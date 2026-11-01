// ============================================================================
// lx_dma.sv - DMA de sistema / blitter del Aleste LX (modo LX, macro ALESTE_LX)
//
// Copia y relleno de memoria en rectangulos (2D), byte a byte por el segundo
// maestro del bus. Sustituye, en version sencilla, a SysDMA (lx_dma.md) y a la
// parte de copia de bloques del acelerador grafico de hww, que estan a
// medias: transferencias memoria-memoria con ancho, alto y paso de linea de
// origen y destino, relleno y copia con color transparente.
//
// Pagina MMIO 6 (FF0300-FF037F, MMIO_PAGE_DMA de aleste-xi-bios):
//   00 CTRL     W  bit 0 arranca, bits 2-1 modo (0 copia, 1 relleno,
//                  2 copia con transparente: no escribe los bytes iguales a
//                  KEY), bit 3 interrupcion al terminar
//               R  bit 0 ocupado, bits 3-1 lo escrito
//   01 STATUS   R  bit 0 fin pendiente;  W 1 = lo borra
//   02-04 SRC      direccion fisica de origen (byte bajo primero)
//   05-07 DST      direccion fisica de destino
//   08-09 WIDTH    bytes por linea (0 = 65536)
//   0A-0B HEIGHT   lineas (0 = 1)
//   0C-0D SSTRIDE  distancia entre lineas del origen (con signo)
//   0E-0F DSTRIDE  distancia entre lineas del destino (con signo)
//   10    KEY      byte de relleno o color transparente
// Las direcciones son fisicas (24 bits). En modo LX la memoria que la CPU ve
// en C00000-C0FFFF esta en 410000-41FFFF.
// ============================================================================
`default_nettype none

module lx_dma (
    input  logic        clk,
    input  logic        rst,

    input  logic        cs_i,
    input  logic        we_i,
    input  logic [6:0]  adr_i,
    input  logic [7:0]  dat_i,
    output logic [7:0]  dat_o,
    output logic        ack_o,

    output logic        dma_cyc_o,
    output logic        dma_we_o,
    output logic [23:0] dma_adr_o,
    output logic [7:0]  dma_dat_o,
    input  logic [7:0]  dma_dat_i,
    input  logic        dma_ack_i,
    input  logic        dma_err_i,

    output logic        irq_o
);

    logic [3:0]  ctrl;
    logic        busy, done;
    logic [23:0] r_src, r_dst;
    logic [15:0] r_w, r_h, r_ss, r_ds;
    logic [7:0]  key;

    // Estado de la transferencia
    logic [23:0] s_line, d_line, s_adr, d_adr;
    logic [16:0] x_left;
    logic [15:0] y_left;
    logic [7:0]  data;
    typedef enum logic [1:0] {T_IDLE, T_RD, T_WR} tstate_t;
    tstate_t st;

    logic ack_q;
    always_ff @(posedge clk) ack_q <= cs_i & ~ack_q;
    assign ack_o = ack_q;
    wire wr = cs_i & we_i & ~ack_q;

    wire [1:0] mode = ctrl[2:1];

    always_comb begin
        dma_cyc_o = (st == T_RD) || (st == T_WR);
        dma_we_o  = (st == T_WR);
        dma_adr_o = (st == T_WR) ? d_adr : s_adr;
        dma_dat_o = (mode == 2'd1) ? key : data;
    end

    // Paso al siguiente byte: al acabar una lectura transparente o una escritura
    wire do_next = (st == T_WR && (dma_ack_i || dma_err_i)) ||
                   (st == T_RD && (dma_ack_i || dma_err_i) && mode == 2'd2 && dma_dat_i == key);
    wire next_st_wr = (mode == 2'd1);

    always_ff @(posedge clk) begin
        if (rst) begin
            ctrl <= '0; busy <= 1'b0; done <= 1'b0; st <= T_IDLE;
            r_src <= '0; r_dst <= '0; r_w <= '0; r_h <= '0; r_ss <= '0; r_ds <= '0; key <= '0;
        end else begin
            if (st == T_RD && (dma_ack_i || dma_err_i)) begin
                data <= dma_dat_i;
                st   <= T_WR;                       // (salvo transparente: do_next)
            end
            if (do_next) begin
                if (x_left > 17'd1) begin
                    x_left <= x_left - 17'd1;
                    s_adr  <= s_adr + 24'd1;
                    d_adr  <= d_adr + 24'd1;
                    st     <= next_st_wr ? T_WR : T_RD;
                end else if (y_left > 16'd1) begin
                    y_left <= y_left - 16'd1;
                    x_left <= (r_w == 16'd0) ? 17'h10000 : {1'b0, r_w};
                    s_line <= s_line + {{8{r_ss[15]}}, r_ss};
                    d_line <= d_line + {{8{r_ds[15]}}, r_ds};
                    s_adr  <= s_line + {{8{r_ss[15]}}, r_ss};
                    d_adr  <= d_line + {{8{r_ds[15]}}, r_ds};
                    st     <= next_st_wr ? T_WR : T_RD;
                end else begin
                    busy <= 1'b0;
                    if (ctrl[3]) done <= 1'b1;
                    st   <= T_IDLE;
                end
            end

            if (wr) begin
                case (adr_i)
                    7'h00: if (!busy) begin
                        ctrl <= dat_i[3:0];
                        if (dat_i[0]) begin
                            busy   <= 1'b1;
                            s_line <= r_src; s_adr <= r_src;
                            d_line <= r_dst; d_adr <= r_dst;
                            x_left <= (r_w == 16'd0) ? 17'h10000 : {1'b0, r_w};
                            y_left <= (r_h == 16'd0) ? 16'd1 : r_h;
                            st     <= (dat_i[2:1] == 2'd1) ? T_WR : T_RD;
                        end
                    end
                    7'h01: if (dat_i[0]) done <= 1'b0;
                    7'h02: r_src[7:0]   <= dat_i;
                    7'h03: r_src[15:8]  <= dat_i;
                    7'h04: r_src[23:16] <= dat_i;
                    7'h05: r_dst[7:0]   <= dat_i;
                    7'h06: r_dst[15:8]  <= dat_i;
                    7'h07: r_dst[23:16] <= dat_i;
                    7'h08: r_w[7:0]     <= dat_i;
                    7'h09: r_w[15:8]    <= dat_i;
                    7'h0A: r_h[7:0]     <= dat_i;
                    7'h0B: r_h[15:8]    <= dat_i;
                    7'h0C: r_ss[7:0]    <= dat_i;
                    7'h0D: r_ss[15:8]   <= dat_i;
                    7'h0E: r_ds[7:0]    <= dat_i;
                    7'h0F: r_ds[15:8]   <= dat_i;
                    7'h10: key          <= dat_i;
                    default: ;
                endcase
            end
        end
    end

    assign irq_o = done;

    always_comb begin
        case (adr_i)
            7'h00: dat_o = {4'h0, ctrl[3:1], busy};
            7'h01: dat_o = {7'd0, done};
            7'h02: dat_o = r_src[7:0];
            7'h03: dat_o = r_src[15:8];
            7'h04: dat_o = r_src[23:16];
            7'h05: dat_o = r_dst[7:0];
            7'h06: dat_o = r_dst[15:8];
            7'h07: dat_o = r_dst[23:16];
            7'h08: dat_o = r_w[7:0];
            7'h09: dat_o = r_w[15:8];
            7'h0A: dat_o = r_h[7:0];
            7'h0B: dat_o = r_h[15:8];
            7'h0C: dat_o = r_ss[7:0];
            7'h0D: dat_o = r_ss[15:8];
            7'h0E: dat_o = r_ds[7:0];
            7'h0F: dat_o = r_ds[15:8];
            7'h10: dat_o = key;
            default: dat_o = 8'hFF;
        endcase
    end

endmodule
