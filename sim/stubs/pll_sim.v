// PLL de simulacion: 108/54/27 MHz en fase
`timescale 1ns/1ps
module pll(input inclk0, output reg c0 = 0, output reg c1 = 0, output reg c2 = 0, output reg locked = 0);
    initial begin
        #100 locked = 1;
    end
    // 108 MHz -> 9.259 ns
    always #4.6296 c0 = ~c0;
    always @(posedge c0) c1 <= ~c1;
    reg [1:0] d = 0;
    always @(posedge c0) begin d <= d + 1; if (d == 2'd1 || d == 2'd3) c2 <= ~c2; end
endmodule

// PLL de video de simulacion: 80 MHz
module pll_video(input inclk0, output reg c0 = 0, output reg locked = 0);
    initial #100 locked = 1;
    always #6.25 c0 = ~c0;
endmodule
