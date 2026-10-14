// ============================================================================
// tb_aleste_core.sv - Banco de pruebas de la fase 1
//
// aleste_core + modelo de SDRAM. Hace lo que haria el firmware MiST por
// data_io (cargar una imagen, una ROM y un guion de bus) y comprueba:
//   - que todos los bytes cargados acaban en la SDRAM donde toca
//   - que la FIFO del cargador no desborda al ritmo del SPI
//   - que el guion llega al CRTC y a la paleta (sin timeout)
//   - que hay auto-refresh a su ritmo
//   - el barrido VGA (858 x 525 a 27 MHz)
//   - errores de tiempos de la SDRAM que detecte el modelo
// ============================================================================
`timescale 1ns/1ps

module tb_aleste_core;

    // ---------------- Relojes (como el PLL: 108/54/27 en fase) ----------------
    logic clk_system = 0, clk_bus = 0, clk_pixel = 0, pll_locked = 0;
    always #4.6296 clk_system = ~clk_system;
    always @(posedge clk_system) clk_bus <= ~clk_bus;
    logic [1:0] div4 = 0;
    always @(posedge clk_system) begin
        div4 <= div4 + 1;
        if (div4 == 2'd1 || div4 == 2'd3) clk_pixel <= ~clk_pixel;
    end
    initial #200 pll_locked = 1;

    // ---------------- DUT ----------------
    logic        ioctl_download = 0, ioctl_wr = 0;
    logic [7:0]  ioctl_index = 0, ioctl_dout = 0;
    logic [26:0] ioctl_addr = 0;

    wire [15:0] dq_ctrl, dq_sdram;
    wire        dq_ctrl_oe, dq_sdram_oe;
    wire [12:0] sd_a;
    wire [1:0]  sd_ba, sd_dqm;
    wire        sd_ncs, sd_nras, sd_ncas, sd_nwe, sd_cke;
    wire [11:0] rgb;
    wire        hs, vs, hb, vb;
    wire        busy, overflow, timeout, refreshing;

    aleste_core dut (
        .clk_system, .clk_bus, .clk_pixel, .pll_locked,
        .user_reset(1'b0),
        .ioctl_download, .ioctl_index, .ioctl_wr, .ioctl_addr, .ioctl_dout,
        .sdram_dq_i(dq_sdram_oe ? dq_sdram : dq_ctrl),
        .sdram_dq_o(dq_ctrl), .sdram_dq_oe(dq_ctrl_oe),
        .sdram_a(sd_a), .sdram_ba(sd_ba), .sdram_dqm(sd_dqm),
        .sdram_ncs(sd_ncs), .sdram_nras(sd_nras), .sdram_ncas(sd_ncas),
        .sdram_nwe(sd_nwe), .sdram_cke(sd_cke),
        .vga_rgb(rgb), .vga_hs(hs), .vga_vs(vs), .vga_hblank(hb), .vga_vblank(vb),
        .loader_busy(busy), .loader_overflow(overflow), .loader_timeout(timeout),
        .sdram_refreshing(refreshing)
    );

    // Reloj de la SDRAM: clk_system invertido (lo que hace el altddio_out)
    wire sdram_clk = ~clk_system;

    sdram_model sdram (
        .clk(sdram_clk), .cke(sd_cke), .ncs(sd_ncs), .nras(sd_nras), .ncas(sd_ncas),
        .nwe(sd_nwe), .ba(sd_ba), .a(sd_a), .dqm(sd_dqm),
        .dq_in(dq_ctrl), .dq_in_oe(dq_ctrl_oe),
        .dq_out(dq_sdram), .dq_out_oe(dq_sdram_oe)
    );

    // ---------------- Lo esperado ----------------
    // Direccion de byte del bus -> {banco, fila, columna, byte} en la SDRAM,
    // con el mismo reparto que memory_arbiter + sdram_wishbone
    logic [7:0] expected [int unsigned];

    function automatic int unsigned sdram_key(input logic [23:0] a);
        int b   = a[23:22];
        int row = {1'b0, a[13:2]};
        int col = {a[21:14], a[1]};
        return (b << 22) | (row << 9) | col;
    endfunction

    // ---------------- data_io simulado ----------------
    // Un byte cada 'gap' ciclos de clk_bus, como llegan del SPI
    task automatic download(input logic [5:0] index, input logic [7:0] data[], input int gap);
        @(posedge clk_bus);
        ioctl_index    <= {2'b00, index};
        ioctl_download <= 1;
        repeat (4) @(posedge clk_bus);
        for (int i = 0; i < data.size(); i++) begin
            ioctl_addr <= 27'(i);
            ioctl_dout <= data[i];
            ioctl_wr   <= 1;
            @(posedge clk_bus);
            ioctl_wr   <= 0;
            repeat (gap - 1) @(posedge clk_bus);
        end
        repeat (4) @(posedge clk_bus);
        ioctl_download <= 0;
        @(posedge clk_bus);
        while (busy) @(posedge clk_bus);
    endtask

    // ---------------- Medidas ----------------
    int max_fifo = 0;
    always @(posedge clk_bus) begin
        int used = int'(dut.loader.wr_ptr - dut.loader.rd_ptr);
        if (used > max_fifo) max_fifo = used;
    end

    int wb_writes = 0;
    always @(posedge clk_bus) if (dut.ld_cyc && dut.ld_stb && dut.ld_ack) wb_writes++;

    // Barrido: contar relojes de pixel entre hsync y lineas entre vsync
    int px_cnt = 0, h_period = 0, line_cnt = 0, v_lines = 0, frames = 0, lit = 0, lit_frame = 0;
    logic hs_d = 1, vs_d = 1;
    always @(posedge clk_pixel) begin
        px_cnt++;
        hs_d <= hs; vs_d <= vs;
        if (!hb && !vb && rgb != 12'h000) lit++;
        if (hs_d && !hs) begin h_period = px_cnt; px_cnt = 0; line_cnt++; end
        if (vs_d && !vs) begin v_lines = line_cnt; line_cnt = 0; frames++; lit_frame = lit; lit = 0; end
    end

    logic [7:0] fbuf [0:(1<<20)-1];

    // Muestreo de una linea visible (la 240) para ver las barras
    bit sample_line = 0;
    int n_colors = 0, n_changes = 0, n_idx = 0, n_bars = 0;
    always @(posedge clk_pixel) begin
        static bit seen_i[256];
        if (sample_line && frames >= 5 && dut.video_controller.ppu2pal_de) begin
            if (!seen_i[dut.video_controller.ppu2pal_color]) begin seen_i[dut.video_controller.ppu2pal_color] = 1; n_idx++; end
        end
    end
    logic [11:0] line_px[$];
    int dumped = 0;
    always @(posedge clk_pixel) begin
        if (sample_line && frames == 5 && line_cnt == 240 && !hb && !vb && dumped == 0) line_px.push_back(rgb);
        if (sample_line && frames == 5 && line_cnt == 241 && dumped == 0 && line_px.size() > 0) begin
            string s = "";
            int run = 1;
            dumped = 1;
            for (int i = 1; i <= line_px.size(); i++) begin
                if (i < line_px.size() && line_px[i] == line_px[i-1]) run++;
                else begin s = {s, $sformatf("%03h*%0d ", line_px[i-1], run)}; run = 1; end
            end
            $display("   linea 240 (color*pixeles, %0d px): %s", line_px.size(), s);
            run = 1;
            for (int i = 1; i <= line_px.size(); i++) begin
                if (i < line_px.size() && line_px[i] == line_px[i-1]) run++;
                else begin if (run == 40) n_bars++; run = 1; end
            end
        end
    end
    always @(posedge clk_pixel) begin
        static bit seen[4096];
        static logic [11:0] prev = 0;
        static int last_frame = -1;
        if (sample_line && frames >= 5 && line_cnt == 240 && !hb && !vb) begin
            if (!seen[rgb]) begin seen[rgb] = 1; n_colors++; end
            if (rgb != prev) n_changes++;
            prev = rgb;
        end
    end

    // ---------------- Guion de bus ----------------
    function automatic void script_add(ref logic [7:0] s[$], input logic [23:0] adr, input logic [7:0] d);
        s.push_back(adr[23:16]); s.push_back(adr[15:8]); s.push_back(adr[7:0]); s.push_back(d);
    endfunction

    // ---------------- Prueba ----------------
    int fails = 0;
    realtime t0;

    initial begin
        logic [7:0] img[], rom[];
        logic [7:0] scr[$];
        logic [7:0] scr_arr[];

        $display("== Esperando a que la SDRAM termine de inicializarse (200 us)");
        wait (pll_locked);
        #210us;
        t0 = $realtime;

        // 1) Imagen de 16 KB en 0x000000 al ritmo del SPI (un byte cada 18 ciclos a 54 MHz = 3 MB/s)
        img = new[16384];
        foreach (img[i]) begin img[i] = 8'((i * 7) ^ (i >> 8)); expected[i] = img[i]; end
        $display("== Cargando imagen de 16 KB (indice 1) a 3 MB/s");
        download(6'd1, img, 18);
        $display("   escrituras de bus: %0d, FIFO maxima: %0d, overflow: %0d", wb_writes, max_fifo, overflow);

        // 2) ROM de 2 KB en 0xC00000, a rafaga mas rapida (un byte cada 6 ciclos = 9 MB/s)
        rom = new[2048];
        foreach (rom[i]) begin rom[i] = 8'(255 - (i & 255) ^ (i >> 3)); expected[32'hC00000 + i] = rom[i]; end
        max_fifo = 0;
        $display("== Cargando ROM de 2 KB (indice 0) a 9 MB/s");
        download(6'd0, rom, 6);
        $display("   FIFO maxima: %0d, overflow: %0d", max_fifo, overflow);

        // 3) Guion: CRTC (indice/dato en FF0120/FF0121), paleta y memoria
        script_add(scr, 24'hFF0120, 8'h01); script_add(scr, 24'hFF0121, 8'd40);
        script_add(scr, 24'hFF0120, 8'h0C); script_add(scr, 24'hFF0121, 8'h00);
        script_add(scr, 24'hFF0100, 8'h00); script_add(scr, 24'hFF0101, 8'h0F);
        script_add(scr, 24'h123457, 8'hA5); expected[32'h123457] = 8'hA5;
        scr_arr = new[scr.size()];
        foreach (scr[i]) scr_arr[i] = scr[i];
        $display("== Ejecutando guion de bus (indice 2): %0d escrituras", scr.size()/4);
        download(6'd2, scr_arr, 18);
        $display("   timeout: %0d", timeout);
        if (dut.video_controller.crtc.reg_h_displayed != 8'd40) begin
            $display("   FALLO: el CRTC no ha recibido R1"); fails++;
        end

        // 4) Comprobar la SDRAM
        begin
            int bad = 0;
            foreach (expected[a]) begin
                int unsigned k = sdram_key(24'(a));
                logic [15:0] w = sdram.mem.exists(k) ? sdram.mem[k] : 16'hxxxx;
                logic [7:0]  got = a[0] ? w[15:8] : w[7:0];
                if (got !== expected[a]) begin
                    bad++;
                    if (bad <= 10) $display("   FALLO: byte 0x%06h = %02h, esperado %02h", a, got, expected[a]);
                end
            end
            $display("== Comprobados %0d bytes en la SDRAM: %0d mal", expected.size(), bad);
            if (bad) fails++;
        end

        // 5) Un cuadro y pico de video para medir el barrido
        $display("== Esperando dos cuadros de video");
        wait (frames >= 3);
        $display("   linea: %0d relojes de pixel (esperado 858), cuadro: %0d lineas (esperado 525)", h_period, v_lines);
        $display("   pixeles no negros en el ultimo cuadro: %0d", lit_frame);
        if (h_period != 858 || v_lines != 525) fails++;

        // 6) Refresco
        begin
            real us = ($realtime - t0) / 1000.0;
            $display("== Auto-refresh: %0d en %0.0f us (%0.2f us de media; hacen falta <= 7.8)",
                     sdram.n_ref, us, us / sdram.n_ref);
            if (sdram.n_ref == 0 || us / sdram.n_ref > 7.8) fails++;
        end

        if (overflow) begin $display("FALLO: overflow en la FIFO"); fails++; end
        if (timeout)  begin $display("FALLO: timeout en el bus");    fails++; end

        $display("== SDRAM: %0d ACTIVE, %0d READ, %0d WRITE, %0d REFRESH, %0d errores de protocolo/tiempos",
                 sdram.n_act, sdram.n_rd, sdram.n_wr, sdram.n_ref, sdram.errors);
        // 7) Opcional: ejecutar un .WBS de verdad (+wbs=FICHERO) y mirar la imagen
        begin
            string wbs;
            if ($value$plusargs("wbs=%s", wbs)) begin
                int fd = $fopen(wbs, "rb");
                int n;
                logic [7:0] buf8[];
                n = $fread(fbuf, fd);
                $fclose(fd);
                buf8 = new[n];
                foreach (buf8[i]) buf8[i] = fbuf[i];
                $display("== Ejecutando %s (%0d escrituras)", wbs, n / 4);
                download(6'd2, buf8, 18);
                $display("   timeout: %0d, overflow: %0d", timeout, overflow);
                sample_line = 1;
                wait (frames >= 6);
                $display("   linea 240: %0d colores distintos, %0d barras de 40 pixeles", n_colors, n_bars);
                $display("   CRTC R18=%02h R20=%02h R21=%02h  bpp=%0d linear=%0d  indices de paleta distintos=%0d",
                         dut.video_controller.crtc.reg_video_control, dut.video_controller.crtc.reg_addr_mode,
                         dut.video_controller.crtc.reg_pixel_ctrl, dut.video_controller.crtc_bpp,
                         dut.video_controller.cfg_linear, n_idx);
                if (n_colors < 16 || n_bars < 15) fails++;
            end
        end

        if (sdram.errors) fails++;
        if (fails == 0) $display("RESULTADO: OK");
        else            $display("RESULTADO: %0d FALLOS", fails);
        $finish;
    end

    initial begin
        #200ms;
        $display("TIMEOUT de simulacion");
        $finish;
    end

endmodule
