// ============================================================================
// vga_timing.sv - Generador de barrido para placas con VGA (MiST, SiDi,
// Poseidon...). Sustituye a llhdmi dentro de video_ctrl_vga.
//
// Es el mismo contador que llhdmi (aleste-lx/src/components/video/llhdmi),
// con las mismas salidas de referencia (o_rd, o_newline, o_newframe, o_x,
// o_y) y con el mismo INPUT_LATENCY, porque el CRTC y el hdmi_scaler del
// Aleste LX van esclavos de este barrido. Lo unico que cambia es la salida:
// en vez de TMDS saca RGB de 12 bits, sincronismos y blanking.
//
// Diferencias con llhdmi:
//   - Todo el color (R, G y B) usa el DrawArea retrasado. En llhdmi el canal
//     verde usa el DrawArea sin retrasar y queda un pixel desalineado.
//   - Polaridad de los sincronismos configurable: 720x480 (CEA-861) los
//     lleva negativos, que es lo que esperan los monitores VGA.
// ============================================================================
`default_nettype none

module vga_timing #(
    parameter int INPUT_LATENCY = 1,
    parameter int H_VISIBLE     = 720,
    parameter int H_FRONT_PORCH = 16,
    parameter int H_SYNC_PULSE  = 62,
    parameter int H_BACK_PORCH  = 60,
    parameter int V_VISIBLE     = 480,
    parameter int V_FRONT_PORCH = 9,
    parameter int V_SYNC_PULSE  = 6,
    parameter int V_BACK_PORCH  = 30,
    parameter bit HS_NEG        = 1'b1,
    parameter bit VS_NEG        = 1'b1
)(
    input  logic        i_pixclk,
    input  logic        i_reset,

    input  logic [11:0] i_rgb,        // R4G4B4, igual que lo que entraba a llhdmi

    // Referencias de barrido (mismas que llhdmi)
    output logic        o_rd,
    output logic        o_newline,
    output logic        o_newframe,
    output logic [10:0] o_x,
    output logic [9:0]  o_y,

    // Salida de video
    output logic [11:0] o_rgb,
    output logic        o_hs,
    output logic        o_vs,
    output logic        o_hblank,
    output logic        o_vblank
);
    localparam int H_TOTAL      = H_VISIBLE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH;
    localparam int V_TOTAL      = V_VISIBLE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH;
    localparam int H_SYNC_START = H_VISIBLE + H_FRONT_PORCH;
    localparam int H_SYNC_END   = H_SYNC_START + H_SYNC_PULSE;
    localparam int V_SYNC_START = V_VISIBLE + V_FRONT_PORCH;
    localparam int V_SYNC_END   = V_SYNC_START + V_SYNC_PULSE;

    // Limites con el ancho de los contadores (Verilog-2001, sin casts)
    localparam [10:0] X_LAST       = H_TOTAL - 1;
    localparam [9:0]  Y_LAST       = V_TOTAL - 1;
    localparam [10:0] X_VIS        = H_VISIBLE;
    localparam [10:0] X_VIS_LAST   = H_VISIBLE - 1;
    localparam [9:0]  Y_VIS        = V_VISIBLE;
    localparam [9:0]  Y_VIS_LAST   = V_VISIBLE - 1;
    localparam [10:0] X_SYNC_START = H_SYNC_START;
    localparam [10:0] X_SYNC_END   = H_SYNC_END;
    localparam [9:0]  Y_SYNC_START = V_SYNC_START;
    localparam [9:0]  Y_SYNC_END   = V_SYNC_END;

    logic [10:0] cnt_x = '0;
    logic [9:0]  cnt_y = '0;

    wire end_line  = (cnt_x == X_LAST);
    wire end_frame = (cnt_y == Y_LAST);

    always_ff @(posedge i_pixclk) begin
        if (i_reset) begin
            cnt_x <= '0;
            cnt_y <= '0;
        end else if (end_line) begin
            cnt_x <= '0;
            cnt_y <= end_frame ? 10'd0 : cnt_y + 10'd1;
        end else begin
            cnt_x <= cnt_x + 11'd1;
        end
    end

    assign o_x = cnt_x;
    assign o_y = cnt_y;

    // Etapa 1: igual que llhdmi
    logic newline = 1'b0, newframe = 1'b0;
    logic draw = 1'b0, hsync = 1'b0, vsync = 1'b0, hblank = 1'b1, vblank = 1'b1;

    always_ff @(posedge i_pixclk) begin
        newline  <= (cnt_x == X_VIS_LAST);
        newframe <= (cnt_x == X_VIS_LAST) && (cnt_y == Y_VIS_LAST);
        draw     <= (cnt_x < X_VIS) && (cnt_y < Y_VIS);
        hblank   <= !(cnt_x < X_VIS);
        vblank   <= !(cnt_y < Y_VIS);
        hsync    <= (cnt_x >= X_SYNC_START) && (cnt_x < X_SYNC_END);
        vsync    <= (cnt_y >= Y_SYNC_START) && (cnt_y < Y_SYNC_END);
    end

    assign o_newline  = newline;
    assign o_newframe = newframe;
    assign o_rd       = ~i_reset & draw;

    // Etapa 2: el dato llega INPUT_LATENCY ciclos despues de o_rd
    logic [11:0] rgb_d  = '0;
    logic        draw_d = 1'b0, hs_d = 1'b0, vs_d = 1'b0, hb_d = 1'b1, vb_d = 1'b1;

    always_ff @(posedge i_pixclk) begin
        rgb_d  <= i_rgb;
        draw_d <= draw;
        hs_d   <= hsync;
        vs_d   <= vsync;
        hb_d   <= hblank;
        vb_d   <= vblank;
    end

    wire [11:0] cur_rgb  = (INPUT_LATENCY == 1) ? rgb_d  : i_rgb;
    wire        cur_draw = (INPUT_LATENCY == 1) ? draw_d : draw;
    wire        cur_hs   = (INPUT_LATENCY == 1) ? hs_d   : hsync;
    wire        cur_vs   = (INPUT_LATENCY == 1) ? vs_d   : vsync;
    wire        cur_hb   = (INPUT_LATENCY == 1) ? hb_d   : hblank;
    wire        cur_vb   = (INPUT_LATENCY == 1) ? vb_d   : vblank;

    // Etapa 3: salida registrada (en llhdmi este ciclo lo pone el codificador TMDS)
    always_ff @(posedge i_pixclk) begin
        o_rgb    <= cur_draw ? cur_rgb : 12'h000;
        o_hs     <= cur_hs ^ HS_NEG;
        o_vs     <= cur_vs ^ VS_NEG;
        o_hblank <= cur_hb;
        o_vblank <= cur_vb;
    end

endmodule

`default_nettype wire
