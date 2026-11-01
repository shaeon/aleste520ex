// ============================================================================
// lx_sys.sv - Dispositivos de sistema del Aleste LX (modo LX, macro ALESTE_LX)
//
// Pagina MMIO 0 (FF0000-FF007F), como en aleste-xi-bios (memory_aleste.inc):
//   FF0000-FF001F  PIC     controlador de interrupciones de 16 lineas
//   FF0040-FF005F  TIMER   temporizador del sistema
// (FF0020 IPC y FF0060 RTC quedan para despues: sin dispositivo responden FF.)
//
// PIC: registros como en wb_z80_pic.sv de hww (aleste-lx-fpga-sv), en IM 1:
// la CPU va a 0038h y el manejador lee el estado y borra lo atendido.
//   +0 MASK_LO   RW  1 = linea habilitada
//   +1 MASK_HI   RW
//   +2 VECTOR    RW  vector base para IM 2 (int_vec_o)
//   +3 STATUS_LO R   pendientes y habilitadas
//   +4 STATUS_HI R
//   +5 PEND_LO   R   pendientes (aunque esten enmascaradas)
//   +6 PEND_HI   R
//   +7 CLEAR_LO  W   1 = borra el pendiente
//   +8 CLEAR_HI  W
// Las lineas se capturan por flanco de subida. INT se mantiene mientras haya
// alguna pendiente y habilitada.
// Lineas (lx_pic_controller.md de hww): 0 STORAGE, 1 DMA_COM, 2 GPU (VBlank),
// 3 AUDIO, 4 LEGACY (interrupcion del Gate Array), 5 IPC, 6 SYSTIMER.
//
// TIMER: cuenta microsegundos.
//   +0 CTRL      RW  bit 0 marcha, bit 1 periodico (si no, una sola vez)
//   +1 RELOAD_LO RW  periodo en microsegundos (0 = 65536)
//   +2 RELOAD_HI RW
//   +3 COUNT_LO  R   cuenta que queda (al leer LO se congela HI)
//   +4 COUNT_HI  R
//   +5 TICKS_LO  R   contador libre de milisegundos (16 bits; al leer LO se congela HI)
//   +6 TICKS_HI  R
// Al llegar a cero levanta la linea 6 del PIC.
// ============================================================================
`default_nettype none

module lx_sys #(
    parameter int CLK_HZ = 54_000_000
) (
    input  logic        clk,
    input  logic        rst,

    // Bus de sistema (ya decodificado: pagina MMIO 0)
    input  logic        cs_i,          // ciclo hacia FF0000-FF007F
    input  logic        we_i,
    input  logic [6:0]  adr_i,
    input  logic [7:0]  dat_i,
    output logic [7:0]  dat_o,
    output logic        ack_o,

    input  logic [15:0] irq_i,         // lineas de interrupcion (la 6 es la del temporizador, interna)
    output logic        int_o,
    output logic [7:0]  int_vec_o
);

    localparam int US_DIV = CLK_HZ / 1_000_000;

    wire pic_sel = (adr_i[6:5] == 2'b00);
    wire tmr_sel = (adr_i[6:5] == 2'b10);

    logic ack_q;
    always_ff @(posedge clk) ack_q <= cs_i & ~ack_q;
    assign ack_o = ack_q;
    wire wr = cs_i & we_i & ~ack_q;
    wire rd = cs_i & ~we_i & ~ack_q;

    // ------------------------------------------------------------------ TIMER
    logic [7:0]  t_ctrl;
    logic [15:0] t_reload, t_count, t_ticks;
    logic [7:0]  t_cnt_hi_l, t_ticks_hi_l;
    logic [$clog2(US_DIV)-1:0] us_pre;
    logic [9:0]  ms_pre;
    logic        t_irq;

    always_ff @(posedge clk) begin
        t_irq <= 1'b0;
        if (rst) begin
            t_ctrl   <= '0;
            t_reload <= '0;
            t_count  <= '0;
            t_ticks  <= '0;
            us_pre   <= '0;
            ms_pre   <= '0;
        end else begin
            if (us_pre == US_DIV - 1) begin
                us_pre <= '0;
                if (ms_pre == 10'd999) begin
                    ms_pre  <= '0;
                    t_ticks <= t_ticks + 16'd1;
                end else ms_pre <= ms_pre + 10'd1;
                if (t_ctrl[0]) begin
                    if (t_count == 16'd1) begin
                        t_irq <= 1'b1;
                        if (t_ctrl[1]) t_count <= t_reload;
                        else begin t_count <= '0; t_ctrl[0] <= 1'b0; end
                    end else t_count <= t_count - 16'd1;
                end
            end else us_pre <= us_pre + 1'b1;

            if (wr && tmr_sel) begin
                case (adr_i[4:0])
                    5'd0: begin
                        t_ctrl <= dat_i;
                        if (dat_i[0] && !t_ctrl[0]) t_count <= t_reload;   // al arrancar carga el periodo
                    end
                    5'd1: t_reload[7:0]  <= dat_i;
                    5'd2: t_reload[15:8] <= dat_i;
                    default: ;
                endcase
            end
            if (rd && tmr_sel && adr_i[4:0] == 5'd3) t_cnt_hi_l   <= t_count[15:8];
            if (rd && tmr_sel && adr_i[4:0] == 5'd5) t_ticks_hi_l <= t_ticks[15:8];
        end
    end

    // -------------------------------------------------------------------- PIC
    logic [15:0] irq_lines, irq_prev, pending, mask;
    logic [7:0]  vector;
    assign irq_lines = {irq_i[15:7], t_irq, irq_i[5:0]};

    always_ff @(posedge clk) begin
        if (rst) begin
            irq_prev <= '0;
            pending  <= '0;
            mask     <= '0;
            vector   <= '0;
        end else begin
            irq_prev <= irq_lines;
            pending  <= pending | (irq_lines & ~irq_prev);
            if (wr && pic_sel) begin
                case (adr_i[4:0])
                    5'd0: mask[7:0]  <= dat_i;
                    5'd1: mask[15:8] <= dat_i;
                    5'd2: vector     <= dat_i;
                    5'd7: pending[7:0]  <= (pending[7:0]  | (irq_lines[7:0]  & ~irq_prev[7:0]))  & ~dat_i;
                    5'd8: pending[15:8] <= (pending[15:8] | (irq_lines[15:8] & ~irq_prev[15:8])) & ~dat_i;
                    default: ;
                endcase
            end
        end
    end

    wire [15:0] active = pending & mask;
    assign int_o = |active;

    // Vector para IM 2: base + 2 * linea de mas prioridad (la mas alta)
    logic [3:0] top;
    always_comb begin
        top = 4'd0;
        for (int i = 0; i < 16; i++) if (active[i]) top = 4'(i);
    end
    assign int_vec_o = vector + {3'b000, top, 1'b0};

    // ---------------------------------------------------------------- Lectura
    always_comb begin
        dat_o = 8'hFF;
        if (pic_sel) begin
            case (adr_i[4:0])
                5'd0: dat_o = mask[7:0];
                5'd1: dat_o = mask[15:8];
                5'd2: dat_o = vector;
                5'd3: dat_o = active[7:0];
                5'd4: dat_o = active[15:8];
                5'd5: dat_o = pending[7:0];
                5'd6: dat_o = pending[15:8];
                default: ;
            endcase
        end else if (tmr_sel) begin
            case (adr_i[4:0])
                5'd0: dat_o = t_ctrl;
                5'd1: dat_o = t_reload[7:0];
                5'd2: dat_o = t_reload[15:8];
                5'd3: dat_o = t_count[7:0];
                5'd4: dat_o = t_cnt_hi_l;
                5'd5: dat_o = t_ticks[7:0];
                5'd6: dat_o = t_ticks_hi_l;
                default: ;
            endcase
        end
    end

endmodule
