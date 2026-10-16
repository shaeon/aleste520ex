// ============================================================================
// tb_fase2.sv - Banco de pruebas de la fase 2: el Z80 ejecutando una ROM
//
// aleste_core + modelo de SDRAM. Carga la ROM (+rom=FICHERO) por el indice 0
// como lo haria el firmware MiST, deja correr la CPU y comprueba:
//   - que la CPU no arranca hasta tener la ROM entera
//   - los resultados que la ROM de diagnostico deja en RESULTS (C03F10):
//     +0 = A5 al terminar, +1..+4 = Z80, MMU, RAM, MMIO (1 = OK)
//   - que el contador de la ROM avanza (la CPU sigue viva)
//   - errores de protocolo/tiempos de la SDRAM
// y vuelca un cuadro de la salida VGA a obj/pantalla.ppm.
// ============================================================================
`timescale 1ns/1ps

module tb_fase2;

    logic clk_system = 0, clk_bus = 0, clk_pixel = 0, pll_locked = 0;
    always #4.6296 clk_system = ~clk_system;
    // Reloj de captura de las lecturas (SDRAM_DQ_CLK): clk_system retrasado 1,5 ns
    wire clk_dq;
    assign #1.5 clk_dq = clk_system;
    always @(posedge clk_system) clk_bus <= ~clk_bus;
    logic [1:0] div4 = 0;
    always @(posedge clk_system) begin
        div4 <= div4 + 1;
        if (div4 == 2'd1 || div4 == 2'd3) clk_pixel <= ~clk_pixel;
    end
    initial #200 pll_locked = 1;

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
    wire        busy, overflow, timeout, refreshing, cpu_running, cpu_halted;

    aleste_core dut (
`ifdef SDRAM_DQ_CLK
        .sdram_dq_clk(clk_dq),
