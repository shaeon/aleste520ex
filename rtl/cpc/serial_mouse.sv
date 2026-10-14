// ============================================================================
// serial_mouse.sv - 8251 (K580VV51) del Aleste 520EX con un raton serie
//
// El 520EX lleva el raton en el puerto serie ("By the serial connector, you
// can connect IBM Mouse", manual de usuario). Lo atiende la BIOS de MSX-DOS
// (FOTON): programa el 8251 (reset interno 40h, modo 4Eh = 8 bits, sin
// paridad, 1 bit de parada, x16; orden 07h) y el 8253 a 1200 baudios, y en la
// interrupcion recoge paquetes de 5 bytes con el primero = 10000LMR: es el
// protocolo Mouse Systems (botones activos a 0; dx1, dy1, dx2, dy2 con signo,
// Y positiva hacia arriba; la BIOS hace X += dx1+dx2, Y -= dy1+dy2). Solo los
// usa si el raton esta activado en el SETUP.
//
// Puertos: EExx datos, EFxx control/estado (A8).
// El raton del PS/2 (user_io) se acumula y se envia en paquetes al ritmo de
// una linea a 1200 baudios (10 bits por byte: 8,33 ms), solo con la recepcion
// del 8251 activada.
// ============================================================================
`default_nettype none

module serial_mouse #(
    parameter int CLK_HZ = 54_000_000
)(
    input  logic       clk,
    input  logic       reset,

    // Bus de la CPU
    input  logic       cs,
    input  logic       we,
    input  logic       a8,             // 0 datos, 1 control/estado
    input  logic [7:0] din,
    output logic [7:0] dout,
    output logic       ack,

    // Raton PS/2 (user_io)
    input  logic [8:0] mouse_x,        // con signo, derecha positiva
    input  logic [8:0] mouse_y,        // con signo, arriba positiva
    input  logic [7:0] mouse_flags,    // ..., mbtn, rbtn, lbtn
    input  logic       mouse_strobe
);

localparam int BYTE_CYCLES = CLK_HZ / 120;     // 1200 baudios, 10 bits por byte

// ---------------------------------------------------------------- 8251
logic       expect_mode;                       // tras el reset, la primera escritura de control es el modo
logic [7:0] cmd;
logic [7:0] rx_data;
logic       rx_rdy, overrun;
wire        rx_en = cmd[2];

wire        new_byte;
wire [7:0]  new_data;

always_ff @(posedge clk) begin
    ack <= 1'b0;
    if (reset) begin
        expect_mode <= 1'b1;
        cmd <= 8'h00;
        rx_rdy <= 1'b0; overrun <= 1'b0;
    end else begin
        if (new_byte) begin
            if (rx_rdy) overrun <= 1'b1;
            rx_data <= new_data;
            rx_rdy  <= 1'b1;
        end
        if (cs && !ack) begin
            ack <= 1'b1;
            if (we) begin
                if (a8) begin
                    // 40h exacto = reset interno tambien esperando el modo (la BIOS
                    // empieza con 40h, 4Eh, 07h; ningun modo asincrono vale 40h)
                    if (din == 8'h40) begin expect_mode <= 1'b1; cmd <= 8'h00; rx_rdy <= 1'b0; end
                    else if (expect_mode) expect_mode <= 1'b0;     // palabra de modo (asincrono)
                    else begin
                        cmd <= din;
                        if (din[4]) overrun <= 1'b0;                // ER: borra errores
                        if (din[6]) begin expect_mode <= 1'b1; cmd <= 8'h00; rx_rdy <= 1'b0; end   // IR
                    end
                end
            end else begin
                if (a8) dout <= {1'b1, 1'b0, 1'b0, overrun, 1'b0, 1'b1, rx_rdy, 1'b1};   // DSR, TxEMPTY, TxRDY
                else begin
                    dout   <= rx_data;
                    rx_rdy <= new_byte;
                end
            end
        end
    end
end

// ---------------------------------------------------------------- raton Mouse Systems
logic signed [11:0] acc_x, acc_y;
logic [2:0]         btn, btn_sent;
logic [7:0]         pkt [0:4];
logic [2:0]         pkt_idx;                    // 0-4 enviando, 5 libre
logic [$clog2(BYTE_CYCLES+1)-1:0] tick;
logic               emit;

function automatic logic [7:0] sat8(input logic signed [11:0] v);
    sat8 = (v > 12'sd127) ? 8'h7F : (v < -12'sd127) ? 8'h81 : v[7:0];
endfunction

always_ff @(posedge clk) begin
    emit <= 1'b0;
    if (reset) begin
        acc_x <= '0; acc_y <= '0; btn <= '0; btn_sent <= '0;
        pkt_idx <= 3'd5; tick <= '0;
    end else begin
        logic signed [11:0] nx, ny;
        logic [2:0]         nb;
        nx = acc_x; ny = acc_y; nb = btn;
        if (mouse_strobe) begin
            nx = nx + 12'($signed(mouse_x));
            ny = ny + 12'($signed(mouse_y));
            nb = {mouse_flags[0], mouse_flags[2], mouse_flags[1]};      // L, M, R
        end

        if (tick != 0) tick <= tick - 1'b1;
        else if (pkt_idx < 3'd5) begin                   // siguiente byte del paquete
            emit    <= 1'b1;
            tick    <= BYTE_CYCLES[$bits(tick)-1:0];
            pkt_idx <= pkt_idx + 3'd1;
        end else if (rx_en && (nx != 0 || ny != 0 || nb != btn_sent)) begin
            // paquete nuevo: 10000LMR (activos a 0), dx, dy, 0, 0
            pkt[0] <= {5'b10000, ~nb};
            pkt[1] <= sat8(nx);
            pkt[2] <= sat8(ny);
            pkt[3] <= 8'h00;
            pkt[4] <= 8'h00;
            nx = nx - 12'($signed(sat8(nx)));
            ny = ny - 12'($signed(sat8(ny)));
            btn_sent <= nb;
            pkt_idx  <= 3'd0;
        end
        acc_x <= nx; acc_y <= ny; btn <= nb;
        if (!rx_en) begin acc_x <= '0; acc_y <= '0; end  // sin receptor, el raton no acumula
    end
end

// el byte se entrega al empezar su tiempo de linea
assign new_byte = emit;
assign new_data = pkt[pkt_idx - 3'd1];

endmodule

`default_nettype wire
