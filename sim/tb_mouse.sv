// tb_mouse.sv - 8251 + raton Mouse Systems, programado como la BIOS FOTON
`timescale 1ns/1ps
module tb_mouse;
    logic clk = 0; always #9.259 clk = ~clk;
    logic reset = 1, cs = 0, we = 0, a8 = 0; logic [7:0] din = 0, dout; logic ack;
    logic [8:0] mx = 0, my = 0; logic [7:0] mf = 8'h08; logic ms = 0;
    serial_mouse #(.CLK_HZ(54_000_000)) dut (.clk, .reset, .cs, .we, .a8, .din, .dout, .ack,
        .mouse_x(mx), .mouse_y(my), .mouse_flags(mf), .mouse_strobe(ms));
    task automatic io(input bit w, input bit ctl, input logic [7:0] v, output logic [7:0] r);
        @(posedge clk); cs <= 1; we <= w; a8 <= ctl; din <= v;
        @(posedge clk); while (!ack) @(posedge clk); r = dout; cs <= 0; @(posedge clk);
    endtask
    initial begin
        logic [7:0] r, st; logic [7:0] got [0:9]; int n = 0;
        repeat (10) @(posedge clk); reset <= 0;
        io(1, 1, 8'h40, r); io(1, 1, 8'h4E, r); io(1, 1, 8'h07, r);   // como la BIOS
        // raton: 10 a la derecha, 5 hacia arriba, boton izquierdo
        @(posedge clk); mx <= 9'd10; my <= 9'd5; mf <= 8'h09; ms <= 1; @(posedge clk); ms <= 0;
        // la BIOS mira el estado en cada interrupcion (300 Hz)
        repeat (40) begin
            #(3.3ms);
            io(0, 1, 8'h00, st);
            if (st[1]) begin io(0, 0, 8'h00, r); got[n] = r; n++; end
            if (st[4]) $display("desbordamiento");
        end
        $write("bytes recibidos (%0d):", n); for (int i = 0; i < n; i++) $write(" %02h", got[i]); $display("");
        $display("esperado: 83 0a 05 00 00 (10000LMR con L pulsado = 0, dx = +10, dy = +5)");
        $finish;
    end
endmodule
