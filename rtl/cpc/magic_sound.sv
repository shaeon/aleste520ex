// ============================================================================
// magic_sound.sv - MagicSound del Aleste 520EX (placa original de Patisonic)
//
// No es el "ms2" del Aleste LX (un diseno nuevo, incompatible): es la tarjeta
// que programa el reproductor MAG.COM (Aleste520EX/MagicSound/SRC/mag.txt).
// Cuatro canales de muestras de 8 bits:
//
//   8254 (contador del canal, modo 2, reloj de 16 MHz) --pulso--> peticion DMA
//   8237 (canal DMA, lectura con autoinicio) --byte de la RAM--> DAC del canal
//   DAC de 8 bits sin signo (80h = silencio) x volumen de 6 bits --> mezcla
//   fin de bloque (TC) --> NMI (el reproductor reprograma el bucle)
//
// Puertos (A10 = A5 = 0; A9..A8 eligen el bloque):
//   F8D0-F8DF  8237: 0-7 direccion/longitud de los canales 0-3, 8 orden /
//              estado (TC en D3..D0, se borra al leer), A mascara de un canal,
//              B modo, C borra el biestable, D reset, E desenmascara todo,
//              F mascara de los 4
//   F9D8-F9DB  8254 n.1: contadores 0-2 = canales A-C (DMA 0-2), DB control
//   F9D4-F9D7  8254 n.2: contador 0 = canal D (DMA 3), contador 1 (E) sin
//              uso conocido, D7 control
//   FAD0-FAD3  volumen de los canales A-D: el byte entero multiplica la muestra
//              (MAG.COM escribe volumen*4; ver la mezcla)
//   FBD0-FBDF  mapper de la DMA: A3..A2 = canal, A1..A0 = cuarto de los 64 KB
//              del canal; la pagina (16 KB de la RAM del 520EX) se escribe
//              invertida (MAG hace CPL): pagina = ~D5..D0 (6 bits, msdesc.txt;
//              con 5 bits las paginas 32-63 se leian en 0-31 y esos canales callaban)
//
// Reloj de los contadores: 4 MHz, el del bus (esquema de la placa y
// Caprice32-Aleste). El contador E (modo 3, /4) multiplexa en la placa real un
// unico DAC entre los 4 canales; aqui se suman directamente.
// ============================================================================
`default_nettype none

module magic_sound (
    input  logic        clk,            // 54 MHz (clk_bus)
    input  logic        reset,

    // Bus de la CPU (E/S)
    input  logic        cs,
    input  logic        we,
    input  logic [9:0]  adr,            // A9..A0
    input  logic [7:0]  din,
    output logic [7:0]  dout,
    output logic        ack,

    // Lectura de muestras (maestro Wishbone de 8 bits)
    output logic        dma_cyc,
    output logic [23:0] dma_adr,
    input  logic [7:0]  dma_dat,
    input  logic        dma_ack,
    input  logic        dma_err,

    output logic        nmi,            // pulso al acabar un bloque (TC)
    output logic signed [15:0] out_l,
    output logic signed [15:0] out_r
);

// ---------------------------------------------------------------- 4 MHz
// Reloj de los 8254: CLK del bus del Aleste (CLKV), el de la CPU. En el esquema
// (al-ms-sch-1.pdf) CLK0-CLK2 de D3 y D4 van a CLK; Caprice32-Aleste usa lo
// mismo (frecuencia = 4 MHz / divisor). 4 MHz = 54 MHz * 2/27.
logic [5:0] acc16;
logic       ce16;
always_ff @(posedge clk) begin
    if (acc16 >= 6'd25) begin acc16 <= acc16 - 6'd25; ce16 <= 1'b1; end   // +2, -27
    else begin acc16 <= acc16 + 6'd2; ce16 <= 1'b0; end
end

// ---------------------------------------------------------------- registros
// 8237
logic [15:0] base_adr [0:3], cur_adr [0:3], base_cnt [0:3], cur_cnt [0:3];
logic [7:0]  dmode    [0:3];
logic [3:0]  dmask, tc_stat;
logic        ff;                         // biestable alto/bajo
// 8254: 2 chips x 3 contadores
logic [15:0] reload [0:5], tcount [0:5];
logic [1:0]  rwmode [0:5];
logic        lsb_next [0:5];             // con RW=11: el siguiente byte es el bajo
logic        loaded [0:5];
// volumen y mapper de la DMA
logic [7:0]  vol  [0:3];              // byte entero (MAG.COM escribe volumen*4)
logic [5:0]  page [0:3][0:3];        // 6 bits (msdesc.txt: D5..D0 invertido)
// DAC
logic [7:0]  dac  [0:3];

wire [1:0] blk  = adr[9:8];
wire [3:0] reg4 = adr[3:0];
// contador: chip n.1 (A3=1) -> 0-2, chip n.2 (A3=0) -> 3-5
wire [2:0] tidx = adr[3] ? {1'b0, adr[1:0]} : 3'd3 + {1'b0, adr[1:0]};

logic dreq [0:3];                        // peticion pendiente por canal
logic       dma_state;
logic [1:0] dma_ch;
logic [6:0] nmi_cnt;

// ---------------------------------------------------------------- bus
always_ff @(posedge clk) begin
    ack <= 1'b0;
    if (reset) begin
        dmask <= 4'hF; tc_stat <= '0; ff <= 1'b0;
        for (int i = 0; i < 4; i++) begin
            vol[i] <= 8'h00; dmode[i] <= '0;
            for (int q = 0; q < 4; q++) page[i][q] <= 6'(q);
        end
        for (int i = 0; i < 6; i++) begin rwmode[i] <= 2'b11; lsb_next[i] <= 1'b1; loaded[i] <= 1'b0; end
    end else if (cs && !ack) begin
        ack  <= 1'b1;
        dout <= 8'hFF;
        case (blk)
        2'd0: begin                                          // ---- 8237
            if (reg4 < 4'd8) begin
                if (we) begin
                    if (!reg4[0]) begin
                        if (!ff) begin base_adr[reg4[2:1]][7:0] <= din; cur_adr[reg4[2:1]][7:0] <= din; end
                        else     begin base_adr[reg4[2:1]][15:8] <= din; cur_adr[reg4[2:1]][15:8] <= din; end
                    end else begin
                        if (!ff) begin base_cnt[reg4[2:1]][7:0] <= din; cur_cnt[reg4[2:1]][7:0] <= din; end
                        else     begin base_cnt[reg4[2:1]][15:8] <= din; cur_cnt[reg4[2:1]][15:8] <= din; end
                    end
                end else begin
                    dout <= reg4[0] ? (ff ? cur_cnt[reg4[2:1]][15:8] : cur_cnt[reg4[2:1]][7:0])
                                    : (ff ? cur_adr[reg4[2:1]][15:8] : cur_adr[reg4[2:1]][7:0]);
                end
                ff <= ~ff;
            end else if (we) begin
                case (reg4)
                    4'hA: dmask[din[1:0]] <= din[2];
                    4'hB: dmode[din[1:0]] <= din;
                    4'hC: ff <= 1'b0;
                    4'hD: begin dmask <= 4'hF; ff <= 1'b0; tc_stat <= '0; end
                    4'hE: dmask <= 4'h0;
                    4'hF: dmask <= din[3:0];
                    default: ;
                endcase
            end else if (reg4 == 4'h8) begin
                dout <= {4'h0, tc_stat};
                tc_stat <= '0;
            end
        end
        2'd1: if (we) begin                                  // ---- 8254
            if (adr[1:0] == 2'd3) begin
                // palabra de control: SC = D7..D6 (contador del chip), RW = D5..D4
                if (din[5:4] != 2'b00) begin
                    rwmode  [(adr[3] ? 3'd0 : 3'd3) + {1'b0, din[7:6]}] <= din[5:4];
                    lsb_next[(adr[3] ? 3'd0 : 3'd3) + {1'b0, din[7:6]}] <= 1'b1;
                end
            end else begin
                case (rwmode[tidx])
                    2'b01: begin reload[tidx][7:0]  <= din; reload[tidx][15:8] <= 8'h00; loaded[tidx] <= 1'b1; end
                    2'b10: begin reload[tidx][15:8] <= din; reload[tidx][7:0]  <= 8'h00; loaded[tidx] <= 1'b1; end
                    default: begin
                        if (lsb_next[tidx]) reload[tidx][7:0] <= din;
                        else begin reload[tidx][15:8] <= din; loaded[tidx] <= 1'b1; end
                        lsb_next[tidx] <= ~lsb_next[tidx];
                    end
                endcase
            end
        end
        2'd2: if (we) vol[adr[1:0]] <= din;                  // ---- volumen (byte entero, como Caprice32-Aleste)
        2'd3: if (we) page[adr[3:2]][adr[1:0]] <= ~din[5:0]; // ---- mapper de la DMA (6 bits)
        endcase
    end

    // ---- contadores (modo de pulsos): el contador de cada canal pide un byte
    for (int i = 0; i < 6; i++) begin
        if (loaded[i]) begin
            loaded[i] <= 1'b0;
            tcount[i] <= reload[i];
        end else if (ce16) begin
            if (tcount[i] <= 16'd1) begin
                tcount[i] <= reload[i];
                if (i <= 3) dreq[i] <= 1'b1;        // contadores A-D -> DMA 0-3 (el E no pide)
            end else
                tcount[i] <= tcount[i] - 16'd1;
        end
    end

    // ---- DMA: un canal cada vez, el de numero mas bajo con peticion
    if (reset) begin
        dma_cyc <= 1'b0; dma_state <= 1'b0;
        for (int i = 0; i < 4; i++) begin dreq[i] <= 1'b0; dac[i] <= 8'h80; end
        nmi_cnt <= '0;
    end else if (!dma_state) begin
        for (int i = 3; i >= 0; i--)
            if (dreq[i] && !dmask[i]) dma_ch <= 2'(i);
        if ((dreq[0] && !dmask[0]) || (dreq[1] && !dmask[1]) || (dreq[2] && !dmask[2]) || (dreq[3] && !dmask[3]))
            dma_state <= 1'b1;
        for (int i = 0; i < 4; i++) if (dmask[i]) dreq[i] <= 1'b0;
    end else if (!dma_cyc) begin
        dma_adr <= {2'b00, 2'b00, page[dma_ch][cur_adr[dma_ch][15:14]], cur_adr[dma_ch][13:0]};
        dma_cyc <= 1'b1;
    end else if (dma_ack || dma_err) begin
        dma_cyc   <= 1'b0;
        dma_state <= 1'b0;
        dreq[dma_ch] <= 1'b0;
        if (dma_ack) dac[dma_ch] <= dma_dat;
        cur_adr[dma_ch] <= dmode[dma_ch][5] ? cur_adr[dma_ch] - 16'd1 : cur_adr[dma_ch] + 16'd1;
        if (cur_cnt[dma_ch] == 16'd0) begin                  // fin de bloque (TC)
            tc_stat[dma_ch] <= 1'b1;
            nmi_cnt <= 7'd127;
            if (dmode[dma_ch][4]) begin                      // autoinicio
                cur_adr[dma_ch] <= base_adr[dma_ch];
                cur_cnt[dma_ch] <= base_cnt[dma_ch];
            end else begin
                cur_cnt[dma_ch] <= 16'hFFFF;
                dmask[dma_ch]   <= 1'b1;
            end
        end else
            cur_cnt[dma_ch] <= cur_cnt[dma_ch] - 16'd1;
    end
    if (!reset && nmi_cnt != 0) nmi_cnt <= nmi_cnt - 7'd1;
end

assign nmi = (nmi_cnt != 0);

// ---------------------------------------------------------------- mezcla
// Muestra sin signo -> con signo, por el byte de volumen tal como se escribe
// (como Caprice32-Aleste: samp += (muestra - 80h) * volumen). El MAG.COM del
// disco escribe volumen*4 (SLA A dos veces: D7..D2); el fuente mag.txt y
// msdesc.txt dicen D5..D0 con 40h = silencio, pero el binario no usa eso.
// Antes se tomaba D6 como silencio y casi todos los instrumentos callaban.
// Estereo como en el Amiga: A y D a la izquierda, B y C a la derecha.
function automatic logic signed [16:0] chan(input logic [7:0] s, input logic [7:0] v);
    logic signed [8:0] x;
    x = $signed({1'b0, s}) - 9'sd128;
    chan = 17'(x * $signed({1'b0, v}));
endfunction

always_ff @(posedge clk) begin
    out_l <= 16'((18'(chan(dac[0], vol[0])) + 18'(chan(dac[3], vol[3]))) >>> 2);
    out_r <= 16'((18'(chan(dac[1], vol[1])) + 18'(chan(dac[2], vol[2]))) >>> 2);
end

endmodule

`default_nettype wire
