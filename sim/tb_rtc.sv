// tb_rtc.sv - Reloj MC146818 del 520EX, manejado como el SETUP (CLK_HZ=1000: 1 s = 1000 ciclos)
`timescale 1ns/1ps
module tb_rtc;
    logic clk = 0; always #5 clk = ~clk;
    logic reset = 1, sel = 0; logic [2:0] cmd = 0; logic [7:0] din = 0, dout; logic drive;
    logic set_time = 0;
    rtc146818 #(.CLK_HZ(1000)) dut (.clk, .reset, .sel, .cmd, .din, .dout, .drive,
        .cmos_we(1'b0), .cmos_addr(6'd0), .cmos_din(8'd0), .cmos_dout(), .dirty(), .cmos_clean(1'b0),
        .set_time, .set_sec(8'h56), .set_min(8'h34), .set_hour(8'h12), .set_day(8'h04),
        .set_mon(8'h10), .set_year(8'h26), .set_wday(3'd0));
    task automatic wr(input logic [5:0] a, input logic [7:0] v);
        @(posedge clk) sel <= 1; cmd <= 2; din <= 8'(a); @(posedge clk) cmd <= 0;
        @(posedge clk) cmd <= 4; din <= v; @(posedge clk) cmd <= 0; sel <= 0;
    endtask
    task automatic rd(input logic [5:0] a, output logic [7:0] v);
        @(posedge clk) sel <= 1; cmd <= 2; din <= 8'(a); @(posedge clk) cmd <= 5;
        @(posedge clk); v = dout; @(posedge clk) cmd <= 0; sel <= 0; @(posedge clk);
    endtask
    task automatic show(input string what);
        logic [7:0] s, m, h, w, d, mo, y;
        rd(4, h); rd(2, m); rd(0, s); rd(6, w); rd(7, d); rd(8, mo); rd(9, y);
        $display("%-36s %02d:%02d:%02d  %02d/%02d/%04d  dia de la semana %0d", what, h, m, s, d, mo, 1980 + y, w);
    endtask
    initial begin
        logic [7:0] c, a;
        repeat (5) @(posedge clk); reset <= 0;
        // inicializacion como CLOCK_INIT del BOOTMENU: SET, binario, 24 h; 23:59:58 del 31/12/1999 (y=19)
        wr(6'h0B, 8'h8E); wr(0, 58); wr(2, 59); wr(4, 23); wr(6, 6); wr(7, 31); wr(8, 12); wr(9, 19); wr(6'h0B, 8'h0E);
        show("puesto (SET, luego en marcha):");
        rd(6'h0C, c); $display("registro C al empezar: %02h (UF=%0d)", c, c[4]);
        repeat (1100) @(posedge clk);
        rd(6'h0C, c); $display("tras 1 s, registro C: %02h (UF=%0d)", c, c[4]);
        rd(6'h0C, c); $display("leido otra vez:       %02h (UF borrado=%0d)", c, !c[4]);
        repeat (1000) @(posedge clk); show("tras 2 s (cambio de ano):");
        // 28/02/2000 (bisiesto) 23:59:59 -> 29/02
        wr(6'h0B, 8'h8E); wr(0, 59); wr(2, 59); wr(4, 23); wr(7, 28); wr(8, 2); wr(9, 20); wr(6'h0B, 8'h0E);
        repeat (1100) @(posedge clk); show("28/02/2000 + 1 s (bisiesto):");
        // SET para la hora
        wr(6'h0B, 8'h8E); repeat (3000) @(posedge clk); show("con SET durante 3 s (parado):");
        wr(6'h0B, 8'h0E);
        // UIP: activo poco antes de la actualizacion
        begin int seen = 0; repeat (1000) begin rd(6'h0A, a); if (a[7]) seen++; end
              $display("UIP visto en %0d de 1000 lecturas (esperado unas pocas)", seen); end
        // ---- modo BCD (DM=0): registro B = 82h/02h
        begin logic [7:0] s, m, h, d, mo, y;
        wr(6'h0B, 8'h82); wr(0, 8'h58); wr(2, 8'h59); wr(4, 8'h23); wr(7, 8'h31); wr(8, 8'h12); wr(9, 8'h19); wr(6'h0B, 8'h02);
        repeat (2100) @(posedge clk);
        rd(4, h); rd(2, m); rd(0, s); rd(7, d); rd(8, mo); rd(9, y);
        $display("BCD 23:59:58 31/12/(19) + 2 s:      %02h:%02h:%02h  %02h/%02h/(%02h)", h, m, s, d, mo, y);
        wr(6'h0B, 8'h82); wr(0, 8'h59); wr(2, 8'h59); wr(4, 8'h23); wr(7, 8'h28); wr(8, 8'h02); wr(9, 8'h20); wr(6'h0B, 8'h02);
        repeat (1100) @(posedge clk);
        rd(7, d); rd(8, mo); $display("BCD 28/02/(20) bisiesto + 1 s:      %02h/%02h", d, mo);
        wr(6'h0B, 8'h82); wr(0, 8'h59); wr(2, 8'h59); wr(4, 8'h23); wr(7, 8'h28); wr(8, 8'h02); wr(9, 8'h21); wr(6'h0B, 8'h02);
        repeat (1100) @(posedge clk);
        rd(7, d); rd(8, mo); $display("BCD 28/02/(21) no bisiesto + 1 s:   %02h/%02h", d, mo);
        wr(6'h0B, 8'h82); wr(0, 8'h59); wr(2, 8'h59); wr(4, 8'h23); wr(7, 8'h30); wr(8, 8'h09); wr(9, 8'h21); wr(6'h0B, 8'h02);
        repeat (1100) @(posedge clk);
        rd(7, d); rd(8, mo); $display("BCD 30/09 + 1 s (septiembre, 30):   %02h/%02h", d, mo);
        @(posedge clk) set_time <= 1; @(posedge clk) set_time <= 0;
        rd(4, h); rd(2, m); rd(0, s); rd(7, d); rd(8, mo); rd(9, y);
        $display("BCD hora de MiST:                   %02h:%02h:%02h  %02h/%02h/(%02h = 2026)", h, m, s, d, mo, y);
        wr(6'h0B, 8'h06);
        end
        // puesta en hora desde MiST: 12:34:56 domingo 04/10/2026
        @(posedge clk) set_time <= 1; @(posedge clk) set_time <= 0;
        show("hora de MiST (12:34:56 04/10/2026):");
        $finish;
    end
endmodule
