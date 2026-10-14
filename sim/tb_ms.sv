// tb_ms.sv - Prueba de la MagicSound (rtl/cpc/magic_sound.sv) programada como
// lo hace el reproductor MAG.COM: canal A a 8448 Hz desde una pagina mapeada.
`timescale 1ns/1ps
module tb_ms;
    logic clk = 0; always #9.259 clk = ~clk;                 // 54 MHz
    logic reset = 1, cs = 0, we = 0;
    logic [9:0] adr = 0; logic [7:0] din = 0, dout;
    logic ack, dma_cyc, nmi; logic [23:0] dma_adr;
    logic [7:0] dma_dat = 0; logic dma_ack = 0;
    logic signed [15:0] out_l, out_r;

    magic_sound dut (.clk, .reset, .cs, .we, .adr, .din, .dout, .ack,
        .dma_cyc, .dma_adr, .dma_dat, .dma_ack, .dma_err(1'b0), .nmi, .out_l, .out_r);

    // memoria: rampa que depende de la direccion fisica
    int n_dma = 0; logic [23:0] last_adr;
    int n_ch [4] = '{0, 0, 0, 0};
    int divs [4] = '{474, 399, 316, 250};
    logic [15:0] tim [4] = '{16'hF9D8, 16'hF9D9, 16'hF9DA, 16'hF9D4};
    always @(posedge clk) begin
        dma_ack <= 0;
        if (dma_cyc && !dma_ack) begin
            repeat (8) @(posedge clk);
            dma_dat <= dma_adr[7:0]; dma_ack <= 1; n_dma++; last_adr <= dma_adr;
            n_ch[(dma_adr[21:14] - 8'd10) / 12]++;
        end
    end

    task automatic io(input logic [15:0] port, input logic [7:0] v, input bit w = 1);
        @(posedge clk); cs <= 1; we <= w; adr <= port[9:0]; din <= v;
        @(posedge clk); while (!ack) @(posedge clk);
        cs <= 0; @(posedge clk);
    endtask

    int n_nmi = 0; logic nmi_d = 0;
    always @(posedge clk) begin nmi_d <= nmi; if (nmi && !nmi_d) n_nmi++; end
    int changes = 0; logic signed [15:0] l_d = 0;
    int max_l = 0, max_r = 0;
    always @(posedge clk) begin if ($signed(out_l) > max_l) max_l = out_l; if ($signed(out_r) > max_r) max_r = out_r; end
    always @(posedge clk) begin l_d <= out_l; if (out_l != l_d) changes++; end

    initial begin
        logic [7:0] st;
        repeat (10) @(posedge clk); reset <= 0;
        // INI_PRT de MAG
        io(16'hF9DB, 8'h34); io(16'hF9DB, 8'h74); io(16'hF9DB, 8'hB4);
        io(16'hF9D7, 8'h34); io(16'hF9D7, 8'h76);
        io(16'hF8DD, 8'h00); io(16'hF8D8, 8'h00);
        io(16'hF8DA, 8'h05); io(16'hF8DA, 8'h04); io(16'hF8DA, 8'h06); io(16'hF8DA, 8'h07);
        // los 4 canales como MAG (MA_START): direccion, longitud, divisor, volumen, paginas, modo, desenmascarar
        foreach (divs[ch]) begin
            io(16'hF8D0 + 16'(2*ch), 8'h00); io(16'hF8D0 + 16'(2*ch), 8'h40);
            io(16'hF8D1 + 16'(2*ch), 8'hFF); io(16'hF8D1 + 16'(2*ch), 8'h00);
            io(tim[ch], 8'(divs[ch])); io(tim[ch], 8'(divs[ch] >> 8));
            io(16'hFAD0 + 16'(ch), 8'(63 << 2));      // como MAG.COM: volumen*4
            for (int q = 0; q < 4; q++) io(16'hFBD0 + 16'(4*ch + q), ~8'(10 + 12*ch + q));   // A:10.. B:22.. C:34.. D:46..
            io(16'hF8DB, 8'h58 + 8'(ch));
            io(16'hF8DA, 8'(ch));
        end
        #100ms;
        io(16'hF8D8, 8'h00, 0); st = dout;
        foreach (n_ch[ch]) $display("canal %0d (A=0..D=3): %0d lecturas en 100 ms (esperado ~%0d)", ch, n_ch[ch], 4000000 / divs[ch] / 10);
        $display("NMI en 100 ms: %0d; amplitud maxima izquierda %0d, derecha %0d", n_nmi, max_l, max_r);
        $finish;
    end
endmodule
