// ============================================================================
// lx_ms2.sv - Magic Sound 2 del Aleste LX (modo LX, macro ALESTE_LX)
//
// Reescrita a partir de la idea y el mapa de registros de
// aleste-lx-fpga-sv/src/components/sound/ms2 (hww), que esta a medias: alli
// el registro de control pisa los volumenes, el paso se sale del bloque del
// canal, el mezclador usa el canal 0 para los cuatro y faltan los registros
// de bucle. Aqui: 4 canales que leen muestras de la memoria por DMA (maestro
// Wishbone de 8 bits, compartido en el core), a 48 kHz, con volumen
// izquierdo/derecho por canal y global, bucle, interrupcion de fin de muestra
// y un temporizador propio.
//
// Pagina MMIO 7 (FF0380-FF03FF, MMIO_PAGE_SOUND de aleste-xi-bios):
//   00 CTRL      RW  bit 0 habilita la MS2 (si no, silencio y sin DMA)
//   01 VOL_L     RW  volumen global izquierdo (0-255, 255 = 1)
//   02 VOL_R     RW  volumen global derecho
//   03 STATUS    R   [3:0] fin de muestra de cada canal (pegajoso),
//                    [7:4] canal sonando
//                W   1 = borra el fin de muestra de ese canal
//   04 IRQ_CTRL  RW  bit 0 interrupcion al terminar una muestra (canales con
//                    CH_CTRL.3), bit 1 interrupcion del temporizador
//   05 IRQ_STAT  R   bit 0 fin de muestra pendiente, bit 1 temporizador
//                W   1 = borra
//   10 TIMER_LO  RW  periodo del temporizador en muestras de 48 kHz
//   11 TIMER_HI  RW  (0 = parado; 160 = 300 Hz, 960 = 50 Hz)
//   20-2F, 30-3F, 40-4F, 50-5F: canales 0-3
//     +0 CTRL    RW  bit 0 suena (al ponerlo empieza en START), bit 1 bucle,
//                    bit 2 muestras de 16 bits (si no, de 8 bits), bit 3
//                    interrupcion al terminar. Muestras con signo; las de 16
//                    bits, en little endian.
//     +1..+3     START  direccion fisica de 24 bits (byte bajo primero)
//     +4..+6     END    direccion final (no incluida)
//     +7..+9     LOOP   donde vuelve con bucle al llegar a END
//     +A VOL_L   +B VOL_R   volumen del canal (0-255)
//     +C..+E     STEP   paso en muestras por salida, 8.16 (C y D fraccion,
//                       E parte entera): 1.0 = 010000h = 48 kHz
//     +F         R: [0] sonando, [1] fin; [7:4] byte alto de la posicion
// El byte alto de cada valor de 24 bits (+3, +6, +9) aplica el valor entero.
// ============================================================================
`default_nettype none

module lx_ms2 #(
    parameter int CLK_HZ  = 54_000_000,
    parameter int RATE_HZ = 48_000
) (
    input  logic        clk,
    input  logic        rst,

    // Esclavo (CPU), ya decodificado
    input  logic        cs_i,
    input  logic        we_i,
    input  logic [6:0]  adr_i,
    input  logic [7:0]  dat_i,
    output logic [7:0]  dat_o,
    output logic        ack_o,

    // Maestro de lectura (DMA de muestras)
    output logic        dma_cyc_o,
    output logic [23:0] dma_adr_o,
    input  logic [7:0]  dma_dat_i,
    input  logic        dma_ack_i,
    input  logic        dma_err_i,

    output logic signed [15:0] out_l,
    output logic signed [15:0] out_r,
    output logic        irq_o
);

    localparam int DIV = CLK_HZ / RATE_HZ;

    // ------------------------------------------------------------- Registros
    logic [7:0]  g_ctrl, g_vol_l, g_vol_r, irq_ctrl;
    logic [1:0]  irq_stat;
    logic [15:0] tmr_period, tmr_cnt;

    logic [3:0]  c_play, c_loop, c_16b, c_irq, c_eof;
    logic [23:0] c_start [4], c_end [4], c_lpos [4], c_step [4];
    logic [7:0]  c_vol_l [4], c_vol_r [4];
    logic [15:0] tmp [4];                       // bytes bajos de START/END/LOOP/STEP
    logic [39:0] c_pos [4];                     // posicion 24.16
    logic signed [15:0] c_smp [4];              // muestra actual

    logic ack_q;
    always_ff @(posedge clk) ack_q <= cs_i & ~ack_q;
    assign ack_o = ack_q;
    wire wr = cs_i & we_i & ~ack_q;
    wire       is_ch = (adr_i[6:4] >= 3'd2) && (adr_i[6:4] <= 3'd5);
    wire [1:0] ch    = 2'(adr_i[6:4] - 3'd2);
    wire [3:0] reg_o = adr_i[3:0];

    // ---------------------------------------------------------- Reloj 48 kHz
    logic [$clog2(DIV)-1:0] div;
    logic tick;
    always_ff @(posedge clk) begin
        tick <= 1'b0;
        if (rst) div <= '0;
        else if (div == DIV - 1) begin div <= '0; tick <= 1'b1; end
        else div <= div + 1'b1;
    end

    // -------------------------------------------------------------- DMA
    // En cada tick: avanza la posicion de los canales que suenan y lee la
    // muestra nueva (1 o 2 bytes) de cada uno, por turno.
    typedef enum logic [1:0] {D_IDLE, D_RD0, D_RD1} dstate_t;
    dstate_t dst;
    logic [1:0] dch;                            // canal que se lee
    logic [3:0] todo;                           // canales por leer en este tick
    logic [7:0] lo_byte;
    wire  [23:0] cur_adr = c_pos[dch][39:16];

    always_comb begin
        dma_cyc_o = (dst == D_RD0) || (dst == D_RD1);
        dma_adr_o = (dst == D_RD1) ? cur_adr + 24'd1 : cur_adr;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            g_ctrl <= '0; g_vol_l <= 8'hFF; g_vol_r <= 8'hFF;
            irq_ctrl <= '0; irq_stat <= '0;
            tmr_period <= '0; tmr_cnt <= '0;
            c_play <= '0; c_loop <= '0; c_16b <= '0; c_irq <= '0; c_eof <= '0;
            dst <= D_IDLE; todo <= '0; dch <= '0;
            for (int i = 0; i < 4; i++) begin
                c_start[i] <= '0; c_end[i] <= '0; c_lpos[i] <= '0; c_step[i] <= 24'h010000;
                c_vol_l[i] <= 8'hFF; c_vol_r[i] <= 8'hFF; tmp[i] <= '0;
                c_pos[i] <= '0; c_smp[i] <= '0;
            end
        end else begin
            // ---- temporizador
            if (tick && tmr_period != 16'd0) begin
                if (tmr_cnt <= 16'd1) begin
                    tmr_cnt <= tmr_period;
                    if (irq_ctrl[1]) irq_stat[1] <= 1'b1;
                end else tmr_cnt <= tmr_cnt - 16'd1;
            end

            // ---- avance de los canales (en el tick) y peticion de lectura
            if (tick && g_ctrl[0]) begin
                for (int i = 0; i < 4; i++) begin
                    if (c_play[i]) begin : adv
                        logic [39:0] np;
                        np = c_pos[i] + {16'd0, c_step[i]};
                        if (np[39:16] >= c_end[i]) begin
                            c_eof[i] <= 1'b1;
                            if (c_irq[i] && irq_ctrl[0]) irq_stat[0] <= 1'b1;
                            if (c_loop[i] && c_lpos[i] < c_end[i])
                                np = {c_lpos[i] + (np[39:16] - c_end[i]), np[15:0]};
                            else begin
                                c_play[i] <= 1'b0;
                                c_smp[i]  <= '0;
                            end
                        end
                        c_pos[i] <= np;
                    end
                end
                todo <= c_play;
            end

            // ---- lectura de las muestras, canal a canal
            case (dst)
                D_IDLE: begin
                    if (todo[0])      begin dch <= 2'd0; dst <= D_RD0; end
                    else if (todo[1]) begin dch <= 2'd1; dst <= D_RD0; end
                    else if (todo[2]) begin dch <= 2'd2; dst <= D_RD0; end
                    else if (todo[3]) begin dch <= 2'd3; dst <= D_RD0; end
                end
                D_RD0: if (dma_ack_i || dma_err_i) begin
                    if (c_16b[dch]) begin
                        lo_byte <= dma_ack_i ? dma_dat_i : 8'h00;
                        dst <= D_RD1;
                    end else begin
                        if (c_play[dch]) c_smp[dch] <= dma_ack_i ? {dma_dat_i, 8'h00} : 16'sd0;
                        todo[dch] <= 1'b0;
                        dst <= D_IDLE;
                    end
                end
                D_RD1: if (dma_ack_i || dma_err_i) begin
                    if (c_play[dch]) c_smp[dch] <= dma_ack_i ? {dma_dat_i, lo_byte} : 16'sd0;
                    todo[dch] <= 1'b0;
                    dst <= D_IDLE;
                end
                default: dst <= D_IDLE;
            endcase
            if (!g_ctrl[0]) todo <= '0;

            // ---- escrituras de la CPU
            if (wr) begin
                if (is_ch) begin
                    case (reg_o)
                        4'h0: begin
                            c_loop[ch] <= dat_i[1];
                            c_16b[ch]  <= dat_i[2];
                            c_irq[ch]  <= dat_i[3];
                            c_play[ch] <= dat_i[0];
                            if (dat_i[0] && !c_play[ch]) begin
                                c_pos[ch] <= {c_start[ch], 16'd0};
                                c_eof[ch] <= 1'b0;
                                todo[ch]  <= g_ctrl[0];      // primera muestra ya
                            end
                            if (!dat_i[0]) c_smp[ch] <= '0;
                        end
                        4'h1, 4'h4, 4'h7, 4'hC: tmp[ch][7:0]  <= dat_i;
                        4'h2, 4'h5, 4'h8, 4'hD: tmp[ch][15:8] <= dat_i;
                        4'h3: c_start[ch] <= {dat_i, tmp[ch]};
                        4'h6: c_end[ch]   <= {dat_i, tmp[ch]};
                        4'h9: c_lpos[ch]  <= {dat_i, tmp[ch]};
                        4'hA: c_vol_l[ch] <= dat_i;
                        4'hB: c_vol_r[ch] <= dat_i;
                        4'hE: c_step[ch]  <= {dat_i, tmp[ch]};
                        default: ;
                    endcase
                end else begin
                    case (adr_i)
                        7'h00: g_ctrl  <= dat_i;
                        7'h01: g_vol_l <= dat_i;
                        7'h02: g_vol_r <= dat_i;
                        7'h03: c_eof   <= c_eof & ~dat_i[3:0];
                        7'h04: irq_ctrl <= dat_i;
                        7'h05: irq_stat <= irq_stat & ~dat_i[1:0];
                        7'h10: tmr_period[7:0]  <= dat_i;
                        7'h11: begin tmr_period[15:8] <= dat_i; tmr_cnt <= {dat_i, tmr_period[7:0]}; end
                        default: ;
                    endcase
                end
            end
        end
    end

    assign irq_o = |irq_stat;

    // ---------------------------------------------------------------- Lectura
    always_comb begin
        dat_o = 8'hFF;
        if (is_ch) begin
            case (reg_o)
                4'h0: dat_o = {4'h0, c_irq[ch], c_16b[ch], c_loop[ch], c_play[ch]};
                4'h1: dat_o = c_start[ch][7:0];
                4'h2: dat_o = c_start[ch][15:8];
                4'h3: dat_o = c_start[ch][23:16];
                4'h4: dat_o = c_end[ch][7:0];
                4'h5: dat_o = c_end[ch][15:8];
                4'h6: dat_o = c_end[ch][23:16];
                4'h7: dat_o = c_lpos[ch][7:0];
                4'h8: dat_o = c_lpos[ch][15:8];
                4'h9: dat_o = c_lpos[ch][23:16];
                4'hA: dat_o = c_vol_l[ch];
                4'hB: dat_o = c_vol_r[ch];
                4'hC: dat_o = c_step[ch][7:0];
                4'hD: dat_o = c_step[ch][15:8];
                4'hE: dat_o = c_step[ch][23:16];
                4'hF: dat_o = {c_pos[ch][39:36], 2'b00, c_eof[ch], c_play[ch]};
            endcase
        end else begin
            case (adr_i)
                7'h00: dat_o = g_ctrl;
                7'h01: dat_o = g_vol_l;
                7'h02: dat_o = g_vol_r;
                7'h03: dat_o = {c_play, c_eof};
                7'h04: dat_o = irq_ctrl;
                7'h05: dat_o = {6'd0, irq_stat};
                7'h10: dat_o = tmr_period[7:0];
                7'h11: dat_o = tmr_period[15:8];
                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------- Mezclador
    // Una suma por tick, canal a canal (un multiplicador): suma de 4 canales a
    // 1/4 cada uno, luego el volumen global.
    logic [2:0] mi;
    logic signed [25:0] acc_l, acc_r;
    logic signed [24:0] pl, pr;
    always_comb begin
        pl = c_smp[mi[1:0]] * $signed({1'b0, c_vol_l[mi[1:0]]});
        pr = c_smp[mi[1:0]] * $signed({1'b0, c_vol_r[mi[1:0]]});
    end
    logic signed [17:0] sum_l, sum_r;
    wire  signed [26:0] gl = sum_l * $signed({1'b0, g_vol_l});
    wire  signed [26:0] gr = sum_r * $signed({1'b0, g_vol_r});
    always_ff @(posedge clk) begin
        if (rst) begin
            mi <= 3'd4; acc_l <= '0; acc_r <= '0; out_l <= '0; out_r <= '0;
        end else if (tick) begin
            mi <= 3'd0; acc_l <= '0; acc_r <= '0;
        end else if (mi < 3'd4) begin
            acc_l <= acc_l + 26'(pl);
            acc_r <= acc_r + 26'(pr);
            mi <= mi + 3'd1;
        end else if (mi == 3'd4) begin
            sum_l <= 18'(acc_l >>> 10);               // /256 del volumen, /4 canales
            sum_r <= 18'(acc_r >>> 10);
            mi <= 3'd5;
        end else if (mi == 3'd5) begin
            out_l <= g_ctrl[0] ? 16'(gl >>> 8) : 16'sd0;
            out_r <= g_ctrl[0] ? 16'(gr >>> 8) : 16'sd0;
            mi <= 3'd6;
        end
    end

endmodule
