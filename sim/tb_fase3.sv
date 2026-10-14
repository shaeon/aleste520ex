`timescale 1ns/1ps

module tb_fase3;

    logic clk_system = 0, clk_bus = 0, clk_pixel = 0, pll_locked = 0;
    logic clk_vid = 0;
    // +reset_during_load: reset del OSD activo durante la descarga de la ROM
    // (como puede hacer el firmware en el primer arranque)
    logic ureset = 1'b0;
    logic [1:0] turbo = 2'd0;                                   // +turbo=N: velocidad del Z80
    initial begin int tv; if ($value$plusargs("turbo=%d", tv)) turbo = 2'(tv); end
    int n_m1 = 0; logic m1_q = 1;                               // instrucciones (ciclos M1)
    always @(posedge clk_bus) begin m1_q <= dut.z80_sys.z80_m1_n; if (m1_q && !dut.z80_sys.z80_m1_n) n_m1++; end
    final $display("== Instrucciones ejecutadas (M1): %0d", n_m1);
    logic [8:0] ms_x = 0, ms_y = 0; logic [7:0] ms_flags = 8'h08; logic ms_strobe = 0;   // raton PS/2
    initial if ($test$plusargs("reset_during_load")) begin
        ureset = 1'b1; #40ms; ureset = 1'b0;
        $display("== reset de usuario activo de 0 a 40 ms (durante la descarga)");
    end
    // Teclado PS/2 (como lo entrega user_io) y audio
    logic       k_strobe = 0, k_pressed = 0;
    logic [7:0] k_code = 0;
    logic [15:0] aud_l;

    // ---- SD del firmware MiST: +dsk=imagen se monta en la unidad A a los 100 ms
    logic        fdc_fast = 0;
    logic [2:0]  img_mounted = 0;
    logic [31:0] img_size = 0, sd_lba;
    logic [2:0]  sd_rd, sd_wr;
    logic        sd_ack = 0, sd_buff_wr = 0;
    logic [8:0]  sd_buff_addr = 0;
    logic [7:0]  sd_buff_dout = 0;
    logic [7:0]  dsk [0:(1<<20)-1];
    int          sd_reads = 0;
    // Registro de la conversacion CPU <-> 765 (+trace_fdc): escrituras en FB7F
    // (ordenes y parametros) y lecturas de FB7F fuera de la fase de datos
    // (bytes de resultado). Las lecturas de estado (FB7E) no se apuntan.
    int n_fdc_log = 0;
    // MagicSound (+trace_ms): escrituras a la tarjeta y lecturas DMA por canal
    int n_ms = 0;
    int ms_reads [4] = '{0, 0, 0, 0};
    always @(posedge clk_bus) if ($test$plusargs("trace_ms")) begin
        if (dut.ms_ack && dut.sys_we && n_ms < 600) begin
            n_ms++;
            $display("   [%0.3f ms] MS %04h <- %02h", $realtime/1e6, dut.sys_adr[15:0], dut.sys_dat);
        end
        if (dut.ms.dma_cyc && dut.m2_ack && dut.m2_owner) begin
            if (ms_reads[dut.ms.dma_ch] < 6 || ms_reads[dut.ms.dma_ch] % 4000 == 0)
                $display("   [%0.3f ms] DMA canal %0d lee %06h = %02h (pagina %0d)", $realtime/1e6, dut.ms.dma_ch,
                         dut.ms.dma_adr, dut.m2_dat, dut.ms.dma_adr[19:14]);
            ms_reads[dut.ms.dma_ch]++;
        end
    end
    final if ($test$plusargs("trace_ms"))
        $display("== MagicSound: lecturas DMA por canal A=%0d B=%0d C=%0d D=%0d; mascara=%b, volumen=%h %h %h %h",
                 ms_reads[0], ms_reads[1], ms_reads[2], ms_reads[3], dut.ms.dmask,
                 dut.ms.vol[0], dut.ms.vol[1], dut.ms.vol[2], dut.ms.vol[3]);
    // Modo Aleste (+trace_aleste): FABF, mapper MSX, reloj y ordenes de lectura
    int n_al = 0;
    always @(posedge clk_bus) if ($test$plusargs("trace_aleste") && n_al < 300) begin
        if (dut.ext_ack) begin n_al++;
            $display("   [%0.2f ms] FABF <- %02h  (8253 reg%0d <- %02h si D4)", $realtime/1e6, dut.extport, dut.sys_adr[1:0], dut.ppi_pa_o); end
        if (dut.ga_ack && dut.sys_dat[7:6] == 2'b11 && dut.extport[2]) begin n_al++;
            $display("   [%0.2f ms] mapper: cuarto %0d <- pagina %0d", $realtime/1e6, dut.sys_adr[9:8], dut.sys_dat[5:0]); end
        if (dut.rtc_drive && dut.ppi_ack && !dut.sys_we && dut.sys_adr[9:8] == 2'b00) begin n_al++;
            $display("   [%0.2f ms] reloj: lee reg %02h = %02h", $realtime/1e6, dut.rtc.addr, dut.rtc_dout); end
    end
    // Ultimas 24 lecturas de la CPU a FB7E/FB7F, volcadas cuando el 765 entra en
    // resultados tras un READ DATA (+trace_ring). No depende del instante exacto.
    logic [15:0] ring_adr [0:23];
    logic [7:0]  ring_dat [0:23], ring_msr [0:23], ring_st [0:23];
    logic [15:0] ring_left [0:23];
    real         ring_t   [0:23];
    int ring_i = 0, n_dumps = 0, post = 0;
    logic [7:0] st_prev = 0;
    always @(posedge clk_bus) if ($test$plusargs("trace_ring")) begin
        if (dut.z80_sys.wbm_data_valid && (dut.z80_sys.wbm_adr_o[15:0] == 16'hFB7E || dut.z80_sys.wbm_adr_o[15:0] == 16'hFB7F)) begin
            ring_adr[ring_i % 24] = dut.z80_sys.wbm_adr_o[15:0];
            ring_dat[ring_i % 24] = dut.z80_sys.wbm_dat_in_reg;
            ring_msr[ring_i % 24] = dut.fdc.m_status;
            ring_st [ring_i % 24] = 8'(dut.fdc.fdc.state);
            ring_left[ring_i % 24] = dut.fdc.fdc.i_bytes_to_read;
            ring_t  [ring_i % 24] = $realtime / 1e6;
            ring_i++;
            if (post > 0) begin
                post--;
                $display("     DESPUES [%0.4f ms] %04h -> %02h   (MSR real %02h, estado %0d)  PC ultimo M1=%04h",
                         $realtime/1e6, dut.z80_sys.wbm_adr_o[15:0], dut.z80_sys.wbm_dat_in_reg, dut.fdc.m_status,
                         dut.fdc.fdc.state, last_pc);
            end
        end
        st_prev <= 8'(dut.fdc.fdc.state);
        if (dut.fdc.fdc.state == 42 && st_prev != 42 && n_dumps < 6) begin   // entra en READ_RESULTS
            n_dumps++;
            post = 8;
            $display("== [%0.3f ms] el 765 entra en resultados; ultimas lecturas de la CPU:", $realtime/1e6);
            for (int k = 24; k >= 1; k--)
                if (ring_i - k >= 0)
                    $display("     [%0.4f ms] %04h -> %02h   (MSR real %02h, estado %0d, quedan %0d)",
                             ring_t[(ring_i - k) % 24], ring_adr[(ring_i - k) % 24], ring_dat[(ring_i - k) % 24],
                             ring_msr[(ring_i - k) % 24], ring_st[(ring_i - k) % 24], ring_left[(ring_i - k) % 24]);
        end
    end
    // Desfase CPU / 765 (+trace_sync): en cada acceso a FB7F del bucle de datos
    // se compara cuantas lecturas ha hecho la CPU con cuantos bytes ha entregado
    // el 765 (i_bytes_to_read). Se imprime el contexto del primer desfase.
    int cpu_rd = 0, fdc_given = 0, n_sync = 0;
    logic [15:0] btr_d = 0;
    logic        exec_d = 0;
    logic [5:0]  nrd_low = 0, nrd_high = 0;
    always @(posedge clk_bus) if ($test$plusargs("trace_sync")) begin
        if (!dut.fdc_nrd) begin nrd_low <= nrd_low + 1; nrd_high <= 0; end
        else begin nrd_high <= (nrd_high == 6'h3F) ? nrd_high : nrd_high + 1; nrd_low <= 0; end
        btr_d  <= dut.fdc.fdc.i_bytes_to_read;
        exec_d <= dut.fdc.m_status[5];
        if (dut.fdc.m_status[5] && !exec_d) begin cpu_rd = 0; fdc_given = 0; end       // empieza la fase de datos
        if (dut.fdc.m_status[5] && dut.fdc.fdc.i_bytes_to_read != btr_d && btr_d != 0) fdc_given++;
        if (dut.fdc_ack && dut.sys_adr[0] && !dut.sys_we && (dut.fdc.m_status[5] || exec_d)) begin
            cpu_rd++;
            if (cpu_rd != fdc_given && n_sync < 12) begin
                n_sync++;
                $display("   [%0.3f ms] DESFASE: CPU %0d lecturas, 765 %0d bytes; MSR=%02h estado=%0d buff_wait=%0d sd_busy=%0d dato=%02h",
                         $realtime/1e6, cpu_rd, fdc_given, dut.fdc.m_status, dut.fdc.fdc.state,
                         dut.fdc.buff_wait, dut.fdc.sd_busy_sector, dut.fdc_dat);
            end
        end
    end
    // Lo que recibe de verdad la CPU (+trace_cpu): dato guardado para el Z80 en
    // cada lectura de FB7F fuera de la fase de datos, y escrituras de la CPU
    // en el buffer de resultados de AMSDOS (BE4C-BE52)
    int n_cpu_log = 0;
    always @(posedge clk_bus) if ($test$plusargs("trace_cpu") && n_cpu_log < 2000) begin
        // ventana +pc_from/+pc_to: TODAS las lecturas de la CPU a FB7E/FB7F
        if (dut.z80_sys.wbm_data_valid && (dut.z80_sys.wbm_adr_o[15:0] == 16'hFB7E || dut.z80_sys.wbm_adr_o[15:0] == 16'hFB7F) &&
            $realtime >= pc_from * 1.0e6 && $realtime <= pc_to * 1.0e6) begin
            n_cpu_log++;
            $display("   [%0.4f ms] CPU lee %04h = %02h   MSR real=%02h estado=%0d quedan=%0d",
                     $realtime/1e6, dut.z80_sys.wbm_adr_o[15:0], dut.z80_sys.wbm_dat_in_reg, dut.fdc.m_status,
                     dut.fdc.fdc.state, dut.fdc.fdc.i_bytes_to_read);
        end
        // estado (FB7E) al final de la fase de datos: lo que recibe la CPU y el MSR real en ese momento
        if (dut.z80_sys.wbm_data_valid && dut.z80_sys.wbm_adr_o[15:0] == 16'hFB7E &&
            (dut.fdc.fdc.i_bytes_to_read < 3 || dut.fdc.fdc.state == 42) && dut.fdc.fdc.state != 0) begin
            n_cpu_log++;
            $display("   [%0.3f ms] CPU recibe de FB7E (estado): %02h   MSR real=%02h  fdc_dat=%02h  quedan=%0d",
                     $realtime/1e6, dut.z80_sys.wbm_dat_in_reg, dut.fdc.m_status, dut.fdc_dat, dut.fdc.fdc.i_bytes_to_read);
        end
        if (dut.z80_sys.wbm_data_valid && dut.z80_sys.wbm_adr_o[15:0] == 16'hFB7F && !dut.fdc.m_status[5]) begin
            n_cpu_log++;
            $display("   [%0.2f ms] CPU recibe de FB7F: %02h", $realtime/1e6, dut.z80_sys.wbm_dat_in_reg);
        end
        if (dut.z80_sys.wbm_cyc_o && dut.z80_sys.wbm_stb_o && dut.z80_sys.wbm_we_o && dut.z80_sys.wbm_ack_i &&
            dut.z80_sys.z80_a[15:0] >= 16'hBE4B && dut.z80_sys.z80_a[15:0] <= 16'hBE52 && !dut.z80_sys.z80_mreq_n) begin
            n_cpu_log++;
            $display("   [%0.2f ms] CPU escribe %04h = %02h", $realtime/1e6, dut.z80_sys.z80_a[15:0], dut.z80_sys.wbm_dat_o);
        end
    end
    // Bytes de la fase de datos de cada orden (+trace_fdc): cuantos y los primeros 12
    int exec_n = 0, n_exec_done = 0;
    bit pc_window = 0;
    logic [7:0] exec_first [0:11];
    always @(posedge clk_bus)
        if ($test$plusargs("trace_fdc") && dut.fdc_ack && dut.sys_adr[0] && !dut.sys_we) begin
            if (dut.fdc.m_status[5]) begin
                if (exec_n < 12) exec_first[exec_n] = dut.fdc_dat;
                exec_n++;
            end else if (exec_n != 0) begin
                $display("   [%0.1f ms] FASE DE DATOS: %0d bytes, primeros: %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h",
                         $realtime/1e6, exec_n, exec_first[0], exec_first[1], exec_first[2], exec_first[3], exec_first[4],
                         exec_first[5], exec_first[6], exec_first[7], exec_first[8], exec_first[9], exec_first[10], exec_first[11]);
                exec_n = 0;
                if (n_exec_done++ == 0) pc_window = 1;
            end
        end
    always @(posedge clk_bus)
        if ($test$plusargs("trace_fdc") && dut.fdc_ack && n_fdc_log < 400 && dut.sys_adr[0]) begin
            if (dut.sys_we) begin
                pc_window = 0;                                  // siguiente escritura al 765: fin de la traza
                n_fdc_log++;
                $display("   [%0.1f ms] FDC <- %02h", $realtime/1e6, dut.sys_dat);
            end else if (!dut.fdc.m_status[5]) begin
                n_fdc_log++;
                $display("   [%0.1f ms] FDC -> %02h   (MSR=%02h INT=%0d)", $realtime/1e6, dut.fdc_dat, dut.fdc.m_status, dut.fdc_int);
            end
        end
    // Traza de los bytes del registro de datos del 765 (+trace_fdc)
    int n_fdc = 0, n_data = 0;
    bit sd_busy_tb = 0;
    always @(posedge clk_bus) sd_busy_tb <= (sd_rd != 0);
    always @(posedge clk_bus) begin
        if ($test$plusargs("trace_fdc") && dut.fdc_ack && dut.sys_adr[0] && !dut.sys_we && dut.fdc.fdc.state == 13)
            n_data++;                                   // bytes de datos del sector: solo se cuentan
        else if ($test$plusargs("trace_fdc") && dut.fdc_ack && dut.sys_adr[0] && n_fdc < 600) begin
            if (n_data) begin $display("   ... %0d bytes de datos", n_data); n_data = 0; end
            n_fdc++;
            $display("   [%0.3f ms] FDC %s %02h  (MSR antes=%02h, fase=%0d, INT=%0d)", $realtime/1e6,
                     dut.sys_we ? "<-" : "->", dut.sys_we ? dut.sys_dat : dut.fdc_dat,
                     dut.fdc.m_status, dut.fdc.fdc.state, dut.fdc_int);
            $fflush;
        end
        if ($test$plusargs("trace_fdc") && sd_rd != 0 && !sd_ack && !sd_busy_tb) begin
            $display("   [%0.3f ms] SD lee bloque %0d", $realtime/1e6, sd_lba); $fflush;
        end
    end

    // Registro de accesos de la CPU a la disquetera: +fdc_log=fichero
    int fdc_fd = 0;
    initial begin
        string lf;
        if ($value$plusargs("fdc_log=%s", lf)) fdc_fd = $fopen(lf, "w");
    end
    always @(posedge clk_bus) if (fdc_fd != 0 && dut.fdc_ack)
        begin
            $fwrite(fdc_fd, "%9.3f ms %s %s %02h  MSR=%02h fase=%0d INT=%0d\n", $realtime/1e6,
                    dut.sys_we ? "OUT" : "IN ", dut.sys_adr[0] ? "datos " : "estado",
                    dut.sys_we ? dut.sys_dat : dut.fdc_dat, dut.fdc.m_status, dut.fdc.fdc.state, dut.fdc_int);
            $fflush(fdc_fd);
        end
    initial begin
        string f;
        int fd, n;
        if ($value$plusargs("dsk=%s", f)) begin
            fd = $fopen(f, "rb"); n = $fread(dsk, fd); $fclose(fd);
            if ($test$plusargs("fdc_fast")) fdc_fast = 1;
            #100ms;
            @(posedge clk_bus); img_size <= n; img_mounted <= 3'b001;
            repeat (50) @(posedge clk_bus); img_mounted <= 3'b000;
            $display("== Disco montado en A: %s (%0d bytes)", f, n);
        end
    end
    // ALESTE.CMO (+cmos=fichero): tercera imagen, se monta a los 50 ms
    logic [7:0] cmos_img [0:511];
    int cmos_writes = 0;
    initial begin
        string f; int fd, n;
        foreach (cmos_img[i]) cmos_img[i] = 8'h00;
        if ($value$plusargs("cmos=%s", f)) begin
            fd = $fopen(f, "rb"); n = $fread(cmos_img, fd); $fclose(fd);
            if ($value$plusargs("cmos_ms=%d", n)) #(n * 1ms); else #50ms;
            @(posedge clk_bus); img_size <= 512; img_mounted <= 3'b100;
            repeat (50) @(posedge clk_bus); img_mounted <= 3'b000;
            $display("== CMOS montado: %s", f);
        end
    end
    always @(posedge clk_bus) begin
        if ((sd_rd[2] || sd_wr[2]) && !sd_ack) begin
            automatic bit w = sd_wr[2];
            repeat (20) @(posedge clk_bus);
            sd_ack <= 1;
            for (int i = 0; i < 512; i++) begin
                @(posedge clk_bus); sd_buff_addr <= 9'(i);
                if (!w) begin sd_buff_dout <= cmos_img[i]; sd_buff_wr <= 1; @(posedge clk_bus); sd_buff_wr <= 0; end
                else begin @(posedge clk_bus); @(posedge clk_bus); cmos_img[i] = dut.sd_buff_din; end
            end
            @(posedge clk_bus); sd_ack <= 0;
            if (w) begin
                cmos_writes++;
                $display("== [%0.1f ms] CMOS guardado en la SD: 3C-3F = %02h %02h %02h %02h, 20 = %02h",
                         $realtime/1e6, cmos_img[60], cmos_img[61], cmos_img[62], cmos_img[63], cmos_img[32]);
            end else $display("== [%0.1f ms] CMOS leido de la SD", $realtime/1e6);
        end
    end
    // +cmos_poke_ms=N: a esa hora se cambia un byte de configuracion (registro 20h)
    initial begin
        int ms;
        if ($value$plusargs("cmos_poke_ms=%d", ms)) begin
            #(ms * 1ms);
            dut.rtc.ram[6'h20] = 8'h5A; dut.rtc.dirty = 1'b1;
            $display("== [%0d ms] cambio en la RAM del reloj (20h = 5A)", ms);
        end
    end
    always @(posedge clk_bus) begin
        if (sd_rd[1:0] != 0 && !sd_ack) begin
            sd_reads++;
            repeat (20) @(posedge clk_bus);
            sd_ack <= 1;
            for (int i = 0; i < 512; i++) begin
                @(posedge clk_bus); sd_buff_addr <= 9'(i); sd_buff_dout <= dsk[sd_lba * 512 + i]; sd_buff_wr <= 1;
                @(posedge clk_bus); sd_buff_wr <= 0;
            end
            @(posedge clk_bus); sd_ack <= 0;
        end
    end
    always #6.25 clk_vid = ~clk_vid;      // 80 MHz, de otro PLL (asincrono)
    always #4.6296 clk_system = ~clk_system;
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
    wire        busy, overflow, timeout, refreshing, cpu_running, cpu_halted, cpu_legacy;

`ifndef FDC_CYCLES
`define FDC_CYCLES 3857
`endif
    // make fase3 FDC_CYCLES=385: disco 10 veces mas rapido (solo simulacion)
    aleste_core #(.FDC_CYCLES(20'd`FDC_CYCLES)) dut (
        .clk_system, .clk_bus, .clk_pixel, .clk_vid, .pll_locked,
        .user_reset(ureset),
        // modo de arranque: AMSTRAD por defecto; +no_shift: Aleste 520EX (BOOTMENU);
        // +bios: Aleste BIOS (BS pulsado: SETUP)
        .boot_mode($test$plusargs("bios") ? 2'd2 : $test$plusargs("no_shift") ? 2'd0 : 2'd1),
        .key_strobe(k_strobe), .key_pressed(k_pressed), .key_extended(1'b0), .key_code(k_code),
        .joystick(8'h00), .audio_stereo(1'b0), .audio_l(aud_l), .audio_r(),
        .fdc_fast(fdc_fast), .fdc_one_drive(1'b0), .video_h_off(3'd0), .video_v_off(3'd0),
        .mouse_x(ms_x), .mouse_y(ms_y), .mouse_flags(ms_flags), .mouse_strobe(ms_strobe), .mist_rtc(64'd0), .cpc_mouse_en(1'b1), .amx_mouse_en(1'b0), .cpu_turbo(turbo),
        .tape_sound(1'b0), .tape_invert(1'b0), .tape_ext(1'b0), .test_tone(1'b0), .img_mounted(img_mounted), .img_wp(1'b0), .img_size(img_size),
        .sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack), .sd_buff_addr(sd_buff_addr),
        .sd_buff_dout(sd_buff_dout), .sd_buff_din(), .sd_buff_wr(sd_buff_wr),
        .ioctl_download, .ioctl_index, .ioctl_wr, .ioctl_addr, .ioctl_dout,
        .sdram_dq_i(dq_sdram_oe ? dq_sdram : dq_ctrl),
        .sdram_dq_o(dq_ctrl), .sdram_dq_oe(dq_ctrl_oe),
        .sdram_a(sd_a), .sdram_ba(sd_ba), .sdram_dqm(sd_dqm),
        .sdram_ncs(sd_ncs), .sdram_nras(sd_nras), .sdram_ncas(sd_ncas),
        .sdram_nwe(sd_nwe), .sdram_cke(sd_cke),
        .vga_rgb(rgb), .vga_hs(hs), .vga_vs(vs), .vga_hblank(hb), .vga_vblank(vb),
        .cpc_ce_pix(c_ce), .cpc_r(c_r), .cpc_g(c_g), .cpc_b(c_b), .cpc_hs(c_hs), .cpc_vs(c_vs),
        .cpc_hblank(), .cpc_vblank(),
        .loader_busy(busy), .loader_overflow(overflow), .loader_timeout(timeout),
        .sdram_refreshing(refreshing), .cpu_running(cpu_running), .cpu_halted(cpu_halted), .cpu_legacy(cpu_legacy)
    );

    sdram_model sdram (
        .clk(~clk_system), .cke(sd_cke), .ncs(sd_ncs), .nras(sd_nras), .ncas(sd_ncas),
        .nwe(sd_nwe), .ba(sd_ba), .a(sd_a), .dqm(sd_dqm),
        .dq_in(dq_ctrl), .dq_in_oe(dq_ctrl_oe),
        .dq_out(dq_sdram), .dq_out_oe(dq_sdram_oe)
    );

    // Byte del bus -> palabra del modelo (reparto de memory_arbiter + sdram_wishbone)
    // Posicion en el modelo de SDRAM (banco << 22 | fila << 9 | columna) de una
    // direccion de bytes del core, como la calcula memory_arbiter.sv
    function automatic int unsigned sdram_key(input logic [23:0] a);
`ifdef CALYPSO
        logic [22:0] c;
        case (a[23:22])
            2'd0: c = {2'b00,  a[20:0]};
            2'd1: c = {3'b010, a[19:0]};
            2'd3: c = {3'b011, a[19:0]};
            default: c = {1'b1, a[21:0]};
        endcase
        return (int'(c[22:21]) << 22) | (int'(c[13:2]) << 9) | int'({c[20:14], c[1]});
`else
        return (int'(a[23:22]) << 22) | (int'({1'b0, a[13:2]}) << 9) | int'({a[21:14], a[1]});
`endif
    endfunction

    function automatic logic [7:0] peek(input logic [23:0] a);
        int unsigned k = sdram_key(a);
        logic [15:0] w = sdram.mem.exists(k) ? sdram.mem[k] : 16'h0000;
        return a[0] ? w[15:8] : w[7:0];
    endfunction

    // +preload_dos=CARPETA: BIOS.SYS/BDOS.SYS ya en las paginas 8 y 9 y sus sumas
    // en el reloj (tools/dos_preload.py). El BOOTMENU no carga nada del disco.
    task automatic poke(input logic [23:0] a, input logic [7:0] v);
        int unsigned k = sdram_key(a);
        logic [15:0] w = sdram.mem.exists(k) ? sdram.mem[k] : 16'h0000;
        if (a[0]) w[15:8] = v; else w[7:0] = v;
        sdram.mem[k] = w;
    endtask
    logic [7:0] pre_buf [0:16383];
    initial begin
        string dir;
        int fd, n, r0, r1, r2, r3;
        if ($value$plusargs("preload_dos=%s", dir)) begin
            #150ms;
            for (int pg = 8; pg <= 9; pg++) begin
                fd = $fopen($sformatf("%s/preload_p%0d.bin", dir, pg), "rb");
                n = $fread(pre_buf, fd); $fclose(fd);
                for (int i = 0; i < 16384; i++) poke(24'(pg * 16384 + i), pre_buf[i]);
            end
            fd = $fopen({dir, "/preload_rtc.txt"}, "r");
            n = $fscanf(fd, "%h %h %h %h", r0, r1, r2, r3); $fclose(fd);
            if (!$test$plusargs("no_rtc_sums")) begin
                dut.rtc.ram[6'h3C] = 8'(r0); dut.rtc.ram[6'h3D] = 8'(r1);
                dut.rtc.ram[6'h3E] = 8'(r2); dut.rtc.ram[6'h3F] = 8'(r3);
            end
            $display("== MSX-DOS precargado (paginas 8 y 9, reloj 3C-3F = %02h %02h %02h %02h)", r0, r1, r2, r3);
        end
    end

    // +tape=fichero.cdt: se descarga por el indice 3 (Load tape) a los 300 ms
    logic [7:0] tape_file [0:(1 << 20) - 1];
    initial begin
        string f; int fd, n;
        logic [7:0] tbuf [];
        if ($value$plusargs("tape=%s", f)) begin
            fd = $fopen(f, "rb"); n = $fread(tape_file, fd); $fclose(fd);
            tbuf = new[n];
            foreach (tbuf[i]) tbuf[i] = tape_file[i];
            #300ms;
            $display("== Cinta: %s, %0d bytes (indice 3)", f, n);
            begin int g; if (!$value$plusargs("tape_gap=%d", g)) g = 60; download(6'd3, tbuf, g); end   // ritmo de bytes (60: unos 0,9 MB/s, como el firmware)
            $display("== Cinta descargada a los %0.1f ms", $realtime/1e6);
        end
    end
    // la entrada de cinta (PB7) y el motor (PC4)
    int tape_edges = 0; logic tape_d = 0, motor_d = 0;
    always @(posedge clk_bus) begin
        tape_d <= dut.tape_in; motor_d <= dut.ppi_pc_o[4];
        if (dut.tape_in != tape_d) tape_edges++;
        if (dut.ppi_pc_o[4] != motor_d) $display("== [%0.1f ms] motor de la cinta %s (flancos de cinta hasta ahora: %0d)",
                                                 $realtime/1e6, dut.ppi_pc_o[4] ? "ENCENDIDO" : "apagado", tape_edges);
    end

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


    // ---------------- Seguimiento -------------------------------------------
    realtime t_legacy = 0;
    always @(posedge clk_bus) if (cpu_running && cpu_legacy && t_legacy == 0) t_legacy = $realtime;

    int n_int = 0;
    logic ack_d = 0;
    always @(posedge clk_bus) begin
        ack_d <= dut.int_ack;
        if (dut.int_ack && !ack_d) n_int++;
    end

    // PC aproximado: direccion del ultimo M1
    logic [15:0] last_pc = 0;
    always @(posedge clk_bus) if (!dut.z80_sys.z80_m1_n && !dut.z80_sys.z80_mreq_n) last_pc <= dut.z80_sys.z80_a;

    int n_err = 0;
    // +trace_bus: el bus en torno al primer error de la CPU
    int bus_log = 0;
    always @(posedge clk_bus) if ($test$plusargs("trace_bus") && $realtime > 299.99e6 && bus_log < 400) begin
        if (dut.sys_cyc || dut.z80_cyc || dut.m2_cyc) begin
            bus_log++;
            $display("   [%0.4f ms] arb=%0d z80 cyc=%0d we=%0d adr=%06h ack=%0d err=%0d | m2 cyc=%0d own=%0d adr=%06h ack=%0d | sys cyc=%0d adr=%06h we=%0d ack=%0d err=%0d | vgrant=%0d",
                     $realtime/1e6, dut.sys_arbiter.current_state, dut.z80_cyc, dut.z80_we, dut.z80_adr, dut.z80_ack, dut.z80_err,
                     dut.m2_cyc, dut.m2_owner, dut.ld_adr, dut.m2_ack, dut.sys_cyc, dut.sys_adr, dut.sys_we, dut.sys_ack, dut.sys_err,
                     dut.vid_grant);
        end
    end
    always @(posedge clk_bus) if (dut.z80_cyc && dut.z80_stb && dut.z80_err) begin
        n_err++;
        if (n_err <= 5) $display("== [%0.3f ms] ERROR de bus del Z80: direccion %06h, we=%0d, PC=%04h",
                                 $realtime/1e6, dut.sys_adr, dut.sys_we, pc_last1);
    end
    // +trace_bus: ciclo a ciclo desde el primer acceso del segundo maestro
    int n_bt = -1;
    always @(posedge clk_bus) if ($test$plusargs("trace_bus")) begin
        if (n_bt < 0 && cyc_len == 20 && $realtime/1e6 > 200) n_bt = 0;
        if (n_bt >= 0 && n_bt < 160) begin
            n_bt++;
            $display("   bus %0d: arb=%0d m2(own=%0d cyc=%0d ack=%0d) z80req=%0d sys(cyc=%0d we=%0d adr=%06h) vid(cyc=%0d ack=%0d grant=%0d)",
                     n_bt, dut.sys_arbiter.current_state, dut.m2_owner, dut.m2_cyc, dut.m2_ack,
                     dut.z80_cyc & dut.z80_stb, dut.sys_cyc, dut.sys_we, dut.sys_adr, dut.vid_cyc, dut.vid_ack, dut.vid_grant);
        end
    end
    // +cpu_speed: velocidad efectiva del Z80 entre 500 y 600 ms (BASIC esperando)
    longint spd_cke = 0, spd_wait = 0;
    always @(posedge clk_bus) if ($test$plusargs("cpu_speed") && $realtime/1e6 >= 500 && $realtime/1e6 < 600) begin
        if (dut.z80_sys.z80_cke) begin
            spd_cke++;
            if (!dut.z80_sys.z80_wait_n) spd_wait++;
        end
    end
    final if ($test$plusargs("cpu_speed"))
        $display("== Velocidad del Z80 (500-600 ms): %0d ciclos de reloj, %0d en espera -> %.3f MHz efectivos",
                 spd_cke, spd_wait, real'(spd_cke - spd_wait) / 100000.0);
    // Errores del watchdog del bus (cualquier maestro): estado del arbitro, direccion
    int n_wdt = 0; int cyc_len = 0;
    always @(posedge clk_bus) begin
        cyc_len <= dut.sys_cyc ? cyc_len + 1 : 0;
        if (dut.sys_err && n_wdt < 6) begin
            n_wdt++;
            $display("== [%0.3f ms] WATCHDOG: arbitro=%0d (1 Z80, 2 segundo maestro), m2_owner=%0d, adr=%06h we=%0d, ciclo de %0d",
                     $realtime/1e6, dut.sys_arbiter.current_state, dut.m2_owner, dut.sys_adr, dut.sys_we, cyc_len);
        end
    end
    // +trace_dl: ventana de traza del bus desde el primer byte de la cinta
    int dl_win = -1; logic [31:0] dl_prev = '0;
    always @(posedge clk_bus) if ($test$plusargs("trace_dl")) begin
        automatic logic [31:0] s = {dut.sys_arbiter.current_state, dut.m2_owner, dut.ld_cyc, dut.ld_stb, dut.ld_ack,
                                    dut.z80_cyc, dut.z80_stb, dut.z80_ack, dut.sys_cyc, dut.vid_grant, dut.vid_ack,
                                    dut.tape_cyc, dut.ms_dma_cyc, dut.ld_we};
        if (dl_win < 0 && dut.ioctl_download && dut.ioctl_index[5:0] == 6'd3 && dut.ioctl_wr) dl_win = 0;
        if (dl_win >= 0 && dl_win < 400) begin
            dl_win++;
            if (s != dl_prev)
                $display("   c%0d arb=%0d own=%0d ld cyc/stb/ack=%b%b%b we=%b z80 cyc/stb/ack=%b%b%b sys_cyc=%b vid g/a=%b%b tape=%b ms=%b adr=%06h",
                         dl_win, dut.sys_arbiter.current_state, dut.m2_owner, dut.ld_cyc, dut.ld_stb, dut.ld_ack, dut.ld_we,
                         dut.z80_cyc, dut.z80_stb, dut.z80_ack, dut.sys_cyc, dut.vid_grant, dut.vid_ack,
                         dut.tape_cyc, dut.ms_dma_cyc, dut.sys_adr);
            dl_prev <= s;
        end
    end
    // +bus_from=ms: cada ciclo del bus del sistema desde ese instante (los 30 primeros)
    real bus_from = -1.0; int n_bus = 0; int blen = 0;
    initial void'($value$plusargs("bus_from=%f", bus_from));
    always @(posedge clk_bus) if (bus_from >= 0.0 && $realtime/1e6 >= bus_from) begin
        blen <= dut.sys_cyc ? blen + 1 : 0;
        if (dut.sys_cyc && (dut.sys_ack || dut.sys_err) && n_bus < 30) begin
            n_bus++;
            $display("   [%0.4f ms] bus: arbitro=%0d owner=%0d adr=%06h we=%0d %s tras %0d ciclos",
                     $realtime/1e6, dut.sys_arbiter.current_state, dut.m2_owner, dut.sys_adr, dut.sys_we,
                     dut.sys_err ? "ERROR" : "ack", blen);
        end
    end
    // +trace_dl: ciclos del bus al empezar una descarga
    int n_dl = -1;
    always @(posedge clk_bus) if ($test$plusargs("trace_dl")) begin
        if (n_dl < 0 && dut.ioctl_download && dut.ioctl_wr && dut.ioctl_index[5:0] == 6'd3) n_dl = 0;
        if (n_dl >= 0) n_dl++;
        if (n_dl >= 200 && n_dl < 340) begin
            $display("   dl%0d: arb=%0d z80req=%0d ldreq=%0d m2cyc=%0d sys_cyc=%0d adr=%06h we=%0d ack=%0d err=%0d vid_grant=%0d tape_cyc=%0d owner=%0d ms=%0d",
                     n_dl, dut.sys_arbiter.current_state, dut.z80_cyc & dut.z80_stb, dut.ld_req, dut.m2_cyc,
                     dut.sys_cyc, dut.sys_adr, dut.sys_we, dut.sys_ack, dut.sys_err, dut.vid_grant, dut.tape_cyc, dut.m2_owner, dut.ms_dma_cyc);
        end
    end
    // Foto del arbitro de memoria cuando un ciclo del bus lleva 100 ciclos esperando
    int n_snap = 0;
    always @(posedge clk_bus) if (cyc_len == 100 && n_snap < 3) begin
        n_snap++;
        $display("== [%0.3f ms] BLOQUEO: arb=%0d m2_owner=%0d adr=%06h we=%0d | mem_arbiter estado=%0d wb_enabled=%0d wb_stb=%0d ciclo=%0d",
                 $realtime/1e6, dut.sys_arbiter.current_state, dut.m2_owner, dut.sys_adr, dut.sys_we,
                 dut.video_controller.mem_arbiter.current_state, dut.video_controller.mem_arbiter.wb_enabled, dut.video_controller.mem_arbiter.wb_stb_i,
                 dut.video_controller.mem_arbiter.cycle);
    end
    // +trace_motor: escrituras a la PPI (puerto C y control) que cambian PC4, con el PC
    int n_mot = 0;
    real mot_from = 0.0;
    initial void'($value$plusargs("motor_from=%f", mot_from));
    always @(posedge clk_bus) if ($test$plusargs("trace_motor") && dut.ppi_ack && dut.sys_we && n_mot < 40 &&
                                  $realtime/1e6 >= mot_from &&
                                  ((dut.sys_adr[9:8] == 2'd2 && dut.sys_dat[4] != dut.ppi_pc_o[4]) ||
                                   (dut.sys_adr[9:8] == 2'd3 && (dut.sys_dat[7] || dut.sys_dat[3:1] == 3'd4)))) begin
        n_mot++;
        $display("   [%0.3f ms] PPI %s <- %02h (PC=%04h, interrupciones %s)", $realtime/1e6,
                 dut.sys_adr[9:8] == 2'd2 ? "puerto C" : "control ", dut.sys_dat, pc_last1,
                 dut.z80_sys.z80_inst.i_tv80_core.IntE_FF1 ? "SI" : "no");
    end

    // E/S del modo CPC: primeras escrituras, para ver por donde va el firmware
    int n_io = 0;
    always @(posedge clk_bus)
        if (dut.sys_cyc && dut.sys_stb && dut.vid_ack && dut.leg_io && n_io < 400 && $test$plusargs("trace_io")) begin
            n_io++;
            $display("   [%0.1f ms] %s %04h %02h", $realtime/1e6, dut.sys_we ? "OUT" : "IN ",
                     dut.sys_adr[15:0], dut.sys_we ? dut.sys_dat : dut.vid_dat_from_slave);
        end

    // Saltos del PC (M1 no secuenciales): +trace_pc
    int n_jmp = 0;
    // +trace_zero: cada vez que la CPU ejecuta la direccion 0 en modo CPC/Aleste
    int n_zero = 0;
    logic [15:0] zero_addr = 16'h0000;   // +zero_addr=0457 (hex)
    initial void'($value$plusargs("zero_addr=%h", zero_addr));
    logic [15:0] pc_last1 = 0, pc_last2 = 0;
    always @(posedge clk_bus)
        if (m1_d && !(dut.z80_sys.z80_m1_n | dut.z80_sys.z80_mreq_n) && cpu_legacy) begin
            if ($test$plusargs("trace_zero") && dut.z80_sys.z80_a[15:0] == zero_addr && n_zero < 6) begin
                n_zero++;
                $display("   [%0.3f ms] la CPU ejecuta %04h; antes: %04h, %04h; mapper %0d %0d %0d %0d",
                         $realtime/1e6, zero_addr, pc_last2, pc_last1, dut.z80_sys.mmu_legacy_inst.mapper_reg[0],
                         dut.z80_sys.mmu_legacy_inst.mapper_reg[1], dut.z80_sys.mmu_legacy_inst.mapper_reg[2],
                         dut.z80_sys.mmu_legacy_inst.mapper_reg[3]);
            end
            pc_last2 <= pc_last1; pc_last1 <= dut.z80_sys.z80_a[15:0];
        end
    // +pc_hist: cuantas veces se salta a cada destino dentro de la ventana
    int unsigned pc_hits [logic [15:0]];
    final if ($test$plusargs("pc_hist")) begin
        $display("== Destinos de salto en la ventana (direccion: veces):");
        foreach (pc_hits[a]) $display("   %04h: %0d", a, pc_hits[a]);
    end
    real pc_from = 0, pc_to = 1.0e9;      // ventana de la traza en ms: +pc_from= +pc_to=
    initial begin void'($value$plusargs("pc_from=%f", pc_from)); void'($value$plusargs("pc_to=%f", pc_to)); end
    logic [15:0] pc_prev = 16'h0000;
    logic m1_d = 1'b1;
    always @(posedge clk_bus) begin
        m1_d <= dut.z80_sys.z80_m1_n | dut.z80_sys.z80_mreq_n;
        if (m1_d && !(dut.z80_sys.z80_m1_n | dut.z80_sys.z80_mreq_n) && $test$plusargs("trace_pc")) begin
            if ((dut.z80_sys.z80_a[15:0] - pc_prev) > 16'd4 && n_jmp < 400 && cpu_legacy &&
                (pc_window || ($realtime >= pc_from * 1.0e6 && $realtime <= pc_to * 1.0e6))) begin
                if ($test$plusargs("pc_hist")) pc_hits[dut.z80_sys.z80_a[15:0]]++;
                else begin
                    n_jmp++;
                    $display("   [%0.2f ms] salto %04h -> %04h", $realtime/1e6, pc_prev, dut.z80_sys.z80_a[15:0]);
                end
            end
            pc_prev = dut.z80_sys.z80_a[15:0];
        end
    end

    // Primeras lecturas de memoria de la CPU tras el cambio de modo: +trace_rd
    int n_rd = 0;
    always @(posedge clk_bus)
        if ($test$plusargs("trace_rd") && n_rd < 50 && dut.z80_cyc && dut.z80_stb && dut.z80_ack && !dut.z80_we
            && $realtime > 27.0e6) begin
            n_rd++;
            $display("   [%0.4f ms] leg=%0d M1=%0d A=%04h fis=%06h dato=%02h", $realtime/1e6, dut.cfg_native ? 0 : 1,
                     !dut.z80_sys.z80_m1_n, dut.z80_sys.z80_a[15:0], dut.z80_adr, dut.z80_dat_in);
        end


    // Traza de los primeros accesos de la CPU (+trace_cpu=N)
    int n_tr = 0, max_tr = 0;
    initial if (!$value$plusargs("trace_cpu=%d", max_tr)) max_tr = 0;
    always @(posedge clk_bus)
        if (dut.z80_cyc && dut.z80_stb && (dut.z80_ack || dut.z80_err) && n_tr < max_tr && cpu_running) begin
            n_tr++;
            $display("   %5d cpu %s %06h %02h  Z80 A=%04h m1=%b leg=%b", n_tr, dut.z80_we ? "W" : "R", dut.z80_adr,
                     dut.z80_we ? dut.z80_dat_out : dut.z80_dat_in, dut.z80_sys.z80_a, dut.z80_sys.z80_m1_n, cpu_legacy);
        end

    // ---------------- Volcado de cuadros (salida de 15 kHz del Gate Array) ---
    // Se guarda el barrido entero (incluidos borde y sincronismos) a 16 MHz:
    // x desde el final del HSYNC, y desde el final del VSYNC.
    logic       c_ce, c_hs, c_vs;
    logic [7:0] c_r, c_g, c_b;
    bit dump_req = 0;
    // Zona visible para mist_video: pixeles por linea y lineas por cuadro
    int vis_px = 0, vis_px_line = 0, vis_lines = 0, vis_lines_frame = 0;
    logic hb_d = 1, vb_d = 1;
    always @(posedge clk_vid) if (dut.cpc_ce_pix) begin
        hb_d <= dut.cpc_hblank; vb_d <= dut.cpc_vblank;
        if (!dut.cpc_hblank && !dut.cpc_vblank) vis_px++;
        if (dut.cpc_hblank && !hb_d) begin if (vis_px) vis_px_line = vis_px; if (vis_px) vis_lines++; vis_px = 0; end
        if (dut.cpc_vblank && !vb_d) begin vis_lines_frame = vis_lines; vis_lines = 0; end
    end
    final $display("== Zona visible: %0d pixeles por linea, %0d lineas por cuadro", vis_px_line, vis_lines_frame);

    // ---- Tecleo: +type="texto" a los +type_ms (por defecto 1200 ms). Cada
    // tecla se mantiene 40 ms y se suelta 40 ms (el firmware lee el teclado
    // en cada interrupcion de cuadro). '~' = RETURN.
    function automatic logic [7:0] scancode(input byte c);
        case (c)
            "a": return 8'h1C; "b": return 8'h32; "c": return 8'h21; "d": return 8'h23; "e": return 8'h24;
            "f": return 8'h2B; "g": return 8'h34; "h": return 8'h33; "i": return 8'h43; "j": return 8'h3B;
            "k": return 8'h42; "l": return 8'h4B; "m": return 8'h3A; "n": return 8'h31; "o": return 8'h44;
            "p": return 8'h4D; "q": return 8'h15; "r": return 8'h2D; "s": return 8'h1B; "t": return 8'h2C;
            "u": return 8'h3C; "v": return 8'h2A; "w": return 8'h1D; "x": return 8'h22; "y": return 8'h35;
            "z": return 8'h1A; "0": return 8'h45; "1": return 8'h16; "2": return 8'h1E; "3": return 8'h26;
            "4": return 8'h25; "5": return 8'h2E; "6": return 8'h36; "7": return 8'h3D; "8": return 8'h3E;
            "9": return 8'h46; " ": return 8'h29; "_": return 8'h29; ",": return 8'h41; ".": return 8'h49; "~": return 8'h5A;
            default: return 8'h00;
        endcase
    endfunction
    task automatic key(input logic [7:0] code, input bit down);
        @(posedge clk_bus); k_code <= code; k_pressed <= down; k_strobe <= 1;
        @(posedge clk_bus); k_strobe <= 0;
    endtask
    string to_type;
    int type_ms;
    realtime t_typed = 0;
    initial begin
        if ($value$plusargs("type=%s", to_type)) begin
            if (!$value$plusargs("type_ms=%d", type_ms)) type_ms = 1200;   // antes el firmware descarta teclas
            #(type_ms * 1ms);
            $display("== Tecleando \"%s\"", to_type);
            for (int i = 0; i < to_type.len(); i++) begin
                if (to_type[i] == "%") begin           // '%' = pausa de 500 ms
                    #500ms;
                end else if (to_type[i] == "#" || to_type[i] == "|") begin   // '#' = comillas (Mayus+2), '|' = Mayus+@
                    automatic logic [7:0] k = (to_type[i] == "#") ? 8'h1E : 8'h54;
                    key(8'h12, 1); key(k, 1); #40ms;
                    key(k, 0); key(8'h12, 0); #40ms;
                end else begin
                    key(scancode(to_type[i]), 1); #40ms;
                    key(scancode(to_type[i]), 0); #40ms;
                end
            end
            t_typed = $realtime;
        end
    end

    // ---- Audio: flancos de subida del canal izquierdo en ventanas de 100 ms
    int aud_edges = 0, aud_hz = 0;
    logic [15:0] aud_d = 0;
    always @(posedge clk_bus) begin
        aud_d <= aud_l;
        if (aud_l > aud_d + 16'd256) aud_edges++;
    end
    always begin
        #100ms;
        aud_hz = aud_edges * 10;
        aud_edges = 0;
    end
    // Lecturas de video que no llegan antes del final de su caracter
    int late = 0, fetches = 0;
    always @(posedge clk_vid) if (dut.cpc_vid.cclk && dut.cpu_legacy) begin
        fetches++;
        if (dut.cpc_vid.d_sync_v[1] != dut.cpc_vid.f_tog) late++;
    end
    int n_dump = 0;
    int cx = 0, cy = 0, lines_frame = 0, n_frames = 0, line_px = 0;
    logic c_hs_d = 0, c_vs_d = 0;
    logic [23:0] fb [0:1023][0:319];
    bit capturing = 0;
    task automatic write_frame(input string name);
        int fd = $fopen(name, "wb");
        $fwrite(fd, "P6\n1024 320\n255\n");
        for (int y = 0; y < 320; y++) for (int x = 0; x < 1024; x++)
            $fwrite(fd, "%c%c%c", fb[x][y][23:16], fb[x][y][15:8], fb[x][y][7:0]);
        $fclose(fd);
    endtask
    always @(posedge clk_vid) if (c_ce) begin
        c_hs_d <= c_hs; c_vs_d <= c_vs;
        if (c_hs_d && !c_hs) begin line_px = cx; cx = 0; cy++; end
        else cx++;
        if (c_vs_d && !c_vs) begin
            lines_frame = cy; cy = 0; n_frames++;
            if (capturing) begin capturing = 0; write_frame($sformatf("cpc_%02d.ppm", n_dump++)); end
            if (dump_req) begin dump_req = 0; capturing = 1; foreach (fb[x, y]) fb[x][y] = 24'h404040; end
        end
        if (capturing && cx < 1024 && cy < 320) fb[cx][cy] = {c_r, c_g, c_b};
    end

    logic [7:0] fbuf [0:(1<<18)-1];
    int fails = 0;
    int wr_slot[4] = '{0, 0, 0, 0};
    int push_hi = 0;
    logic [23:0] first_hi = 24'hFFFFFF;
    always @(posedge clk_bus) begin
        if (dut.ld_cyc && dut.ld_stb && dut.ld_ack && dut.ld_we) wr_slot[dut.ld_adr[23:22]]++;
        if (dut.loader.push && dut.loader.push_data[31:30] == 2'b01) begin
            push_hi++;
            if (first_hi == 24'hFFFFFF) first_hi = dut.loader.push_data[31:8];
        end
    end

    initial begin
        string romf;
        int fd, n, total_ms, step_ms;
        logic [7:0] rom[];
        if (!$value$plusargs("rom=%s", romf)) romf = "ALESTE_CPC.ROM";
        if (!$value$plusargs("ms=%d", total_ms)) total_ms = 1000;
        if (!$value$plusargs("step=%d", step_ms)) step_ms = 100;
        fd = $fopen(romf, "rb");
        if (fd == 0) begin $display("No encuentro %s", romf); $finish; end
        n = $fread(fbuf, fd); $fclose(fd);
        rom = new[n]; foreach (rom[i]) rom[i] = fbuf[i];

        wait (pll_locked); #205us;
        $display("== Cargando %s (%0d bytes) por el indice 0", romf, n);
        download(6'd0, rom, 18);      // ritmo del SPI del firmware: 24 MHz / 8 bits = 1 byte cada 18 ciclos de 54 MHz
        wait (cpu_running);
        $display("== CPU en marcha a los %0.1f ms", $realtime/1e6);
        if (peek(24'h400000) != rom[32'h4000] || peek(24'h40FFFF) != rom[32'h13FFF] || peek(24'hC03FFE) != 8'hD3)
            begin $display("FALLO: la ROM no esta donde toca: 400000=%02h (esperado %02h) 40FFFF=%02h (%02h) C03FFE=%02h (D3) C00000=%02h (%02h)",
                           peek(24'h400000), rom[32'h4000], peek(24'h40FFFF), rom[32'h13FFF], peek(24'hC03FFE), peek(24'hC00000), rom[0]); fails++; end

        $display("   escrituras del cargador por slot: 0=%0d 1=%0d 2=%0d 3=%0d; entradas a la FIFO para el slot 1: %0d (primera %06h)",
                 wr_slot[0], wr_slot[1], wr_slot[2], wr_slot[3], push_hi, first_hi);
        if ($test$plusargs("find_rom"))
            for (int b = 0; b < 1024; b++) begin
                logic [23:0] a = 24'(b) << 14;
                if (peek(a) == rom[32'h4000] && peek(a + 1) == rom[32'h4001] && peek(a + 2) == rom[32'h4002])
                    $display("   AL512 pagina 0 encontrada en %06h", a);
                if (peek(a) == rom[32'h8000] && peek(a + 1) == rom[32'h8001] && peek(a + 2) == rom[32'h8002] && peek(a + 3) == rom[32'h8003])
                    $display("   AL512 pagina 1 encontrada en %06h", a);
            end
        for (int t = step_ms; t <= total_ms; t += step_ms) begin
            #(step_ms * 1ms);
            dump_req = 1;
            $display("== %4d ms: modo CPC=%0d PC=%04h interrupciones=%0d cuadros=%0d (%0d lineas, %0d px/linea) modo GA=%0d CRTC R12/R13=%02h%02h errores de bus=%0d",
                     t, cpu_legacy, last_pc, n_int, n_frames, lines_frame, line_px, dut.cpc_vid.mode,
                     dut.cpc_vid.crtc.R12_start_addr_h, dut.cpc_vid.crtc.R13_start_addr_l, n_err);
            if (sd_reads) $display("          disco: MSR=%02h estado=%0d motor=%0d bloques=%0d INT=%0d",
                                   dut.fdc.m_status, dut.fdc.fdc.state, dut.fdc_motor, sd_reads, dut.fdc_int);
            $fflush;
            $fflush();
        end
        #45ms;                          // da tiempo a guardar el ultimo cuadro pedido
        if (!cpu_legacy) begin $display("FALLO: la CPU no ha pasado a modo CPC"); fails++; end
        else $display("== Paso a modo CPC a los %0.2f ms", t_legacy/1e6);
        if (n_int == 0) begin $display("FALLO: no hay interrupciones"); fails++; end
        $display("== Lecturas de video: %0d, tarde: %0d", fetches, late);
        if (sd_reads) $display("== Disco: %0d bloques leidos de la SD, motor=%0d", sd_reads, dut.fdc_motor);
        if (t_typed > 0) begin
            $display("== Audio en los ultimos 100 ms: %0d Hz (AY: periodo canal A=%0d, volumen A=%0d, mezclador R7=%02h)",
                     aud_hz, {dut.psg.ymreg[1][3:0], dut.psg.ymreg[0]}, dut.psg.ymreg[8], dut.psg.ymreg[7]);
            // +expect_hz=N: frecuencia esperada del canal A (margen +-5 %)
            begin
                int exp_hz;
                if ($value$plusargs("expect_hz=%d", exp_hz) &&
                    (aud_hz < exp_hz * 95 / 100 || aud_hz > exp_hz * 105 / 100)) begin
                    $display("FALLO: audio a %0d Hz, esperado %0d", aud_hz, exp_hz); fails++;
                end
            end
        end
        if (late > 1) begin $display("FALLO: lecturas de video tarde"); fails++; end
        if (dut.loader_overflow) begin $display("FALLO: la FIFO del cargador se ha desbordado"); fails++; end
        if (sdram.errors) fails++;
        if (fails == 0) $display("RESULTADO: OK (ver cpc_*.ppm)");
        else            $display("RESULTADO: %0d FALLOS", fails);
        $finish;
    end
endmodule
