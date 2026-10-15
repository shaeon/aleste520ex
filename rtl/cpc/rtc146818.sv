// ============================================================================
// rtc146818.sv - Reloj MC146818 (K512VI1) del Aleste 520EX
//
// En el 520EX el reloj comparte el puerto A de la PPI con el AY (FABF D5=1
// lo selecciona) y PC2..PC0 de la PPI dan la orden (BOOTMENU, RD_CLOCK y
// WR_CLOCK):
//     2 = AS: el puerto A lleva la direccion del registro
//     4 = DS escritura: el puerto A lleva el dato
//     5 = DS lectura: el reloj pone el dato en el puerto A
//
// 64 registros: 0-9 hora y fecha (0 seg, 2 min, 4 horas, 6 dia de la semana
// 1-7, 7 dia, 8 mes, 9 ano), A-D de control, 0E-3F RAM (configuracion del
// SETUP y sumas de comprobacion de MSX-DOS). Lo que usa el software:
//   - Registro A: UIP (bit 7) a 1 los 244 us antes de cada actualizacion.
//   - Registro B: SET (bit 7) para la hora para poder escribirla; DM (bit 2)
//     binario (1, lo que pone el SETUP) o BCD (0); 24/12 (bit 1, solo 24 h).
//   - Registro C: UF (bit 4) se pone a 1 al acabar cada actualizacion (una por
//     segundo) y se borra al leer el registro. El SETUP solo lee la hora con
//     UF a 1 (rutina CLOCK); sin el, la pantalla del SETUP se quedaba en XX.
//   - Registro D: VRT (bit 7) a 1, bateria bien.
// Calendario completo: dias por mes, bisiestos (ano = anos desde 1980, como
// el SETUP), dia de la semana.
//
// Puerta de copia (cmos_*): los 64 registros se guardan en ALESTE.CMO y se
// recuperan al montarlo; "dirty" se pone a 1 cuando la CPU cambia algo de 0A
// en adelante (la hora no se guarda: cambia cada segundo).
//
// Puesta en hora (set_*): la hora del firmware de MiST (si la placa tiene
// reloj), en BCD; se convierte al modo del reloj.
//
// Cambio de DM: cuando la CPU cambia el bit DM del registro B, la hora y la
// fecha (0, 2, 4, 7, 8, 9) se convierten al formato nuevo, un campo por ciclo
// (en un solo ciclo no cumpliria los 54 MHz de la SiDi). Un MC146818 real no lo
// hace, pero el firmware del 520EX pasa el reloj a binario sin volver a
// escribir la hora: con una CMOS en blanco (DM = 0) la hora puesta por el
// firmware de MiST/MiSTer, en BCD, se leia como binario (23:52 salia 35:82).
// ============================================================================
`default_nettype none

module rtc146818 #(
    parameter int CLK_HZ = 54_000_000
)(
    input  logic       clk,
    input  logic       reset,
    input  logic       sel,         // FABF D5: el puerto A de la PPI va al reloj
    input  logic [2:0] cmd,         // PC2..PC0 de la PPI
    input  logic [7:0] din,         // salida del puerto A de la PPI
    output logic [7:0] dout,        // al puerto A de la PPI
    output logic       drive,       // el reloj pone el dato (lectura)

    input  logic       cmos_we,     // carga desde el fichero
    input  logic [5:0] cmos_addr,
    input  logic [7:0] cmos_din,
    output logic [7:0] cmos_dout,
    output logic       dirty,
    input  logic       cmos_clean,

    input  logic       set_time,    // pulso: poner en hora (valores en BCD)
    input  logic [7:0] set_sec, set_min, set_hour, set_day, set_mon, set_year,  // ano 00-99 = 2000-2099
    input  logic [2:0] set_wday     // 0 domingo - 6 sabado
);

localparam int UIP_CYCLES = CLK_HZ / 4096;     // 244 us

logic [5:0] addr;
logic [7:0] ram [0:63];
wire        bin   = ram[6'h0B][2];             // DM
wire        setb  = ram[6'h0B][7];             // SET: hora parada
logic       uf;                                // registro C, bit 4
logic       drive_d;
logic [2:0] step;                              // 0 parado, 1-6 campo que se actualiza
logic [2:0] conv;                              // 0 parado, 1-6 campo que se convierte (cambio de DM)
logic       conv_bin;                          // formato de destino: 1 binario, 0 BCD

// ---------------------------------------------------------------- utilidades
// Todo en el formato del registro (binario o BCD segun DM), sin convertir: en
// la SiDi, convertir en un solo ciclo (con /10 y %10) no cumplia los 54 MHz.
function automatic logic [7:0] inc(input logic [7:0] v, input logic b);
    if (b) inc = v + 8'd1;
    else   inc = (v[3:0] == 4'd9) ? {v[7:4] + 4'd1, 4'd0} : v + 8'd1;
endfunction
function automatic logic [7:0] k(input logic [7:0] bin_v, input logic [7:0] bcd_v, input logic b);
    k = b ? bin_v : bcd_v;                     // constante en el formato del registro
endfunction
function automatic logic leap(input logic [7:0] y, input logic b);   // anos desde 1980 (1980 bisiesto)
    if (b) leap = (y[1:0] == 2'd0);
    else   leap = y[4] ? (y[3:0] == 4'd2 || y[3:0] == 4'd6)                       // decena impar
                       : (y[3:0] == 4'd0 || y[3:0] == 4'd4 || y[3:0] == 4'd8);    // decena par
endfunction
function automatic logic [7:0] last_day(input logic [7:0] m, input logic [7:0] y, input logic b);
    if (m == k(8'd2, 8'h02, b))
        last_day = leap(y, b) ? k(8'd29, 8'h29, b) : k(8'd28, 8'h28, b);
    else if (m == k(8'd4, 8'h04, b) || m == k(8'd6, 8'h06, b) || m == k(8'd9, 8'h09, b) || m == k(8'd11, 8'h11, b))
        last_day = k(8'd30, 8'h30, b);
    else
        last_day = k(8'd31, 8'h31, b);
endfunction
function automatic logic [7:0] bcd2b(input logic [7:0] v);                 // x10 = x8 + x2
    bcd2b = {1'b0, v[7:4], 3'b000} + {3'b000, v[7:4], 1'b0} + {4'b0000, v[3:0]};
endfunction
function automatic logic [7:0] b2bcd(input logic [7:0] v);                 // 0-99; v/10 = v*205 >> 11
    logic [15:0] p;
    logic [3:0]  t;
    p = {8'd0, v} * 16'd205;
    t = p[14:11];
    b2bcd = {t, 4'(v - {t, 3'b000} - {3'b000, t, 1'b0})};                // unidades = v - 10*decenas
endfunction

// ---------------------------------------------------------------- reloj
logic [$clog2(CLK_HZ)-1:0] div;
wire uip = !setb && (div >= CLK_HZ - UIP_CYCLES);

always_ff @(posedge clk) begin
    if (cmos_clean) dirty <= 1'b0;

    if (cmos_we) begin                      // carga desde la SD: tambien durante el reset
        ram[cmos_addr] <= cmos_din;
    end else if (reset) begin
        div <= '0;
        dirty <= 1'b0;
        uf <= 1'b0;
        step <= 3'd0;
        conv <= 3'd0;
    end else begin
        // ---- actualizacion de cada segundo: un campo por ciclo, solo con acarreo
        if (setb) begin div <= '0; step <= 3'd0; end
        else if (div == CLK_HZ - 1) begin
            div  <= '0;
            uf   <= 1'b1;
            step <= 3'd1;
        end else
            div <= div + 1'b1;

        case (step)
            3'd1: if (ram[0] == k(8'd59, 8'h59, bin)) begin ram[0] <= 8'h00; step <= 3'd2; end
                  else begin ram[0] <= inc(ram[0], bin); step <= 3'd0; end
            3'd2: if (ram[2] == k(8'd59, 8'h59, bin)) begin ram[2] <= 8'h00; step <= 3'd3; end
                  else begin ram[2] <= inc(ram[2], bin); step <= 3'd0; end
            3'd3: if (ram[4] == k(8'd23, 8'h23, bin)) begin ram[4] <= 8'h00; step <= 3'd4; end
                  else begin ram[4] <= inc(ram[4], bin); step <= 3'd0; end
            3'd4: begin                                            // dia de la semana (1-7) y dia
                  ram[6] <= (ram[6] >= 8'd7) ? 8'd1 : ram[6] + 8'd1;
                  if (ram[7] == last_day(ram[8], ram[9], bin)) begin ram[7] <= 8'h01; step <= 3'd5; end
                  else begin ram[7] <= inc(ram[7], bin); step <= 3'd0; end
                  end
            3'd5: if (ram[8] == k(8'd12, 8'h12, bin)) begin ram[8] <= 8'h01; step <= 3'd6; end
                  else begin ram[8] <= inc(ram[8], bin); step <= 3'd0; end
            3'd6: begin
                  ram[9] <= (ram[9] == k(8'd99, 8'h99, bin)) ? 8'h00 : inc(ram[9], bin);
                  step <= 3'd0;
                  end
            default: ;
        endcase

        // ---- puesta en hora desde MiST (BCD; ano 2000-2099 -> anos desde 1980)
        // (llega en BCD: en modo BCD se guarda tal cual; en binario, decenas*10+unidades)
        if (set_time) begin
            ram[0] <= bin ? bcd2b(set_sec)  : set_sec;
            ram[2] <= bin ? bcd2b(set_min)  : set_min;
            ram[4] <= bin ? bcd2b(set_hour) : set_hour;
            ram[6] <= 8'(set_wday) + 8'd1;                       // 1-7, igual en los dos
            ram[7] <= bin ? bcd2b(set_day)  : set_day;
            ram[8] <= bin ? bcd2b(set_mon)  : set_mon;
            ram[9] <= bin ? bcd2b(set_year) + 8'd20                               // 2000 = 1980 + 20
                          : {set_year[7:4] + 4'd2 - ((set_year[7:4] >= 4'd8) ? 4'd10 : 4'd0), set_year[3:0]};
            div    <= '0;
            step   <= 3'd0;
        end

        // ---- cambio de DM: hora y fecha al formato nuevo, un campo por ciclo
        if (conv != 3'd0) begin
            case (conv)
                3'd1: ram[0] <= conv_bin ? bcd2b(ram[0]) : b2bcd(ram[0]);
                3'd2: ram[2] <= conv_bin ? bcd2b(ram[2]) : b2bcd(ram[2]);
                3'd3: ram[4] <= conv_bin ? bcd2b(ram[4]) : b2bcd(ram[4]);
                3'd4: ram[7] <= conv_bin ? bcd2b(ram[7]) : b2bcd(ram[7]);
                3'd5: ram[8] <= conv_bin ? bcd2b(ram[8]) : b2bcd(ram[8]);
                default: ram[9] <= conv_bin ? bcd2b(ram[9]) : b2bcd(ram[9]);
            endcase
            conv <= (conv == 3'd6) ? 3'd0 : conv + 3'd1;
        end

        // ---- acceso de la CPU
        if (sel) begin
            if (cmd == 3'd2) addr <= din[5:0];
            else if (cmd == 3'd4) begin
                if (addr == 6'h0B && din[2] != ram[6'h0B][2]) begin   // cambia DM
                    conv     <= 3'd1;
                    conv_bin <= din[2];
                end
                if (addr != 6'h0C && addr != 6'h0D) ram[addr] <= din;
                if (addr >= 6'h0A) dirty <= 1'b1;           // la hora no hace falta guardarla
            end
        end
        // leer el registro C borra sus banderas (al acabar la lectura)
        if (drive_d && !drive && addr == 6'h0C) uf <= 1'b0;
    end
end

always_ff @(posedge clk) drive_d <= drive;

always_comb begin
    case (addr)
        6'h0A: dout = {uip, ram[6'h0A][6:0]};
        6'h0C: dout = {1'b0, 2'b00, uf, 4'b0000};          // IRQF, PF, AF = 0; UF
        6'h0D: dout = 8'h80;                                // VRT: bateria bien
        default: dout = ram[addr];
    endcase
end
assign drive     = sel && (cmd == 3'd5);
assign cmos_dout = ram[cmos_addr];

// Valores iniciales (sin fichero ni hora de MiST): 12:00:00, jueves 1-1-2026,
// en binario y 24 h, como deja el reloj el SETUP del 520EX
initial begin
    for (int i = 0; i < 64; i++) ram[i] = 8'h00;
    ram[6'h04] = 8'd12; ram[6'h06] = 8'd5; ram[6'h07] = 8'd1; ram[6'h08] = 8'd1; ram[6'h09] = 8'd46;
    ram[6'h0A] = 8'h26; ram[6'h0B] = 8'h06;
    drive_d = 1'b0;
end

endmodule

`default_nettype wire