`endif
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
        .sdram_refreshing(refreshing), .cpu_running(cpu_running), .cpu_halted(cpu_halted)
    );

    sdram_model sdram (
        .clk(~clk_system), .cke(sd_cke), .ncs(sd_ncs), .nras(sd_nras), .ncas(sd_ncas),
        .nwe(sd_nwe), .ba(sd_ba), .a(sd_a), .dqm(sd_dqm),
        .dq_in(dq_ctrl), .dq_in_oe(dq_ctrl_oe),
        .dq_out(dq_sdram), .dq_out_oe(dq_sdram_oe)
    );

    // Byte del bus -> palabra del modelo (reparto de memory_arbiter + sdram_wishbone)
    function automatic logic [7:0] peek(input logic [23:0] a);
        int unsigned k = (int'(a[23:22]) << 22) | (int'({1'b0, a[13:2]}) << 9) | int'({a[21:14], a[1]});
        logic [15:0] w = sdram.mem.exists(k) ? sdram.mem[k] : 16'h0000;
        return a[0] ? w[15:8] : w[7:0];
    endfunction

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
    endtask

    // ---------------- La CPU no debe arrancar antes de tiempo ----------------
    bit loading = 0, early_start = 0;
    always @(posedge clk_bus) if (loading && cpu_running) early_start = 1;

    // ---------------- Latencia maxima de los accesos de la CPU --------------
    int lat = 0, max_lat = 0, n_err = 0;
    always @(posedge clk_bus) begin
        if (dut.z80_cyc && dut.z80_stb) begin
            lat++;
            if (dut.z80_ack || dut.z80_err) begin
                if (lat > max_lat) max_lat = lat;
                if (dut.z80_err) n_err++;
                lat = 0;
            end
        end else lat = 0;
    end

    // ---------------- Traza de E/S de la CPU (+trace_io) ---------------------
    bit trace_io = 0;
    initial trace_io = $test$plusargs("trace_io");
    int n_io = 0;
    always @(posedge clk_bus)
        if (trace_io && dut.z80_cyc && dut.z80_stb && (dut.z80_ack || dut.z80_err)
            && dut.z80_adr[23:16] == 8'hFF && !dut.z80_we && n_io < 80) begin
            n_io++;
            $display("   E/S %s %06h = %02h%s", dut.z80_we ? "OUT" : "IN ", dut.z80_adr,
                     dut.z80_we ? dut.z80_dat_out : dut.z80_dat_in, dut.z80_err ? "  (error de bus)" : "");
        end

    // Lo que el Z80 recoge en los ciclos de lectura de E/S (+trace_io)
    logic iorq_d = 1;
    int n_cpu = 0;
    always @(posedge clk_bus) begin
        iorq_d <= dut.z80_sys.z80_iorq_n;
        if (trace_io && dut.z80_sys.z80_cke && !dut.z80_sys.z80_iorq_n && !dut.z80_sys.z80_rd_n && n_cpu < 400) begin
            n_cpu++;
            if (0)
            $display("   [%0t] IORQ rd A=%04h wait_n=%b di=%02h dat_in_reg=%02h st=%0d tstate=%b mmu_acc=%b",
                     $time, dut.z80_sys.z80_a, dut.z80_sys.z80_wait_n, dut.z80_sys.z80_di,
                     dut.z80_sys.wbm_dat_in_reg, dut.z80_sys.wbm_state, dut.z80_sys.z80_inst.tstate,
                     dut.z80_sys.native_mmu_access);
        end
    end

    int win = 0;
    always @(posedge clk_bus) begin
        if (trace_io && dut.z80_sys.z80_cke) begin
            if (!dut.z80_sys.z80_iorq_n && !dut.z80_sys.z80_rd_n && dut.z80_sys.z80_a[7:0] == 8'h01) win = 6;
            if (win > 0) begin
                win--;
                $display("   cen: mc=%b ts=%b iorq_n=%b rd_n=%b wait_n=%b di=%02h di_reg=%02h A=%02h",
                         dut.z80_sys.z80_inst.mcycle, dut.z80_sys.z80_inst.tstate, dut.z80_sys.z80_iorq_n,
                         dut.z80_sys.z80_rd_n, dut.z80_sys.z80_wait_n, dut.z80_sys.z80_di,
                         dut.z80_sys.z80_inst.di_reg, dut.z80_sys.z80_inst.i_tv80_core.ACC);
            end
        end
    end

    // Accesos de la CPU por segundo durante el volcado (bucle principal)
    longint n_acc = 0;
    realtime t_acc0;
    always @(posedge clk_bus) if (dump_req && !dumped && dut.z80_cyc && dut.z80_stb && dut.z80_ack) n_acc++;

    // ---------------- Volcado de un cuadro --------------------------------
    int frame_no = 0;
    bit dump_req = 0, dumping = 0, dumped = 0;
    int fd_img, px_x = 0, px_y = 0;
    logic vs_d = 1, hb_d = 1;
    always @(posedge clk_pixel) begin
        vs_d <= vs;
        hb_d <= hb;
        if (vs_d && !vs) begin
            frame_no++;
            if (dumping) begin dumping = 0; dumped = 1; $fclose(fd_img); end
            if (dump_req && !dumped && !dumping) begin
                fd_img = $fopen("pantalla.ppm", "wb");
                $fwrite(fd_img, "P6\n720 480\n255\n");
                dumping = 1;
            end
        end
        if (dumping && !hb && !vb)
            $fwrite(fd_img, "%c%c%c", {rgb[11:8], rgb[11:8]}, {rgb[7:4], rgb[7:4]}, {rgb[3:0], rgb[3:0]});
    end

    logic [7:0] fbuf [0:(1<<16)-1];
    int fails = 0;

    initial begin
        string romf;
        logic [7:0] rom[];
        int n, fd;
        logic [15:0] c1, c2;

        if (!$value$plusargs("rom=%s", romf)) romf = "../../sd/ALESTE.ROM";
        fd = $fopen(romf, "rb");
        if (fd == 0) begin $display("No encuentro la ROM %s", romf); $finish; end
        n = $fread(fbuf, fd);
        $fclose(fd);
        rom = new[n];
        foreach (rom[i]) rom[i] = fbuf[i];

        wait (pll_locked);
        #210us;
        if (cpu_running) begin $display("FALLO: la CPU corre sin ROM"); fails++; end

        $display("== Cargando %s (%0d bytes) por el indice 0", romf, n);
        loading = 1;
        download(6'd0, rom, 18);
        loading = 0;
        wait (cpu_running);
        $display("   la CPU arranca a los %0.2f ms", $realtime / 1.0e6);
        if (early_start) begin $display("FALLO: la CPU arranco antes de acabar la carga"); fails++; end

        // esperar a que la ROM termine sus pruebas
        fork
            begin
                wait (peek(24'hC03F10) == 8'hA5);
            end
            begin
                #150ms;
            end
        join_any
        disable fork;
        if (peek(24'hC03F10) != 8'hA5) begin
            $display("FALLO: la ROM no termina (RESULTS=%02h)", peek(24'hC03F10)); fails++;
        end
        $display("== Pruebas de la ROM terminadas a los %0.1f ms", $realtime / 1.0e6);
        $display("   Z80=%0d MMU=%0d RAM=%0d MMIO=%0d   (1 = OK)",
                 peek(24'hC03F11), peek(24'hC03F12), peek(24'hC03F13), peek(24'hC03F14));
        $display("   MMIO leido: CRTC R1=%02h (esperado 28)  paleta[9].lo=%02h (esperado 5F)",
                 peek(24'hC03F15), peek(24'hC03F16));
        for (int i = 1; i <= 4; i++) if (peek(24'hC03F10 + i) != 1) fails++;

        // la CPU sigue viva: el contador avanza
        c1 = {peek(24'hC03F03), peek(24'hC03F02)};
        t_acc0 = $realtime;
        dump_req = 1;
        wait (dumped);
        begin
            real secs = ($realtime - t_acc0) * 1.0e-9;
            real acc_s = n_acc / secs;
            // bucle de espera: dec bc / ld a,b / or c / jr nz,x = 5 lecturas por vuelta
            $display("== CPU: %0.2f M accesos/s; espera de 65536 vueltas = %0.0f ms",
                     acc_s / 1.0e6, 65536.0 * 5.0 / acc_s * 1000.0);
        end
        c2 = {peek(24'hC03F03), peek(24'hC03F02)};
        $display("== Contador: %04h -> %04h", c1, c2);
        if (c2 == c1) begin $display("FALLO: el contador no avanza"); fails++; end
        $display("   cuadro volcado en obj/pantalla.ppm");

        $display("== Bus: latencia maxima de la CPU %0d ciclos de 54 MHz, %0d errores de bus", max_lat, n_err);
        $display("== SDRAM: %0d errores de protocolo/tiempos", sdram.errors);
        if (sdram.errors) fails++;
        if (n_err) fails++;
        if (fails == 0) $display("RESULTADO: OK");
        else            $display("RESULTADO: %0d FALLOS", fails);
        $finish;
    end

    initial begin
        #400ms;
        $display("TIMEOUT de simulacion");
        $finish;
    end

endmodule
