// tb_vid.sv - Modos de alta resolucion del 520EX en cpc_video: memoria llena de
// un byte fijo y se cuentan los pixeles encendidos de una linea visible.
`timescale 1ns/1ps
module tb_vid;
    logic clk_v = 0, clk_b = 0, clk_m = 0;
    always #6.25 clk_v = ~clk_v; always #9.259 clk_b = ~clk_b; always #4.63 clk_m = ~clk_m;
    logic rst = 1, crtc = 0, ga = 0, we = 0, rs = 0; logic [7:0] dat = 0, dout; logic ack;
    logic [1:0] mode = 0; logic [7:0] ext = 0;
    logic [2:0] hoff = 0, voff = 0; logic [7:0] fill;
    logic [15:0] maddr, mdata; logic mreq, mack = 0;
    logic ce, hs, vs, hb, vb, chs, cvs; logic [7:0] r, g, b;
    cpc_video dut (.clk_v, .rst_v(rst), .clk_b, .rst_b(rst), .bus_crtc(crtc), .bus_ga(ga), .bus_we(we),
        .bus_rs(rs), .bus_dat_i(dat), .bus_dat_o(dout), .bus_ack(ack), .mode_i(mode), .extport_i(ext),
        .clk_m, .rst_m(rst), .mem_en(1'b1), .mem_addr(maddr), .mem_req(mreq), .mem_ack0(mack), .mem_data(mdata),
        .ce_pix(ce), .r, .g, .b, .hs, .vs, .hblank(hb), .vblank(vb), .crtc_hs(chs), .crtc_vs(cvs), .h_off(hoff), .v_off(voff), .hires_o(hires_v));
    // Doblador de lineas real de mist_video (31 kHz), como lo instancia el top
    logic sd_hb, sd_vb, sd_hs, sd_vs; logic [7:0] sd_r, sd_g, sd_b;
    // divisor del doblador como en el top (+fixed_ce: el antiguo, 16 MHz fijos)
    logic hires_v; logic sd_pe;
    wire [3:0] sd_div = (hires_v && !$test$plusargs("fixed_ce")) ? 4'd5 : 4'd4;
    // muestras que toma el doblador en una linea visible: distancias entre pixeles encendidos
    int smp_n = 0, last_lit = -1, gaps [int]; bit sampling = 0, smp_done = 0; logic hb_s = 1;
    always @(posedge clk_v) begin
        hb_s <= hb;
        if (sampling && sd_pe && !hb && !vb) begin
            if (r != 0) begin
                if (last_lit >= 0) gaps[smp_n - last_lit] = gaps.exists(smp_n - last_lit) ? gaps[smp_n - last_lit] + 1 : 1;
                last_lit = smp_n;
            end
            smp_n++;
        end
        if (sampling && hb && !hb_s && smp_n > 0) begin sampling = 0; smp_done = 1; end
    end
    task automatic show_samples(input string name);
        gaps.delete(); smp_n = 0; last_lit = -1; smp_done = 0;
        wait (!vb); repeat (60) @(posedge hb); @(negedge hb); sampling = 1;
        wait (smp_done);
        $write("%-34s doblador: %0d muestras en la linea; distancias entre pixeles encendidos:", name, smp_n);
        foreach (gaps[g]) $write(" %0dx%0d", gaps[g], g);
        $display("");
    endtask
    // la temporizacion de la salida de 31 kHz la decide scandoubler_framing
    scandoubler_framing #(.HCNT_WIDTH(11), .HSCNT_WIDTH(12)) sd (
        .clk_sys(clk_v), .ce_divider(sd_div), .hb_in(hb), .vb_in(vb), .hs_in(hs), .vs_in(vs), .pe_in(sd_pe), .hcnt_in(),
        .hb_out(sd_hb), .vb_out(sd_vb), .hs_out(sd_hs), .vs_out(sd_vs), .pe_out(), .ppe_out(), .hcnt_out(), .line_out());
    // salida a 31 kHz: periodo de linea, HSYNC y distancia HSYNC -> imagen (en ciclos de 80 MHz)
    int sd_cnt = 0, sd_line = 0, sd_hsw = 0, sd_vis = 0; logic sd_hs_q = 0, sd_hb_q = 1;
    always @(posedge clk_v) begin
        sd_hs_q <= sd_hs; sd_hb_q <= sd_hb;
        if (sd_hs && !sd_hs_q) begin sd_line <= sd_cnt; sd_cnt <= 0; end else sd_cnt <= sd_cnt + 1;
        if (!sd_hs && sd_hs_q) sd_hsw <= sd_cnt;
        if (!sd_hb && sd_hb_q && !sd_vb) sd_vis <= sd_cnt;
    end
    task automatic show_31k(input string name);
        repeat (2) @(posedge vs);
        $display("%-34s 31 kHz: linea %0.2f us, HSYNC %0.2f us, HSYNC -> imagen %0.2f us", name,
                 sd_line / 80.0, sd_hsw / 80.0, sd_vis / 80.0);
    endtask
    always @(posedge clk_m) begin mack <= 0; if (mreq && !mack) begin mdata <= {fill, fill}; mack <= 1; end end
    task automatic bw(input bit is_crtc, input bit r_s, input logic [7:0] v);
        @(posedge clk_b); crtc <= is_crtc; ga <= !is_crtc; we <= 1; rs <= r_s; dat <= v;
        @(posedge clk_b); while (!ack) @(posedge clk_b); crtc <= 0; ga <= 0; @(posedge clk_b);
    endtask
    task automatic crtc_reg(input int n, input int v); bw(1, 0, 8'(n)); bw(1, 1, 8'(v)); endtask
    // pixeles encendidos en una linea visible (mitad de la pantalla)
    function automatic int lit_line(); return 0; endfunction
    int lit, best;
    task automatic measure(input string name, input int expect_px);
        int line_lit; logic hb_d;
        best = 0;
        wait (!vb); repeat (60) @(posedge hb);     // lineas del centro de la pantalla
        repeat (3) begin
            @(posedge hb); @(negedge hb); line_lit = 0;
            while (!hb) begin @(posedge clk_v); if (ce && !hb && !vb && r != 0) line_lit++; end
            if (line_lit > best) best = line_lit;
        end
        $display("   (diag: vs=%0d hb=%0d vb=%0d r=%0d ink3=%h scr_on=%0d hires=%0d)", vs, hb, vb, r, dut.ink[3], dut.scr_on, dut.hires);
        $display("%-34s pixeles encendidos por linea: %0d (esperado %0d) %s", name, best, expect_px, best == expect_px ? "OK" : "FALLO");
    endtask
    // distancia del flanco de HSYNC al principio de la ventana visible (ciclos de 80 MHz)
    int hs_to_vis = 0, cnt_h = 0; logic hs_q = 0, hb_q = 1;
    always @(posedge clk_v) begin
        hs_q <= hs; hb_q <= hb;
        if (hs && !hs_q) cnt_h <= 0; else cnt_h <= cnt_h + 1;
        if (!hb && hb_q && !vb) hs_to_vis <= cnt_h;
    end
    // lineas desde el flanco de VSYNC hasta la primera linea visible
    int vs_to_vis = 0, cnt_v = 0; logic vs_q = 0, vb_q = 1, hs_q2 = 0;
    always @(posedge clk_v) begin
        vs_q <= vs; vb_q <= vb; hs_q2 <= hs;
        if (vs && !vs_q) cnt_v <= 0; else if (hs && !hs_q2) cnt_v <= cnt_v + 1;
        if (!vb && vb_q) vs_to_vis <= cnt_v;
    end
    task automatic show_sync(input string name);
        repeat (3) @(posedge hb);
        repeat (2) @(posedge vs);
        $display("%-34s HSYNC -> imagen: %0d ciclos (%0.2f us); VSYNC -> imagen: %0d lineas", name, hs_to_vis, hs_to_vis / 80.0, vs_to_vis);
    endtask
    initial begin
        repeat (20) @(posedge clk_b); rst <= 0; repeat (20) @(posedge clk_b);
        // CRTC de la BIOS para alta resolucion: 108 caracteres, 80 visibles, 25 filas de 8
        crtc_reg(0, 8'h6B); crtc_reg(1, 80); crtc_reg(2, 8'h51); crtc_reg(3, 8'h8E);   // tabla MC6845H del BOOTMENU
        crtc_reg(4, 38); crtc_reg(5, 0); crtc_reg(6, 25); crtc_reg(7, 30); crtc_reg(9, 7);
        crtc_reg(12, 0); crtc_reg(13, 0);
        ext = 8'h0F;            // pantalla, MAPMOD, alta resolucion, D0 (antes de las tintas)
        repeat (20) @(posedge clk_v);
        // tintas RGB directas (MAPMOD): 0 negro, 3 blanco, resto rojo
        bw(0, 0, 8'h00); bw(0, 0, 8'h40);
        for (int i = 1; i < 16; i++) begin bw(0, 0, 8'(i)); bw(0, 0, i == 3 ? 8'h7F : 8'h70); end
        // modo 1 en alta resolucion: 640x200x4; byte 88h = un pixel de color 3 cada 4
        mode = 2'd1; fill = 8'h88;
        repeat (2) @(posedge vs); measure("alta res., modo 1 (640x200x4)", 160);
        show_samples("alta res., 1 de cada 4 encendido");
        show_sync("alta resolucion");
        show_31k("alta resolucion");
        // toda la pantalla encendida: la ventana debe abarcar los 640 pixeles
        mode = 2'd1; fill = 8'hFF;
        repeat (2) @(posedge vs); measure("alta res., pantalla entera", 640);
        // modo 3: 320x200x16; byte 01 = pixel 0 tinta 0, pixel 1 tinta 8 (2 relojes cada uno)
        mode = 2'd3; fill = 8'h01;
        repeat (2) @(posedge vs); measure("alta res., modo 3 (320x200x16)", 320);
        // resolucion normal (CPC): tabla del CPC, sin alta resolucion
        ext = 8'h0C; mode = 2'd2;
        crtc_reg(0, 63); crtc_reg(1, 40); crtc_reg(2, 46); crtc_reg(3, 8'h8E);
        repeat (3) @(posedge vs); show_sync("resolucion normal (CPC)");
        show_31k("resolucion normal (CPC)");
        hoff = 3'd1; voff = 3'd1; repeat (3) @(posedge vs); show_sync("H centre +8, V centre +2");
        measure("  pixeles visibles (iguales)", 80);
        hoff = 3'd4; voff = 3'd4; repeat (3) @(posedge vs); show_sync("H centre -32, V centre -8");
        $finish;
    end
    initial begin #1000ms; $display("TIMEOUT"); $finish; end
endmodule
