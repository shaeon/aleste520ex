// ============================================================================
// cpc_video.sv - Video del modo CPC del Aleste 520EX, con temporizacion real
//
// Como en la maquina: el CRTC (6845) va libre con sus registros y la imagen
// sale al ritmo que el software programe (312 lineas = 50 Hz en modo AMSTRAD).
// La salida es de 15 kHz; mist_video la dobla a 31 kHz o la deja tal cual.
//
//   clk_v  80 MHz  CRTC (CLKEN 1 MHz), pixel (16 MHz = 80/5), paleta, syncs.
//                  80 = 16*5 = 13,333*6: tambien sirve para el modo Aleste.
//   clk_b  54 MHz  bus del sistema: escrituras de la CPU a CRTC y Gate Array.
//   clk_m 108 MHz  memoria: una lectura de 16 bits por caracter (1 us).
//
// Los cruces entre dominios son handshakes por cambio de nivel (toggle) con
// dos registros de sincronizacion; los datos que cruzan estan quietos varios
// ciclos antes y despues (cambian como mucho una vez por microsegundo).
//
// Gate Array: tintas (16 + borde), modos 0-3 (el cambio de modo se aplica al
// empezar el HSYNC de salida, como el 40010) y sincronismos de salida segun
// el GA40010 (Amstrad_MiST, syncgen_sync.v): HSYNC 2 us despues del del CRTC
// y como mucho 4 us; VSYNC de 4 lineas, 2 lineas despues del del CRTC.
// Colores: PROM D62 del 520EX (modo CPC: 27 colores con 3 niveles de 4).
// ============================================================================
`default_nettype none

module cpc_video (
    // ---- dominio de video (80 MHz)
    input  logic        clk_v,
    input  logic        rst_v,          // sincronizado a clk_v

    // ---- bus del sistema (54 MHz)
    input  logic        clk_b,
    input  logic        rst_b,
    input  logic        bus_crtc,       // ciclo al CRTC (BCxx-BFxx)
    input  logic        bus_ga,         // escritura al Gate Array con D7=0 (tinta)
    input  logic        bus_we,
    input  logic        bus_rs,         // A8: 0 = indice, 1 = dato
    input  logic [7:0]  bus_dat_i,
    output logic [7:0]  bus_dat_o,
    output logic        bus_ack,
    input  logic [1:0]  mode_i,         // modo del Gate Array (RMR), dominio clk_b
    input  logic [7:0]  extport_i,      // FABF del 520EX (clk_b): D1 alta res., D2 MAPMOD, D3 pantalla

    // ---- memoria (108 MHz)
    input  logic        clk_m,
    input  logic        rst_m,
    input  logic        mem_en,         // el puerto de video de la SDRAM es nuestro
    output logic [15:0] mem_addr,       // direccion de byte (par) en la RAM base
    output logic        mem_req,
    input  logic        mem_ack0,
    input  logic [15:0] mem_data,

    // ---- salida (clk_v)
    output logic        ce_pix,         // 16 MHz (13,333 MHz en alta resolucion)
    output logic [7:0]  r, g, b,
    output logic        hs, vs,         // sincronismos de salida (activos a 1); hs: ver al final
    output logic        hblank, vblank,
    output logic        crtc_hs,        // sincronismos del CRTC (interrupciones)
    output logic        crtc_vs,
    output logic        hires_o,        // alta resolucion (pixel de 13,33 MHz), para el divisor del doblador
    input  logic [2:0]  h_off,          // OSD: desplazamiento horizontal (con signo)
    input  logic [2:0]  v_off           // OSD: desplazamiento vertical (con signo)
);

// ============================================================================
// Base de tiempos: 80 MHz -> pixel 16 MHz -> caracter 1 MHz
// ============================================================================
// FABF del 520EX al dominio de video (cambia muy de vez en cuando)
logic [7:0] ext_s1, ext_s2;
always_ff @(posedge clk_v) begin ext_s1 <= extport_i; ext_s2 <= ext_s1; end
wire hires   = ext_s2[1];         // alta resolucion: pixel 13,333 MHz, caracter de 8 pixeles
wire mapmod  = ext_s2[2];         // paleta RGB directa (64 colores)
wire scr_on  = ext_s2[3];         // pantalla encendida

logic [2:0] div5;
logic [3:0] pix;            // pixel dentro del caracter
wire        div_last = hires ? (div5 == 3'd5) : (div5 == 3'd4);    // 80/6 o 80/5
wire [3:0]  pix_last = hires ? 4'd7 : 4'd15;
always_ff @(posedge clk_v) begin
    if (rst_v) begin
        div5 <= '0; pix <= '0;
    end else if (div_last) begin
        div5 <= '0;
        pix  <= (pix >= pix_last) ? 4'd0 : pix + 4'd1;
    end else begin
        div5 <= div5 + 3'd1;
    end
end
wire ce16    = div_last;                                     // avanza el pixel
wire cclk    = ce16 && (pix == pix_last);                    // flanco del CRTC (fin de caracter)
wire ncclk   = ce16 && (pix == (hires ? 4'd3 : 4'd7));       // fase opuesta
assign ce_pix = ce16;

// ============================================================================
// Accesos de la CPU (clk_b -> clk_v)
// ============================================================================
logic        op_tog_b, op_crtc, op_we, op_rs;
logic [7:0]  op_dat;
logic        busy_b;
logic [2:0]  ack_sync_b;
logic        ack_tog_v;
logic [7:0]  rd_dat_v;

always_ff @(posedge clk_b) begin
    if (rst_b) begin
        op_tog_b <= 1'b0; busy_b <= 1'b0; bus_ack <= 1'b0;
        ack_sync_b <= '0;
    end else begin
        ack_sync_b <= {ack_sync_b[1:0], ack_tog_v};
        bus_ack <= 1'b0;
        if (!busy_b && !bus_ack && (bus_crtc || bus_ga)) begin
            op_crtc  <= bus_crtc;
            op_we    <= bus_we;
            op_rs    <= bus_rs;
            op_dat   <= bus_dat_i;
            op_tog_b <= ~op_tog_b;
            busy_b   <= 1'b1;
        end else if (busy_b && (ack_sync_b[2] != ack_sync_b[1])) begin
            busy_b    <= 1'b0;
            bus_ack   <= 1'b1;
            bus_dat_o <= rd_dat_v;
        end
    end
end

logic [2:0] op_sync_v;
wire op_go = (op_sync_v[2] != op_sync_v[1]);
always_ff @(posedge clk_v) op_sync_v <= {op_sync_v[1:0], op_tog_b};

// ============================================================================
// CRTC
// ============================================================================
logic        crtc_en, crtc_ncs, crtc_rnw;
logic [7:0]  crtc_do;
logic [13:0] ma;
logic [4:0]  ra;
logic        de, hsync, vsync;

always_comb begin
    crtc_en  = op_go && op_crtc;
    crtc_ncs = ~(op_go && op_crtc);
    crtc_rnw = ~op_we;
end

UM6845R crtc (
    .CLOCK(clk_v),
    .CLKEN(cclk),
    .nCLKEN(ncclk),
    .nRESET(~rst_v),
    .CRTC_TYPE(1'b0),           // Aleste: UM6845 (tipo 0)
    .ENABLE(crtc_en),
    .nCS(crtc_ncs),
    .R_nW(crtc_rnw),
    .RS(op_rs),
    .DI(op_dat),
    .DO(crtc_do),
    .VSYNC(vsync),
    .HSYNC(hsync),
    .DE(de),
    .FIELD(),
    .CURSOR(),
    .MA(ma),
    .RA(ra)
);
assign crtc_hs = hsync;
assign crtc_vs = vsync;

// ============================================================================
// Gate Array: tintas
// ============================================================================
logic [4:0] pen;
logic [6:0] ink [0:15];             // {RGB directo, color}
logic [6:0] border;

always_ff @(posedge clk_v) begin
    if (rst_v) begin
        pen <= '0; border <= 7'h14;     // negro
        ack_tog_v <= 1'b0;
    end else if (op_go) begin
        if (op_crtc) rd_dat_v <= crtc_do;
        else if (op_we) begin
            if (!op_dat[6]) pen <= op_dat[4:0];
            // MAPMOD: color RGB directo de 6 bits (RRGGBB); si no, color del CPC
            else if (pen[4]) border <= mapmod ? {1'b1, op_dat[5:0]} : {2'b00, op_dat[4:0]};
            else ink[pen[3:0]] <= mapmod ? {1'b1, op_dat[5:0]} : {2'b00, op_dat[4:0]};
        end
        ack_tog_v <= ~ack_tog_v;
    end
end

// ============================================================================
// Sincronismos del Gate Array (GA40010)
// ============================================================================
logic       hsync_d, vsync_d;
logic [2:0] hcnt;           // caracteres desde el inicio del HSYNC del CRTC
logic [2:0] vcnt;           // HSYNC desde el inicio del VSYNC del CRTC
logic       hs_ga, vs_ga, hs_ga_d;

always_ff @(posedge clk_v) begin
    if (rst_v) begin
        hcnt <= '0; vcnt <= 3'd7; hs_ga <= 1'b0; vs_ga <= 1'b0;
        hsync_d <= 1'b0; vsync_d <= 1'b0;
    end else if (cclk) begin
        hsync_d <= hsync;
        vsync_d <= vsync;
        // HSYNC: del 2.o al 5.o caracter del HSYNC del CRTC
        if (!hsync)              hcnt <= '0;
        else if (hcnt != 3'd7)   hcnt <= hcnt + 3'd1;
        hs_ga <= hsync && (hcnt >= 3'd1) && (hcnt <= 3'd4);
        // VSYNC: lineas 2..5 contadas desde el VSYNC del CRTC
        if (vsync && !vsync_d)          vcnt <= '0;
        else if (hsync_d && !hsync && vcnt != 3'd7) vcnt <= vcnt + 3'd1;
        vs_ga <= (vcnt >= 3'd2) && (vcnt <= 3'd5);
    end
end

// Modo: se aplica al empezar el HSYNC de salida
logic [1:0] mode_s1, mode_s2, mode;
always_ff @(posedge clk_v) begin
    mode_s1 <= mode_i;
    mode_s2 <= mode_s1;
    hs_ga_d <= hs_ga;
    if (rst_v) mode <= 2'd1;
    else if (hs_ga && !hs_ga_d) mode <= mode_s2;
end

// ============================================================================
// Lectura de memoria: 2 bytes por caracter, se ven en el caracter siguiente
// ============================================================================
logic [15:0] f_addr;
logic        f_tog;
logic        de_f, hs_f, vs_f;          // estado del caracter que se esta leyendo
logic [15:0] word_next, word;
logic [2:0]  d_sync_v;
logic        d_tog_m;
logic [15:0] d_word_m;

always_ff @(posedge clk_v) begin
    if (rst_v) begin
        f_tog <= 1'b0; d_sync_v <= '0;
    end else begin
        d_sync_v <= {d_sync_v[1:0], d_tog_m};
        if (d_sync_v[2] != d_sync_v[1]) word_next <= d_word_m;
        if (cclk) begin
            // Resolucion normal (CPC, y los modos 0/1 del 520EX, manual 3.3):
            //   A15..A14 = MA13..12, A13..A11 = RA2..0, A10..A1 = MA9..0
            // Alta resolucion (FABF D1, modos 2/3 del 520EX, manual 3.4): 32 KB,
            //   2 bytes por caracter, lineas impares en +16 KB:
            //   {MA13, RA0, RA2..1, MA10..0, byte}
            // (La BIOS de MSX-DOS pone alta resolucion con el registro de modo a 1
            // para 640x200x4 y a 3 para 320x200x16; el BOOTMENU, 3.)
            if (!hires) f_addr <= {ma[13:12], ra[2:0], ma[9:0], 1'b0};
            else        f_addr <= {ma[13], ra[0], ra[2:1], ma[10:0], 1'b0};
            f_tog  <= ~f_tog;
        end
    end
end

logic [2:0] f_sync_m;
always_ff @(posedge clk_m) begin
    if (rst_m) begin
        f_sync_m <= '0; mem_req <= 1'b0; d_tog_m <= 1'b0;
    end else begin
        f_sync_m <= {f_sync_m[1:0], f_tog};
        if ((f_sync_m[2] != f_sync_m[1]) && mem_en) begin
            mem_addr <= {f_addr[15:1], 1'b0};
            mem_req  <= 1'b1;
        end else if (mem_req && mem_ack0) begin
            mem_req  <= 1'b0;
            d_word_m <= mem_data;
            d_tog_m  <= ~d_tog_m;
        end
    end
end

// ============================================================================
// Pixeles
// ============================================================================
logic [15:0] shift;
logic        de_c;                      // DE del caracter que se ve
always_ff @(posedge clk_v) begin
    if (cclk) begin
        word <= word_next;
        de_c <= de_f;
        de_f <= de;                     // se ve un caracter despues de leerlo
        hs_f <= hs_ga;
        vs_f <= vs_ga;
    end
end

wire [3:0] p   = pix;                   // pixel que se saca en este ce16 (word cambia con pix 15 -> 0)
logic [7:0] by;
logic [2:0] q;
logic [3:0] inkn;
always_comb begin
    if (!hires) begin                   // CPC: 2 bytes por caracter, 8 relojes por byte
        by = p[3] ? word[15:8] : word[7:0];       // primero el byte par
        q  = p[2:0];
    end else begin                      // alta resolucion: 2 bytes, 4 relojes por byte
        by = p[2] ? word[15:8] : word[7:0];
        q  = {p[1:0], 1'b0};                       // cada pixel dura la mitad
    end
    case ({hires, mode})
        3'b0_00, 3'b1_00, 3'b1_11: begin  // 16 colores: CPC modo 0 (160 px) / alta res. modos 0 y 3 (320 px)
            inkn = q[2] ? {by[0], by[4], by[2], by[6]} : {by[1], by[5], by[3], by[7]};
        end
        3'b0_01, 3'b1_01, 3'b1_10: begin  // 4 colores: CPC modo 1 (320 px) / alta res. modos 1 y 2 (640 px)
            case (q[2:1])
                2'd0: inkn = {2'b00, by[3], by[7]};
                2'd1: inkn = {2'b00, by[2], by[6]};
                2'd2: inkn = {2'b00, by[1], by[5]};
                default: inkn = {2'b00, by[0], by[4]};
            endcase
        end
        3'b0_10: inkn = {3'b000, by[3'd7 - q]};                 // 2 colores: CPC modo 2 (640 px)
        default: inkn = q[2] ? {2'b00, by[2], by[6]} : {2'b00, by[3], by[7]};  // CPC modo 3
    endcase
end

// Colores de la PROM D62 (RFCOLDAT 0x140): r = bits 1..0, g = 3..2, b = 5..4
function automatic logic [5:0] d62(input logic [4:0] hw);
    case (hw)
        5'h00: d62 = 6'h15; 5'h01: d62 = 6'h15; 5'h02: d62 = 6'h1C; 5'h03: d62 = 6'h1F;
        5'h04: d62 = 6'h10; 5'h05: d62 = 6'h13; 5'h06: d62 = 6'h14; 5'h07: d62 = 6'h17;
        5'h08: d62 = 6'h13; 5'h09: d62 = 6'h1F; 5'h0A: d62 = 6'h0F; 5'h0B: d62 = 6'h3F;
        5'h0C: d62 = 6'h03; 5'h0D: d62 = 6'h33; 5'h0E: d62 = 6'h07; 5'h0F: d62 = 6'h37;
        5'h10: d62 = 6'h10; 5'h11: d62 = 6'h1C; 5'h12: d62 = 6'h0C; 5'h13: d62 = 6'h3C;
        5'h14: d62 = 6'h00; 5'h15: d62 = 6'h30; 5'h16: d62 = 6'h04; 5'h17: d62 = 6'h34;
        5'h18: d62 = 6'h11; 5'h19: d62 = 6'h1D; 5'h1A: d62 = 6'h0D; 5'h1B: d62 = 6'h3D;
        5'h1C: d62 = 6'h01; 5'h1D: d62 = 6'h31; 5'h1E: d62 = 6'h05; default: d62 = 6'h35;
    endcase
endfunction

// Tinta -> RGB222 (r = bits 1..0, g = 3..2, b = 5..4). MAPMOD: el dato es RRGGBB
// (manual: "morado = 22h"); si no, color del CPC por la PROM D62.
function automatic logic [5:0] col6(input logic [6:0] c);
    col6 = c[6] ? {c[1:0], c[3:2], c[5:4]} : d62(c[4:0]);
endfunction

function automatic logic [7:0] lvl(input logic [1:0] v);
    lvl = {v, v, v, v};                 // 0, 85, 170, 255
endfunction

logic [5:0] c6;
logic hs_pipe, vs_pipe;                 // sincronismos del Gate Array alineados con los pixeles
always_ff @(posedge clk_v) begin
    if (ce16) begin
        c6     <= (hs_f || vs_f || !scr_on) ? 6'h00 : col6(de_c ? ink[inkn] : border);
        hs_pipe <= hs_f;
        vs_pipe <= vs_f;
    end
end
assign r = lvl(c6[1:0]);
assign g = lvl(c6[3:2]);
assign b = lvl(c6[5:4]);

// ============================================================================
// Zona visible para mist_video (OSD y scandoubler), como hace un monitor y como
// el crt_filter del core Amstrad (Sorgelig): fija respecto a los sincronismos
// de salida. Horizontal: de 12,25 us a 60,25 us tras el inicio del HSYNC (48 us,
// 768 pixeles de modo 2). Vertical: lineas 30 a 302 tras el VSYNC (272).
// Se mide en ciclos de 80 MHz, asi vale igual en modo normal y en alta resolucion.
// ============================================================================
// Ventana por resolucion, del mismo ancho (48 us) para que el monitor no cambie
// de tamano al cambiar de modo:
//   CPC (R0=63, R2=46): zona activa de 16 a 56 us -> ventana de 12,25 a 60,25
//   alta resolucion (tabla MC6845H del BOOTMENU: R0=6Bh, R1=50h, R2=51h, a
//   0,6 us por caracter): zona activa de 15,6 a 63,6 us (15 + un caracter de
//   lectura adelantada) -> ventana de 15,6 a 63,6
//   (antes se usaba la del CPC y se cortaban ~5 caracteres por la derecha)
// h_off / v_off (OSD, como H/V centre de NewBrain): 3 bits con signo, en pasos
// de 8 pixeles de modo 2 (0,5 us) y de 2 lineas.
wire signed [12:0] hoff = 13'($signed(h_off)) * 13'sd40;
wire signed [8:0]  voff = 9'($signed(v_off)) * 9'sd2;
// La ventana queda fija sobre la imagen (y con ella el OSD de mist_video);
// h_off y v_off mueven los sincronismos de salida, que es lo que mueve la
// imagen en el monitor (ver al final).
// Ventana de 48 us en los dos modos, a la misma distancia del HSYNC de salida
// (12,25 us): es la imagen centrada de un monitor PAL de 15 kHz (activa de 10,5
// a 62,5 us) y, pasada por el doblador de mist_video (que empieza cada linea
// al final del HSYNC y lo pone a mitad de escala), la de 576p en 31 kHz (6,1 us
// tras el sincronismo; el estandar, 6,2). En alta resolucion la ventana es la
// zona activa justa (15,6 a 63,6 us tras el HSYNC del Gate Array). (Un margen
// a la izquierda en alta resolucion la desplazaba 2 us a la derecha: en 15 kHz
// NC se salia por la derecha.)
wire [12:0] HB_END   = hires ? 13'd1248 : 13'd980;     // 15,6 us / 12,25 us
wire [12:0] HB_START = hires ? 13'd5088 : 13'd4820;    // 63,6 us / 60,25 us
wire [8:0]  VB_END   = 9'd30;
wire [8:0]  VB_START = 9'd302;
logic [12:0] hpos;
logic [8:0]  vline;
logic        hs_d2, vs_d2;
always_ff @(posedge clk_v) begin
    hs_d2 <= hs_pipe;
    if (hs_pipe && !hs_d2) begin
        hpos   <= '0;
        hblank <= 1'b1;
        vs_d2  <= vs_pipe;
        if (vs_pipe && !vs_d2) begin vline <= '0; vblank <= 1'b1; end
        else if (vline != 9'h1FF) vline <= vline + 9'd1;
    end else if (hpos != 13'h1FFF) begin
        hpos <= hpos + 13'd1;
    end
    if (hpos == HB_END) begin
        hblank <= 1'b0;
        if (vline == VB_END) vblank <= 1'b0;
    end
    if (hpos == HB_START) begin
        hblank <= 1'b1;
        if (vline == VB_START) vblank <= 1'b1;
    end
end

// Sincronismos de salida, a distancia fija de la ventana visible en todos los
// modos. Con H/V centre a 0, la misma que da el Gate Array en el CPC: HSYNC
// 12,25 us antes de la imagen y VSYNC 30 lineas antes (la de siempre: un
// monitor ya ajustado no ve cambio). H centre (+ = imagen a la derecha) y
// V centre (+ = imagen mas abajo) cambian esa distancia; si el sincronismo
// tiene que ir antes del principio de la linea (o del cuadro) del Gate Array,
// se genera al final de la anterior: se mide la longitud real de la linea y
// del cuadro.
logic [12:0] line_len;
logic [8:0]  frame_len;
always_ff @(posedge clk_v) begin
    if (hs_pipe && !hs_d2) line_len <= hpos + 13'd1;
    if (hs_pipe && !hs_d2 && vs_pipe && !vs_d2) frame_len <= vline + 9'd1;
end

wire signed [14:0] hs_rel = $signed({2'b00, HB_END}) - (15'sd980 + 15'(hoff));   // inicio del HSYNC
wire [12:0] hs_start = (hs_rel < 0) ? 13'(hs_rel + $signed({2'b00, line_len})) : 13'(hs_rel);
wire [13:0] hs_end   = {1'b0, hs_start} + 14'd320;                                // 4 us
wire        hs_wrap  = hs_end >= {1'b0, line_len};
always_ff @(posedge clk_v)
    hs <= hs_wrap ? ((hpos >= hs_start) || ({1'b0, hpos} < hs_end - {1'b0, line_len}))
                  : ((hpos >= hs_start) && ({1'b0, hpos} < hs_end));

wire signed [10:0] vs_rel = $signed({2'b00, VB_END}) - (11'sd30 + 11'(voff));     // linea del VSYNC
wire [8:0]  vs_start = (vs_rel < 0) ? 9'(vs_rel + $signed({2'b00, frame_len})) : 9'(vs_rel);
wire [9:0]  vs_end   = {1'b0, vs_start} + 10'd4;                                   // 4 lineas
wire        vs_wrap  = vs_end >= {1'b0, frame_len};
always_ff @(posedge clk_v)
    vs <= vs_wrap ? ((vline >= vs_start) || ({1'b0, vline} < vs_end - {1'b0, frame_len}))
                  : ((vline >= vs_start) && ({1'b0, vline} < vs_end));

assign hires_o = hires;

endmodule

`default_nettype wire
