// ============================================================================
// aleste_core.sv - Nucleo del Aleste LX para placas MiST, sin nada de placa
//
// Todo lo que no depende de la placa ni del firmware: cargador, bus,
// controlador de video y SDRAM. El top (aleste_mist_top.sv) pone el PLL,
// user_io/data_io, el OSD, los pines y el reloj de la SDRAM. Asi el banco de
// pruebas (sim/) simula exactamente esto con un modelo de SDRAM.
//
// FASE 2: Z80 (tv80) con la MMU nativa del Aleste LX. Como el aleste_system
// del original, pero con el cargador de la SD en lugar del puente UART:
//
//   z80_system (Z80 + MMU) --+
//                            +-- system_arbiter --> video_ctrl_vga --> SDRAM
//   mist_loader (data_io) ---+         ^              (CRTC, paleta,
//                                 wb_wdt_simple        memoria)
//
// La CPU arranca en 0xC00000 (slot 3, banco 0 tras el reset de la MMU), que
// es donde el cargador pone la ROM (indice 0). Se queda en reset hasta que
// se ha cargado una ROM y mientras se carga otra; asi, sin ALESTE.ROM en la
// SD, el core se comporta como en la fase 1.
// ============================================================================
`default_nettype none

module aleste_core #(
    // Ciclos por ms de cada unidad del 765 (ver la disquetera). Solo la
    // simulacion lo cambia, para que el disco gire mas deprisa.
    parameter logic [19:0] FDC_CYCLES = 20'd3857
) (
    input  logic        clk_system,     // 108 MHz
    input  logic        clk_bus,        //  54 MHz
    input  logic        clk_pixel,      //  27 MHz
    input  logic        clk_vid,        //  80 MHz (video del modo CPC, PLL propio)
    input  logic        pll_locked,
    input  logic        user_reset,     // menu o boton (dominio clk_bus)
    input  logic [1:0]  boot_mode,      // OSD CPC boot: 0 Aleste 520EX, 1 AMSTRAD (SHIFT), 2 Aleste BIOS (BS -> SETUP)
    input  logic        key_strobe,     // teclado PS/2 de user_io (clk_bus)
    input  logic        key_pressed,
    input  logic        key_extended,
    input  logic [7:0]  key_code,
    input  logic [7:0]  joystick,       // joystick 1 de MiST
    input  logic        audio_stereo,   // 0 mono, 1 estereo ABC

    // data_io
    input  logic        ioctl_download,
    input  logic [7:0]  ioctl_index,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [7:0]  ioctl_dout,

    // SDRAM (el tri-estado y el reloj los pone el top)
    input  logic [15:0] sdram_dq_i,
    output logic [15:0] sdram_dq_o,
    output logic        sdram_dq_oe,
    output logic [12:0] sdram_a,
    output logic [1:0]  sdram_ba,
    output logic [1:0]  sdram_dqm,
    output logic        sdram_ncs,
    output logic        sdram_nras,
    output logic        sdram_ncas,
    output logic        sdram_nwe,
    output logic        sdram_cke,

    // Video, en clk_pixel: 720x480, 59,94 Hz
    output logic [11:0] vga_rgb,
    output logic        vga_hs,
    output logic        vga_vs,
    output logic        vga_hblank,
    output logic        vga_vblank,

    // Video del modo CPC, en clk_vid, a 15 kHz (temporizacion del CRTC)
    output logic        cpc_ce_pix,
    output logic [7:0]  cpc_r,
    output logic [7:0]  cpc_g,
    output logic [7:0]  cpc_b,
    output logic        cpc_hs,
    output logic        cpc_vs,
    output logic        cpc_hires,      // alta resolucion del 520EX (dominio clk_vid)
    output logic        cpc_hblank,
    output logic        cpc_vblank,

    // Audio del AY (clk_bus), 16 bits con signo
    output logic [15:0] audio_l,
    output logic [15:0] audio_r,

    // Disquetera: SD del firmware MiST (user_io), dos unidades (clk_bus)
    input  logic        fdc_fast,       // busqueda y lectura inmediatas
    input  logic        fdc_one_drive,  // solo la unidad A (OSD); si no, A y B
    input  logic [8:0]  mouse_x,        // raton PS/2 de user_io (para el raton serie del 520EX)
    input  logic [8:0]  mouse_y,
    input  logic [7:0]  mouse_flags,
    input  logic        mouse_strobe,
    input  logic [63:0] mist_rtc,       // hora del firmware de MiST (user_io), si la placa tiene reloj
    input  logic        cpc_mouse_en,   // OSD: ratones de CPC (Kempston, SYMBiFACE II, Multiplay)
    input  logic        amx_mouse_en,   // OSD: raton AMX por el joystick 1
    input  logic [1:0]  cpu_turbo,      // OSD: velocidad del Z80 (0 4 MHz, 1 8 MHz, 2 16 MHz)
    input  logic [2:0]  video_h_off,    // OSD: centrado horizontal de la imagen CPC
    input  logic [2:0]  video_v_off,    // OSD: centrado vertical
    input  logic        tape_sound,     // OSD: se oye la cinta mientras se reproduce
    input  logic        tape_invert,    // OSD: invertir la entrada de cinta
    input  logic        tape_ext,       // entrada de cinta de la placa (AUDIO_IN), asincrona
    input  logic        test_tone,      // OSD: tono de prueba de 1 kHz
    input  logic [2:0]  img_mounted,    // 0 A:, 1 B:, 2 ALESTE.CMO (RAM del reloj)
    input  logic        img_wp,
    input  logic [31:0] img_size,
    output logic [31:0] sd_lba,
    output logic [2:0]  sd_rd,
    output logic [2:0]  sd_wr,
    input  logic        sd_ack,
    input  logic [8:0]  sd_buff_addr,
    input  logic [7:0]  sd_buff_dout,
    output logic [7:0]  sd_buff_din,
    input  logic        sd_buff_wr,

    // Estado
    output logic        loader_busy,
    output logic        loader_overflow,
    output logic        loader_timeout,
    output logic        sdram_refreshing,
    output logic        cpu_running,
    output logic        cpu_halted,
    output logic        cpu_legacy      // la CPU esta en modo CPC (MMU legacy)
);

// ============================================================================
// Resets
// ============================================================================
// Sistema de video (CRTC, paleta, arbitros, cargador): PLL o menu.
// La SDRAM solo con el PLL: si se reiniciara desde el menu con una carga en
// marcha, lo cargado se perderia a medias.
logic system_reset;
logic res_key;                        // tecla RES del 520EX (Bloq Despl)
logic [6:0] amx_dout;                 // raton AMX (al joystick 1)
reset_controller reset_ctrl (
    .clk_i(clk_system),
    .pll_locked_i(pll_locked),
    // El reset del menu o del boton no actua mientras se descarga una ROM: en
    // el primer arranque el firmware puede enviar ALESTE.ROM con el reset del
    // OSD activo, y el cargador y el camino a la SDRAM la perdian (la CPU
    // arrancaba sin ROM; recargando el core a mano ya funcionaba).
    .rst_i((user_reset | res_key) & ~ioctl_download & ~loader_busy),   // RES: Bloq Despl
    .rst_o(system_reset),
    .eof_rst_o()
);

logic [1:0] mem_reset_sync = 2'b11;
always_ff @(posedge clk_system) mem_reset_sync <= {mem_reset_sync[0], ~pll_locked};
wire mem_reset = mem_reset_sync[1];

// ============================================================================
// CPU en reset hasta tener ROM
// ============================================================================
// rom_ready solo se borra al encender (mem_reset) o al empezar a cargar otra
// ROM: un reset desde el menu reinicia la CPU con la ROM que ya hay.
logic rom_ready, rom_loading, cpu_reset;
logic [7:0] extport;                  // EXTEND PORT del 520EX (FABF)
logic       ms_nmi;                   // MagicSound: NMI al acabar un bloque de DMA
logic       rtc_set;                  // poner el reloj en hora con la de MiST
logic       tape_in;                  // entrada de cinta (PB7 de la PPI)
logic       tape_read, tape_running;  // reproductor de cintas
logic       tape_motor;               // motor de la cinta (PC4 de la PPI, con inercia)
logic       tape_src;                 // cinta: fichero CDT/TZX o entrada de la placa
logic       cmos_we, cmos_clean, rtc_dirty;   // ALESTE.CMO (RAM del reloj en la SD)
logic [5:0] cmos_addr;
logic [7:0] cmos_din, cmos_dout;
logic [7:0] rtc_dout;                 // reloj MC146818
logic       rtc_drive;

always_ff @(posedge clk_bus) begin
    if (mem_reset) begin
        rom_ready   <= 1'b0;
        rom_loading <= 1'b0;
    end else if (ioctl_download && ioctl_index[5:0] == 6'd0) begin
        rom_loading <= 1'b1;
        rom_ready   <= 1'b0;
    end else if (rom_loading && !loader_busy) begin
        rom_loading <= 1'b0;                    // FIFO vacia: la ROM entera esta en SDRAM
        rom_ready   <= ~loader_overflow;        // con datos perdidos la CPU no arranca (LED rapido)
    end
end

// Registrado: z80_system usa el reset como asincrono
always_ff @(posedge clk_bus)
    cpu_reset <= system_reset | ~rom_ready | rom_loading;

assign cpu_running = ~cpu_reset;

// ============================================================================
// Z80 + MMU (z80_system del Aleste LX). El bus de depuracion queda sin usar.
// ============================================================================
logic        z80_cyc, z80_stb, z80_we, z80_ack, z80_err;
logic [23:0] z80_adr;
logic [7:0]  z80_dat_out, z80_dat_in;
logic        cfg_native;
logic        cpc_int, int_ack;
logic [1:0]  cpc_mode;
logic        z80_halt;

z80_system z80_sys (
    .clk_i(clk_bus),
    .res_i(cpu_reset),
    .res_short_i(mem_reset),

    .wbm_adr_o(z80_adr),
    .wbm_dat_i(z80_dat_in),
    .wbm_dat_o(z80_dat_out),
    .wbm_cyc_o(z80_cyc),
    .wbm_stb_o(z80_stb),
    .wbm_we_o(z80_we),
    .wbm_ack_i(z80_ack),
    .wbm_err_i(z80_err),

    .dbg_adr_i(8'h00),
    .dbg_dat_o(),
    .dbg_dat_i(8'h00),
    .dbg_cyc_i(1'b0),
    .dbg_stb_i(1'b0),
    .dbg_we_i(1'b0),
    .dbg_cs_i(1'b0),
    .dbg_ack_o(),

    .nmi_req_i(ms_nmi),                 // MagicSound: fin de bloque de DMA
    .int_req_i(cpc_int),
    .mapmod_i(extport[2]),
    .cpu_4mhz_i(~cfg_native),     // modo CPC: Z80 a 4 MHz, como el 520EX
    .cpu_turbo_i(cpu_turbo),      // OSD: 4 / 8 (turbo del 520EX) / 16 MHz
    .int_ack_o(int_ack),
    .system_status_i(8'h00),

    .graphic_mode(cpc_mode),
    .irq_control(),
    .supervisor_mode_o(),
    .native_mode_o(cfg_native),

    .debug_z80_reset_o(),
    .debug_z80_halt_o(z80_halt),
    .debug_reg_control_o(),
    .debug_reg_mmio_page_o(),
    .debug_z80_bus_o()
);

assign cpu_halted = z80_halt & ~cpu_reset;

// ============================================================================
// Cargador: data_io -> FIFO -> maestro Wishbone (en el puerto del puente UART)
// ============================================================================
logic        ld_cyc, ld_stb, ld_we, ld_ack, ld_err;   // cargador de la SD
logic [23:0] ld_adr;
logic [7:0]  ld_dat_out;

// Segundo maestro del bus (puerto del antiguo puente UART), compartido entre
// el cargador de la SD y la DMA de la MagicSound. El dueno solo cambia cuando
// el actual no tiene ciclo en curso; el cargador tiene prioridad.
logic        ms_dma_cyc;
logic [23:0] ms_dma_adr;
logic signed [15:0] ms_out_l, ms_out_r;
logic [1:0]  m2_owner;                  // 0 cargador, 1 MagicSound, 2 cinta
logic        m2_ack, m2_err;
logic [7:0]  m2_dat;
logic        tape_cyc;                  // lector de la cinta (ver mas abajo)
logic [23:0] tape_adr;
wire ld_req = ld_cyc & ld_stb;
wire m2_busy = (m2_owner == 2'd0) ? ld_req : (m2_owner == 2'd1) ? ms_dma_cyc : tape_cyc;
always_ff @(posedge clk_bus) begin
    if (system_reset) m2_owner <= 2'd0;
    else if (!m2_busy) m2_owner <= ld_req ? 2'd0 : ms_dma_cyc ? 2'd1 : tape_cyc ? 2'd2 : 2'd0;
end
wire m2_cyc = m2_busy;
assign ld_ack = m2_ack & (m2_owner == 2'd0);
assign ld_err = m2_err & (m2_owner == 2'd0);

mist_loader loader (
    .clk(clk_bus),
    .rst(system_reset),
    .ioctl_download(ioctl_download),
    .ioctl_index(ioctl_index),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .wb_cyc_o(ld_cyc),
    .wb_stb_o(ld_stb),
    .wb_we_o(ld_we),
    .wb_adr_o(ld_adr),
    .wb_dat_o(ld_dat_out),
    .wb_ack_i(ld_ack),
    .wb_err_i(ld_err),
    .busy_o(loader_busy),
    .overflow_o(loader_overflow),
    .timeout_o(loader_timeout)
);

// ============================================================================
// Arbitro del bus de sistema (Aleste LX): Z80 con prioridad sobre el cargador
// ============================================================================
logic        sys_cyc, sys_stb, sys_we, sys_ack, sys_err;
logic [23:0] sys_adr;
logic [7:0]  sys_dat;
logic        vid_cyc, vid_stb, vid_we, vid_ack, vid_grant;
logic [23:0] vid_adr;
logic [7:0]  vid_dat_to_slave, vid_dat_from_slave;

system_arbiter sys_arbiter (
    .clk_i(clk_bus),
    .rst_i(system_reset),

    .sys_cyc_o(sys_cyc),
    .sys_stb_o(sys_stb),
    .sys_we_o(sys_we),
    .sys_ack_o(sys_ack),
    .sys_adr_o(sys_adr),
    .sys_dat_o(sys_dat),
    .sys_err_i(sys_err),

    .z80_cyc_i(z80_cyc),
    .z80_stb_i(z80_stb),
    .z80_we_i(z80_we),
    .z80_adr_i(z80_adr),
    .z80_dat_i(z80_dat_out),
    .z80_dat_o(z80_dat_in),
    .z80_ack_o(z80_ack),
    .z80_grant_o(),
    .z80_err_o(z80_err),

    .uart_cyc_i(m2_cyc),
    .uart_stb_i(m2_cyc),
    .uart_we_i((m2_owner == 2'd0) ? ld_we : 1'b0),
    .uart_adr_i((m2_owner == 2'd0) ? ld_adr : (m2_owner == 2'd1) ? ms_dma_adr : tape_adr),
    .uart_dat_i(ld_dat_out),
    .uart_dat_o(m2_dat),
    .uart_ack_o(m2_ack),
    .uart_grant_o(),
    .uart_err_o(m2_err),

    .vid_cyc_o(vid_cyc),
    .vid_stb_o(vid_stb),
    .vid_we_o(vid_we),
    .vid_adr_o(vid_adr),
    .vid_dat_o(vid_dat_to_slave),
    .vid_dat_i(vid_dat_from_slave),
    .vid_ack_i(vid_ack),
    .vid_grant_i(vid_grant),

    .debug_state_o(),
    .debug_z80_active_o(),
    .debug_uart_active_o()
);

// Watchdog: un acceso que nadie contesta termina en error en vez de colgar la
// CPU. Los puertos sin dispositivo del modo CPC ya contestan al momento (FF), asi
// que solo cubre fallos; 1024 ciclos (19 us) dejan margen a un acceso que espera
// detras del video y de un tren de escrituras del cargador (con 128 se cortaban
// lecturas de la ROM al empezar una descarga rapida, p. ej. una cinta).
wb_wdt_simple #(
    .TIMEOUT_CYCLES(1024)
) sys_wdt (
    .clk_i(clk_bus),
    .rst_i(system_reset),
    .cyc_i(sys_cyc),
    .stb_i(sys_stb),
    .ack_i(sys_ack),
    .err_o(sys_err)
);

// ============================================================================
// Decodificador de direcciones y controlador de video (del Aleste LX)
// ============================================================================
logic [7:0] cs_native, cs_system, cs_legacy;
logic [2:0] sys_tag;

address_decoder adu (
    .cfg_native_i(cfg_native),
    .wb_adr_i(sys_adr),
    .wb_tag_o(sys_tag),
    .cs_native_o(cs_native),
    .cs_system_o(cs_system),
    .cs_legacy_o(cs_legacy)
);


// ============================================================================
// Dispositivos del modo CPC (fase 3). Solo responden con la MMU en modo
// legacy, en el espacio de E/S CPC que la MMU pone en FF4000-FFFFFF.
// ============================================================================
logic [7:0] vc_dat;
logic       vc_ack, vc_grant;
logic       crtc_hs, crtc_vs;

wire legacy  = ~cfg_native;
wire leg_io  = legacy & sys_tag[2];
wire bus_req = sys_cyc & sys_stb;
logic fdc_int;                  // INT de la disquetera (PB1 de la PPI)
assign cpu_legacy = legacy & ~cpu_reset;

// ---- Gate Array: RMR/MMR (7Fxx con D7=1). Los registros estan en la MMU
// legacy; aqui solo se reconoce el ciclo para no esperar al watchdog.
// (Las escrituras de pen/color, D7=0, van al video CPC, rtl/cpc/cpc_video.sv.)
// Gate Array del 520EX: decodificado solo con A15 (CPCWiki); 7Cxx-7Fxx con
// D7..6=11 es tambien el mapper MSX (con MAPMOD), que atiende la MMU legacy.
wire ga_cfg = leg_io & ~sys_adr[15] & sys_we & sys_dat[7];
logic ga_ack;
always_ff @(posedge clk_bus) ga_ack <= bus_req & ga_cfg & ~ga_ack;

// Lectura del mapper (520EX: se puede leer). La BIOS de MSX-DOS guarda los
// cuatro registros leyendo 7C-7F y luego los restaura escribiendo lo leido,
// asi que la lectura devuelve el mismo formato que se escribe: C0 | pagina.
// (Sin esto se leia FF, la BIOS restauraba "pagina 63" en C000-FFFF, perdia
// su pila y sus ganchos y volvia a empezar: pantalla en negro.)
wire ga_rd = leg_io & ~sys_adr[15] & ~sys_we;
logic [5:0] map_shadow [0:3];
logic       ga_rd_ack;
always_ff @(posedge clk_bus) begin
    ga_rd_ack <= bus_req & ga_rd & ~ga_rd_ack;
    if (cpu_reset) begin
        map_shadow[0] <= 6'd0; map_shadow[1] <= 6'd1; map_shadow[2] <= 6'd2; map_shadow[3] <= 6'd3;
    end else if (bus_req & ga_cfg & ~ga_ack & (sys_dat[7:6] == 2'b11) & extport[2])
        map_shadow[sys_adr[9:8]] <= sys_dat[5:0];
end
wire [7:0] ga_rd_dat = extport[2] ? {2'b11, map_shadow[sys_adr[9:8]]} : 8'hFF;

// ---- Video CPC con temporizacion real (CRTC libre, Gate Array, 15 kHz)
wire crtc_cs = leg_io & ~sys_adr[14];                                   // BCxx-BFxx
wire ga_pen  = leg_io & ~sys_adr[15] & ~sys_dat[7] & sys_we;  // tinta / borde
logic [7:0]  cv_dat;
logic        cv_ack;
logic [15:0] cpc_mem_addr, cpc_mem_data;
logic        cpc_mem_req, cpc_mem_ack0;

logic [1:0] rst_v_s = 2'b11;
always_ff @(posedge clk_vid) rst_v_s <= {rst_v_s[0], system_reset};
logic [1:0] leg_m_s;
always_ff @(posedge clk_system) leg_m_s <= {leg_m_s[0], legacy};
wire leg_m = leg_m_s[1];

cpc_video cpc_vid (
    .clk_v(clk_vid),
    .rst_v(rst_v_s[1]),
    .clk_b(clk_bus),
    .rst_b(system_reset),
    .bus_crtc(bus_req & crtc_cs),
    .bus_ga(bus_req & ga_pen),
    .bus_we(sys_we),
    .bus_rs(sys_adr[8]),
    .bus_dat_i(sys_dat),
    .bus_dat_o(cv_dat),
    .bus_ack(cv_ack),
    .mode_i(cpc_mode),
    .extport_i(extport),
    .clk_m(clk_system),
    .rst_m(system_reset),
    .mem_en(leg_m),
    .mem_addr(cpc_mem_addr),
    .mem_req(cpc_mem_req),
    .mem_ack0(cpc_mem_ack0),
    .mem_data(cpc_mem_data),
    .ce_pix(cpc_ce_pix),
    .r(cpc_r), .g(cpc_g), .b(cpc_b),
    .hs(cpc_hs), .vs(cpc_vs),
    .hblank(cpc_hblank), .vblank(cpc_vblank),
    .crtc_hs(crtc_hs),
    .crtc_vs(crtc_vs),
    .h_off(video_h_off),
    .hires_o(cpc_hires),
    .v_off(video_v_off)
);

// ---- Sincronismos del CRTC al dominio del bus
logic [2:0] hs_s, vs_s;
always_ff @(posedge clk_bus) begin
    hs_s <= {hs_s[1:0], crtc_hs};
    vs_s <= {vs_s[1:0], crtc_vs};
end
wire hs_end   = hs_s[2] & ~hs_s[1];     // fin del HSYNC (como el Gate Array)
wire vs_start = ~vs_s[2] & vs_s[1];

// ---- PPI 8255 (F4xx-F7xx: A11=0, registro en A9..A8)
wire ppi_cs = leg_io & ~sys_adr[11];
logic [7:0] ppi_dat, ppi_pa_o, ppi_pc_o, psg_to_ppi;
logic       ppi_ack;

i8255_wb ppi (
    .clk_i(clk_bus),
    .rst_i(system_reset),
    .cs_i(ppi_cs),
    .adr_i(sys_adr[9:8]),
    .dat_i(sys_dat),
    .dat_o(ppi_dat),
    .we_i(sys_we),
    .stb_i(bus_req),
    .ack_o(ppi_ack),
    .ipa_i(rtc_drive ? rtc_dout : psg_to_ppi),   // puerto A: AY o reloj (FABF D5)
    .opa_o(ppi_pa_o),
    // PB: 7 cassette, 6 BUSY impresora (0 = lista), 5 /EXP, 4 50 Hz,
    //     3..1 marca (111 = Amstrad), 0 VSYNC
    // 520EX (CPCWiki, Aleste 520EX - I/O Ports): /EXP (PB5) va a masa
    // PB1 = DISKINT: la INT de la disquetera, ACTIVA A 1. El BOOTMENU espera
    // el fin de una busqueda con BIT 1 / JR Z ("Wait for seek end"); CPCWiki
    // la llama /DISCINT, pero la polaridad buena es esta.
    .ipb_i({tape_in, 1'b0, 1'b0, 1'b1, 2'b11, fdc_int, vs_s[1]}),   // PB7 = entrada de cinta
    .opb_o(),
    .ipc_i(8'hFF),
    .opc_o(ppi_pc_o)
);

// ---- AY-3-8910 (YM2149 de MikeJ/Sorgelig, del Aleste LX) y teclado del
// 520EX. Como en el CPC: BDIR = PC7, BC1 = PC6, dato por el puerto A de la
// PPI; la fila del teclado (PC3..PC0) entra por el puerto A del AY.
// Reloj del AY: 1 MHz (54 MHz / 54).
logic [5:0] psg_div;
logic       psg_ce;
always_ff @(posedge clk_bus) begin
    psg_ce <= 1'b0;
    if (psg_div == 6'd53) begin psg_div <= '0; psg_ce <= 1'b1; end
    else psg_div <= psg_div + 6'd1;
end

// SHIFT pulsado al arrancar si se pide, para que el SETUP del 520EX (ROM 3)
// arranque en modo AMSTRAD en vez de MSX-DOS. El SETUP lo mira durante la
// inicializacion de las ROM: se mantiene 2,5 s (con la CPU a 4 MHz, como la
// original, BASIC tarda mas de 1 s) y se suelta antes si se pulsa una tecla
// de verdad (si no, lo que se escribiera saldria con SHIFT).
logic [27:0] boot_timer;
logic        boot_key;
always_ff @(posedge clk_bus) begin
    if (cpu_reset) begin
        boot_timer <= '0;
        boot_key   <= 1'b0;
    end else begin
        if (boot_timer != 28'd135_000_000) boot_timer <= boot_timer + 28'd1;   // 2,5 s a 54 MHz
        if (key_strobe && key_pressed)    boot_key   <= 1'b1;
    end
end
wire boot_keys = (boot_timer != 28'd135_000_000) & ~boot_key;
wire shift_now = (boot_mode == 2'd1) & boot_keys;
wire bs_now    = (boot_mode == 2'd2) & boot_keys;

logic [7:0] kbd_cols;
kbd_520ex kbd (
    .clk(clk_bus),
    .reset(mem_reset),        // las teclas mantenidas sobreviven al RES
    .key_strobe(key_strobe),
    .key_pressed(key_pressed),
    .key_extended(key_extended),
    .key_code(key_code),
    .joystick((joystick) | (amx_mouse_en ? {1'b0, amx_dout} : 8'd0)),
    .force_shift(shift_now),
    .force_bs(bs_now),
    .res_key(res_key),
    .row(ppi_pc_o[3:0]),
    .cols(kbd_cols)
);

logic [7:0] psg_a, psg_b, psg_c;
YM2149 psg (
    .CLK(clk_bus),
    .CE(psg_ce),
    .RESET(system_reset),
    .BDIR(ppi_pc_o[7]),
    .BC(ppi_pc_o[6]),
    .DI(ppi_pa_o),
    .DO(psg_to_ppi),
    .CHANNEL_A(psg_a),
    .CHANNEL_B(psg_b),
    .CHANNEL_C(psg_c),
    .SEL(1'b0),                 // divisor /8: tono = 1 MHz / (16 * periodo), como el AY-3-8910
    .MODE(1'b1),                // tabla de volumen del AY
    .ACTIVE(),
    .IOA_in(kbd_cols),
    .IOA_out(),
    .IOB_in(8'hFF),             // puerto B: impresora (no hay)
    .IOB_out()
);

// Mezcla: mono (A+B+C) o estereo ABC como en el CPC (B en el centro).
// 0..765 -> 16 bits con signo, sin pasar de +32767.
logic [9:0] mix_l, mix_r;
always_ff @(posedge clk_bus) begin
    if (audio_stereo) begin
        mix_l <= {1'b0, psg_a, 1'b0} + {2'b00, psg_b};
        mix_r <= {1'b0, psg_c, 1'b0} + {2'b00, psg_b};
    end else begin
        mix_l <= {2'b00, psg_a} + {2'b00, psg_b} + {2'b00, psg_c};
        mix_r <= {2'b00, psg_a} + {2'b00, psg_b} + {2'b00, psg_c};
    end
end
// AY (0..765 -> 0..12240, sin signo) + MagicSound (+-16128 por lado), con margen.
// MagicSound en estereo: A y D a la izquierda, B y C a la derecha (Amiga). En
// mono, los cuatro canales a los dos lados (antes solo iban A+D a la izquierda
// y B+C a la derecha tambien en mono: con un solo altavoz faltaban canales).
wire signed [16:0] ms_mono = (17'(ms_out_l) + 17'(ms_out_r)) >>> 1;
wire signed [15:0] ms_l = audio_stereo ? (ms_out_l >>> 1) : 16'(ms_mono >>> 1);
wire signed [15:0] ms_r = audio_stereo ? (ms_out_r >>> 1) : 16'(ms_mono >>> 1);
// Cinta (OSD Tape sound: se oye mientras se reproduce) y tono de prueba de
// 1 kHz (OSD Test tone, como en NewBrain): separa "no sale sonido" de "no entra
// la cinta". 54 MHz / 54000 = 1 kHz; medio periodo, 27000 ciclos.
logic [14:0] tone_cnt;
logic        tone;
always_ff @(posedge clk_bus) begin
    if (tone_cnt == 15'd26999) begin tone_cnt <= '0; tone <= ~tone; end
    else tone_cnt <= tone_cnt + 15'd1;
end
localparam logic signed [15:0] TAPE_LEVEL = 16'sd4096;
wire signed [15:0] tape_audio = test_tone                   ? (tone      ? TAPE_LEVEL : -TAPE_LEVEL)
                              : (tape_sound && (tape_running || tape_motor)) ? (tape_src ? TAPE_LEVEL : -TAPE_LEVEL)
                              : 16'sd0;
assign audio_l = 16'($signed({1'b0, mix_l, 4'b0}) + ms_l + tape_audio);
assign audio_r = 16'($signed({1'b0, mix_r, 4'b0}) + ms_r + tape_audio);

// ---- EXTEND PORT del 520EX (FABC-FABF, solo escritura). Reparto segun el
// fuente del BOOTMENU y CPCWiki:
//   D0 decodificacion de la direccion de video (banco)   D1 alta resolucion
//   D2 MAPMOD (mapper MSX)   D3 pantalla encendida
//   D4 el 8253 escribe (registro = A1..A0, dato = puerto A de la PPI)
//   D5 el puerto A de la PPI va al reloj MC146818 en vez de al AY
// Tras el reset vale 0: el BOOTMENU (ROM 3) lo pone a 8 (AMSTRAD) o 4 (Aleste).
wire ext_cs = leg_io & sys_we & (sys_adr[15:8] == 8'hFA) & sys_adr[7] & sys_adr[5];   // FABx (A5=1; FADx = MagicSound)
logic       ext_ack;
logic [7:0] pit_reg [0:3];           // 8253: por ahora solo se guardan las escrituras
always_ff @(posedge clk_bus) begin
    ext_ack <= bus_req & ext_cs & ~ext_ack;
    if (cpu_reset) extport <= 8'h00;
    else if (bus_req & ext_cs & ~ext_ack) begin
        extport <= sys_dat;
        if (sys_dat[4]) pit_reg[sys_adr[1:0]] <= ppi_pa_o;
    end
end

// ---- 8251 (K580VV51), puerto serie / raton: EExx datos, EFxx control/estado.
// Todavia no hay puerto serie: se responde como un 8251 en reposo. Estado 85h:
// TxRDY y TxEMPTY a 1, sin caracter recibido (RxRDY=0), sin errores (PE, OE,
// FE = 0) y DSR=1. La interrupcion de la BIOS de MSX-DOS lee este estado en
// cada cuadro: con FF (sin dispositivo) veia errores y "caracter recibido"
// siempre y volvia a inicializarse una y otra vez (pantalla en negro).
wire usart_cs = leg_io & (sys_adr[15:9] == 7'b1110111);
logic       usart_ack;
logic [7:0] usart_dat;
// 8251 con el raton serie (Mouse Systems, como lo atiende la BIOS de MSX-DOS)
serial_mouse #(.CLK_HZ(54_000_000)) mouse (
    .clk(clk_bus),
    .reset(system_reset),
    .cs(bus_req & usart_cs),
    .we(sys_we),
    .a8(sys_adr[8]),
    .din(sys_dat),
    .dout(usart_dat),
    .ack(usart_ack),
    .mouse_x(mouse_x),
    .mouse_y(mouse_y),
    .mouse_flags(mouse_flags),
    .mouse_strobe(mouse_strobe)
);

// ---- Reloj MC146818 (K512VI1), por la PPI cuando FABF D5=1
rtc146818 #(.CLK_HZ(54_000_000)) rtc (
    .clk(clk_bus),
    .reset(system_reset),
    .sel(extport[5]),
    .cmd(ppi_pc_o[2:0]),
    .din(ppi_pa_o),
    .dout(rtc_dout),
    .drive(rtc_drive),
    .cmos_we(cmos_we),
    .cmos_addr(cmos_addr),
    .cmos_din(cmos_din),
    .cmos_dout(cmos_dout),
    .dirty(rtc_dirty),
    .cmos_clean(cmos_clean),
    .set_time(rtc_set),
    .set_sec(mist_rtc[7:0]), .set_min(mist_rtc[15:8]), .set_hour(mist_rtc[23:16]),
    .set_day(mist_rtc[31:24]), .set_mon(mist_rtc[39:32]), .set_year(mist_rtc[47:40]),
    .set_wday(mist_rtc[50:48])
);

// ---- Ratones del CPC (modulos de Sorgelig de los cores Amstrad de MiST y
// MiSTer), con el raton de MiST. El raton serie del 520EX (8251) es para
// MSX-DOS; los programas de CPC usan estos:
//   Kempston       FBEE (X), FBEF (Y), FAEF (botones)  [aqui solo FAxx/FBxx con
//                  A7=1, A4=0: la decodificacion original (A10, A4) chocaria con
//                  la disquetera]
//   SYMBiFACE II   FD10 (X, Y y botones por turnos)     SymbOS
//   Multiplay      F990-F997                            SymbOS, juegos
//   AMX            por el joystick 1                    AMX Art, Art Studio...
logic        cm_stb_lvl;
always_ff @(posedge clk_bus) if (mouse_strobe) cm_stb_lvl <= ~cm_stb_lvl;
wire [24:0] ps2_mouse = {cm_stb_lvl, mouse_y[7:0], mouse_x[7:0], mouse_flags};

wire kemp_hit = (sys_adr[15:9] == 7'b1111101) & sys_adr[7] & ~sys_adr[4];
wire sf2_hit  = (sys_adr[15:0] == 16'hFD10);
wire mp_hit   = (sys_adr[15:4] == 12'hF99) & ~sys_adr[3];
wire cpcm_cs  = leg_io & ~sys_we & cpc_mouse_en & (kemp_hit | sf2_hit | mp_hit);
wire cpcm_req = bus_req & cpcm_cs;

logic [7:0] kemp_dout, sf2_dout, mp_dout;
kempston_mouse kmouse (
    .clk_sys(clk_bus), .reset(cpu_reset), .ps2_mouse(ps2_mouse),
    .addr({sys_adr[0], cpcm_req & kemp_hit, sys_adr[8]}), .sel(), .dout(kemp_dout)
);
symbiface_mouse smouse (
    .clk_sys(clk_bus), .reset(cpu_reset), .ps2_mouse(ps2_mouse),
    .sel(cpcm_req & sf2_hit), .dout(sf2_dout)
);
multiplay_mouse mmouse (
    .clk_sys(clk_bus), .reset(cpu_reset), .ps2_mouse(ps2_mouse),
    .sel(cpcm_req & mp_hit), .addr(sys_adr[2:0]), .dout(mp_dout)
);
amx_mouse amouse (
    .clk_sys(clk_bus), .reset(cpu_reset), .ps2_mouse(ps2_mouse),
    .sel(ppi_pc_o[3:0] == 4'd9), .dout(amx_dout)
);
// SYMBiFACE II y Multiplay cargan el dato en el flanco de subida de sel: se
// responde al bus al tercer ciclo, con el dato ya estable
logic [1:0] cm_cnt;
logic       cm_ack;
always_ff @(posedge clk_bus) begin
    cm_ack <= 1'b0;
    if (!cpcm_req || cm_ack) cm_cnt <= 2'd0;
    else if (cm_cnt == 2'd3) cm_ack <= 1'b1;
    else cm_cnt <= cm_cnt + 2'd1;
end
wire [7:0] cpcm_dat = kemp_dout & sf2_dout & mp_dout;

// ---- MagicSound del 520EX (rtl/cpc/magic_sound.sv): F8D0-FBDF, A10=A5=0
wire ms_cs = leg_io & (sys_adr[15:10] == 6'b111110) & (sys_adr[7:4] == 4'hD);
logic [7:0] ms_dat;
logic       ms_ack;
magic_sound ms (
    .clk(clk_bus),
    .reset(system_reset),
    .cs(bus_req & ms_cs),
    .we(sys_we),
    .adr(sys_adr[9:0]),
    .din(sys_dat),
    .dout(ms_dat),
    .ack(ms_ack),
    .dma_cyc(ms_dma_cyc),
    .dma_adr(ms_dma_adr),
    .dma_dat(m2_dat),
    .dma_ack(m2_ack & (m2_owner == 2'd1)),
    .dma_err(m2_err & (m2_owner == 2'd1)),
    .nmi(ms_nmi),
    .out_l(ms_out_l),
    .out_r(ms_out_r)
);

// ---- ALESTE.CMO: la RAM del reloj guardada en la SD (tercera imagen de user_io)
// Al montar el fichero se leen sus 64 primeros bytes en el reloj. Si despues la
// CPU cambia algo (SETUP, sumas de MSX-DOS, fecha), a los 2 s se escribe el
// bloque 0 entero. La SD se comparte con la disquetera: el CMOS solo empieza
// cuando la disquetera no tiene peticion ni transferencia, y mientras dura se le
// retienen las peticiones y no ve el ACK.
logic [31:0] fdc_sd_lba;
logic [1:0]  fdc_sd_rd, fdc_sd_wr;
logic [7:0]  fdc_sd_din;
logic        cmos_present, cmos_rd, cmos_wr, cmos_busy, cmos_ack_d, cmos_mnt_d, cmos_req;
logic [26:0] cmos_wait;                     // 2 s a 54 MHz antes de guardar
always_ff @(posedge clk_bus) begin
    cmos_clean <= 1'b0;
    cmos_ack_d <= sd_ack;
    cmos_mnt_d <= img_mounted[2];
    // Solo el reset del PLL: el firmware monta las imagenes automaticas
    // (ALESTE.HD2) antes de soltar el reset del OSD, y ese aviso no se puede perder.
    if (mem_reset) begin
        cmos_present <= 1'b0; cmos_rd <= 1'b0; cmos_wr <= 1'b0; cmos_busy <= 1'b0; cmos_req <= 1'b0;
        cmos_wait <= '0;
    end else begin
        if (img_mounted[2] && !cmos_mnt_d) begin       // flanco: una sola carga por montaje
            cmos_present <= |img_size;
            if (|img_size) cmos_rd <= 1'b1;
        end
        if (!rtc_dirty || !cmos_present) cmos_wait <= '0;
        else if (cmos_wait != 27'd108_000_000) cmos_wait <= cmos_wait + 27'd1;
        // empezar: solo con la disquetera quieta
        if (!cmos_busy && !sd_ack && fdc_sd_rd == 2'b00 && fdc_sd_wr == 2'b00) begin
            if (cmos_rd || (cmos_present && cmos_wait == 27'd108_000_000)) begin
                cmos_busy <= 1'b1;
                cmos_req  <= 1'b1;
                if (!cmos_rd) begin cmos_wr <= 1'b1; cmos_clean <= 1'b1; cmos_wait <= '0; end
            end
        end
        // la peticion se retira al llegar el ACK, como hace el u765 (si no,
        // user_io la toma como otra peticion al acabar)
        if (cmos_busy && sd_ack) cmos_req <= 1'b0;
        // fin de la transferencia (flanco de bajada del ACK)
        if (cmos_busy && cmos_ack_d && !sd_ack) begin
            cmos_busy <= 1'b0; cmos_rd <= 1'b0; cmos_wr <= 1'b0;
        end
    end
end
// Puesta en hora desde el firmware de MiST (solo si la placa tiene reloj: el
// ultimo byte, 40h, llega cuando ya estan los demas): la primera vez que llega
// y otra vez tras cargar el CMOS, que trae una hora antigua.
logic rtc_seen, cmos_was_rd;
always_ff @(posedge clk_bus) begin
    rtc_set     <= 1'b0;
    cmos_was_rd <= cmos_busy & cmos_rd;
    if (mem_reset) rtc_seen <= 1'b0;
    else begin
        if (cmos_was_rd && !(cmos_busy & cmos_rd)) rtc_seen <= 1'b0;      // CMOS cargado
        if (!rtc_seen && mist_rtc[63:56] == 8'h40) begin rtc_set <= 1'b1; rtc_seen <= 1'b1; end
    end
end
assign cmos_we   = cmos_busy & cmos_rd & sd_ack & sd_buff_wr & (sd_buff_addr[8:6] == 3'd0);
assign cmos_addr = sd_buff_addr[5:0];
assign cmos_din  = sd_buff_dout;
assign sd_lba      = cmos_busy ? 32'd0 : fdc_sd_lba;
assign sd_rd       = {cmos_req & cmos_rd, cmos_busy ? 2'b00 : fdc_sd_rd};
assign sd_wr       = {cmos_req & cmos_wr, cmos_busy ? 2'b00 : fdc_sd_wr};
assign sd_buff_din = cmos_busy ? ((sd_buff_addr[8:6] == 3'd0) ? cmos_dout : 8'h00) : fdc_sd_din;

// ---- Cinta (CDT/TZX): el fichero se descarga a 0x800000 (indice 3 del OSD) y
// el reproductor de gyurco (rtl/cpc/tzxplayer.sv, con los tiempos del CPC del
// core Amstrad) pide los bytes de uno en uno. El motor lo controla PC4 de la
// PPI, como en el CPC; la senal entra por PB7. Se rebobina al cargar una cinta
// y con el reset.
wire        tape_download = ioctl_download && (ioctl_index[5:0] == 6'd3);
logic [21:0] tape_last, tape_pos;
logic        tape_req, tape_ack, tape_end, tape_restart;
logic [7:0]  tape_byte;
always_ff @(posedge clk_bus) begin
    tape_restart <= 1'b0;
    if (tape_download && ioctl_wr) tape_last <= ioctl_addr[21:0];
    if (system_reset || tape_download) begin
        tape_pos <= '0; tape_cyc <= 1'b0; tape_end <= 1'b0; tape_restart <= 1'b1;
        if (tape_download && ioctl_addr == 27'd0) tape_last <= '0;
    end else if (tape_cyc) begin
        if (m2_ack && m2_owner == 2'd2) begin      // byte leido de la SDRAM
            tape_byte <= m2_dat;
            tape_cyc  <= 1'b0;
            tape_ack  <= tape_req;
            tape_pos  <= tape_pos + 22'd1;
        end
    end else if (tape_req != tape_ack && !ioctl_download) begin
        if (tape_pos <= tape_last) begin
            tape_adr <= {2'b10, tape_pos};         // 0x800000 + posicion
            tape_cyc <= 1'b1;
        end else
            tape_end <= 1'b1;                      // fin de la cinta: se para el motor
    end
end

// Motor: el firmware escribe la palabra de modo de la PPI al leer el teclado
// (tambien mientras espera la cinta, para ver si se pulsa ESC), y eso pone PC4 a
// 0 durante una fraccion de microsegundo. El rele de un CPC real no se entera;
// el reproductor, con su inercia de 50 ms, se reiniciaba con cada parpadeo y la
// cinta no arrancaba nunca. Aqui el motor se mantiene 1 ms tras verse PC4 a 1.
logic [15:0] motor_hold;
always_ff @(posedge clk_bus) begin
    if (ppi_pc_o[4]) begin motor_hold <= 16'd54000; tape_motor <= 1'b1; end
    else if (motor_hold != 0) motor_hold <= motor_hold - 16'd1;
    else tape_motor <= 1'b0;
end

tzxplayer #(
    .TZX_MS(54000),                                // 54 MHz con ce = 1
    .NORMAL_PILOT_LEN(2000), .NORMAL_SYNC1_LEN(855), .NORMAL_SYNC2_LEN(855),
    .NORMAL_ZERO_LEN(855), .NORMAL_ONE_LEN(1710),
    .HEADER_PILOT_PULSES(4095), .NORMAL_PILOT_PULSES(4095)
) tape (
    .clk(clk_bus),
    .ce(1'b1),
    .restart_tape(tape_restart),
    .host_tap_in(tape_byte),
    .tzx_req(tape_req),
    .tzx_ack(tape_ack),
    .loop_start(), .loop_next(), .stop(), .stop48k(),
    .cass_read(tape_read),
    .cass_motor(tape_motor & ~tape_end),
    .cass_running(tape_running)
);
// Entrada de cinta: mientras se reproduce un fichero CDT/TZX manda el
// reproductor; si no, la entrada de audio de la placa (AUDIO_IN, un
// magnetofono de verdad). "Invert tape in" vale para las dos.
logic [1:0] tape_ext_s;
always_ff @(posedge clk_bus) tape_ext_s <= {tape_ext_s[0], tape_ext};
assign tape_src = tape_running ? tape_read : tape_ext_s[1];
assign tape_in = tape_src ^ tape_invert;

// ---- Disquetera: uPD765 (rtl/cpc/u765.sv: el de Amstrad_MiST con INT y
// con imagenes raw, ademas de DSK/EDSK). Puertos del CPC y del 520EX:
//   FB7E estado, FB7F datos (A10=0, A8=1, A7=0; A0 elige)
//   FA7E motor (A10=0, A8=0, A7=0; D0)
wire fdc_cs = leg_io & ~sys_adr[10] &  sys_adr[8] & ~sys_adr[7];
wire mot_cs = leg_io & ~sys_adr[10] & ~sys_adr[8] & ~sys_adr[7] & sys_we;
logic       fdc_motor;
logic       mot_ack;
always_ff @(posedge clk_bus) begin
    if (system_reset) fdc_motor <= 1'b0;
    else if (bus_req & mot_cs & ~mot_ack) fdc_motor <= sys_dat[0];
    mot_ack <= bus_req & mot_cs & ~mot_ack;
end

// Reloj del 765: ce = 54/7 = 7,71 MHz, como los 8 MHz de Amstrad_MiST/MiSTer.
// Dentro del u765 cada ce alterna entre las dos unidades, asi que cada una
// avanza a ce/2 y CYCLES (ciclos por ms de cada unidad) = 7.714.286/2/1000 =
// 3857: 32 us por byte y 200 ms por vuelta, como un disco real. (Antes:
// ce = 4,5 MHz con CYCLES=4500, todo al doble de lento.)
//
// El 765 solo mira RD/WR en sus ciclos de reloj (ce): para
// que vea cada acceso, RD o WR tienen que estar activos durante al menos un
// ce y volver a reposo durante otro antes del siguiente acceso. En el CPC los
// accesos de E/S van separados por 1 us o mas; nuestro Z80 es mucho mas
// rapido y, sin esto, el 765 juntaba dos lecturas de estado seguidas y se
// perdia un byte de resultado (AMSDOS se quedaba esperando). Cada acceso
// dura 26 ciclos de 54 MHz (3 ce) y entre dos accesos hay al menos 26 en
// reposo. Peor caso para la CPU: 52 ciclos (watchdog del bus: 128).
logic [3:0] fdc_div;
logic       fdc_ce;
always_ff @(posedge clk_bus) begin
    fdc_ce <= (fdc_div == 4'd6);
    fdc_div <= (fdc_div == 4'd6) ? 4'd0 : fdc_div + 4'd1;
end
localparam [5:0] FDC_ACTIVE = 6'd26, FDC_IDLE = 6'd26;
logic [5:0] fdc_cnt, fdc_rest;
logic       fdc_busy, fdc_ack, fdc_nrd, fdc_nwr;
logic [7:0] fdc_dout, fdc_dat;
always_ff @(posedge clk_bus) begin
    fdc_ack <= 1'b0;
    if (system_reset) begin
        fdc_busy <= 1'b0; fdc_nrd <= 1'b1; fdc_nwr <= 1'b1; fdc_rest <= FDC_IDLE;
    end else if (fdc_busy) begin
        fdc_cnt <= fdc_cnt + 6'd1;
        if (fdc_cnt == FDC_ACTIVE - 6'd1) begin
            fdc_dat  <= fdc_dout;           // dato valido con RD activo
            fdc_nrd  <= 1'b1;
            fdc_nwr  <= 1'b1;
            fdc_busy <= 1'b0;
            fdc_ack  <= 1'b1;
            fdc_rest <= '0;
        end
    end else begin
        if (fdc_rest != FDC_IDLE) fdc_rest <= fdc_rest + 6'd1;
        else if (!fdc_ack && bus_req && fdc_cs) begin
            fdc_busy <= 1'b1;
            fdc_cnt  <= '0;
            fdc_nrd  <= sys_we;
            fdc_nwr  <= ~sys_we;
        end
    end
end

// Unidad lista: imagen montada con algo dentro
logic [1:0] fdc_ready;
always_ff @(posedge clk_bus) begin
    if (img_mounted[0]) fdc_ready[0] <= |img_size;
    if (img_mounted[1]) fdc_ready[1] <= |img_size;
end

u765 #(.CYCLES(FDC_CYCLES)) fdc (
    .clk_sys(clk_bus),
    .ce(fdc_ce),
    .reset(system_reset),
    .ready(fdc_ready),
    .motor({fdc_motor, fdc_motor}),
    .available({~fdc_one_drive, 1'b1}),   // unidades presentes (OSD: Floppy drives)
    .fast(fdc_fast),
    .a0(sys_adr[0]),
    .nRD(fdc_nrd),
    .nWR(fdc_nwr),
    .din(sys_dat),
    .dout(fdc_dout),
    .int_o(fdc_int),
    .img_mounted(img_mounted[1:0]),
    .img_wp(img_wp),
    .img_size(img_size),
    .sd_lba(fdc_sd_lba),
    .sd_rd(fdc_sd_rd),
    .sd_wr(fdc_sd_wr),
    .sd_ack(sd_ack & ~cmos_busy),
    .sd_buff_addr(sd_buff_addr),
    .sd_buff_dout(sd_buff_dout),
    .sd_buff_din(fdc_sd_din),
    .sd_buff_wr(sd_buff_wr)
);

// ---- Resto de la E/S CPC sin dispositivo (disquetera, impresora...) y el
// ciclo de reconocimiento de interrupcion (M1+IORQ, que la MMU legacy saca
// como E/S a FF0000+PC): respuesta inmediata con FF para no esperar al
// watchdog en cada acceso.
wire leg_none = legacy & (sys_adr[23:16] == 8'hFF) & ~ga_cfg & ~ppi_cs & ~vc_grant & ~crtc_cs & ~ga_pen & ~fdc_cs & ~mot_cs & ~ext_cs & ~usart_cs & ~ga_rd & ~ms_cs & ~cpcm_cs;
logic none_ack;
always_ff @(posedge clk_bus) none_ack <= bus_req & leg_none & ~none_ack;

assign vid_ack            = vc_ack | ga_ack | ppi_ack | none_ack | cv_ack | fdc_ack | mot_ack | ext_ack | usart_ack | ga_rd_ack | ms_ack | cm_ack;
assign vid_grant          = vc_grant | (bus_req & (ga_cfg | ppi_cs | leg_none | crtc_cs | ga_pen | fdc_cs | mot_cs | ext_cs | usart_cs | ga_rd | ms_cs | cpcm_cs));
assign vid_dat_from_slave = ppi_cs ? ppi_dat : crtc_cs ? cv_dat : fdc_cs ? fdc_dat : usart_cs ? usart_dat : ga_rd ? ga_rd_dat : ms_cs ? ms_dat : cpcm_cs ? cpcm_dat : leg_none ? 8'hFF : vc_dat;

// ---- Interrupciones del Gate Array: una cada 52 HSYNC; 2 HSYNC despues
// del inicio del VSYNC el contador vuelve a 0 (y si iba por 32 o mas, hay
// interrupcion). El reconocimiento (INTA) borra el bit 5 del contador, y
// RMR con D4=1 lo pone a 0. Ver doc/02-hardware-aleste520ex.md.
logic [5:0] irq_cnt;
logic [1:0] vs_wait;
logic       irq;
// En el CPC, RMR con D4=1 pone a cero el contador de interrupciones. En el
// 520EX ese bit es el LED RUS y no toca las interrupciones (CPCWiki,
// Aleste 520EX - Misc), asi que aqui no se hace nada con el.
wire rmr_irq_reset = 1'b0;
always_ff @(posedge clk_bus) begin
    if (cpu_reset || !legacy) begin
        irq_cnt <= '0; vs_wait <= '0; irq <= 1'b0;
    end else begin
        if (vs_start) vs_wait <= 2'd2;
        if (hs_end) begin
            if (vs_wait == 2'd1) begin
                if (irq_cnt >= 6'd32) irq <= 1'b1;
                irq_cnt <= '0;
            end else if (irq_cnt == 6'd51) begin
                irq <= 1'b1;
                irq_cnt <= '0;
            end else begin
                irq_cnt <= irq_cnt + 6'd1;
            end
            if (vs_wait != 2'd0) vs_wait <= vs_wait - 2'd1;
        end
        if (int_ack) begin
            irq <= 1'b0;
            irq_cnt <= {1'b0, irq_cnt[4:0]};
        end
        if (rmr_irq_reset) begin
            irq <= 1'b0;
            irq_cnt <= '0;
        end
    end
end
assign cpc_int = irq;

logic [23:0] video2mem_addr;
logic [15:0] video2mem_data_out, video2mem_data_in;
logic        video2mem_we, video2mem_req, video2mem_ack0, video2mem_ack1;
logic [1:0]  video2mem_sel;

video_ctrl_vga #(
    .SDRAM_ADDR_WIDTH(24),
    .SDRAM_DATA_WIDTH(16)
) video_controller (
    .clk_system(clk_system),
    .clk_bus(clk_bus),
    .clk_pixel(clk_pixel),
    .clk_pixel_x2(clk_bus),
    .system_reset(system_reset),

    .wb_cyc_i(vid_cyc),
    .wb_stb_i(vid_stb),
    .wb_we_i(vid_we),
    .wb_adr_i(vid_adr),
    .wb_dat_i(vid_dat_to_slave),
    .wb_dat_o(vc_dat),
    .wb_ack_o(vc_ack),
    .wb_grant_o(vc_grant),
    .wb_tag_i(sys_tag),
    .wb_cs_pal_i(cs_legacy[0]),     // 0xFF0100
    .wb_cs_crt_i(cs_legacy[1]),     // 0xFF0120

    .mem_addr_o(video2mem_addr),
    .mem_data_o(video2mem_data_out),
    .mem_data_i(video2mem_data_in),
    .mem_we_o(video2mem_we),
    .mem_req_o(video2mem_req),
    .mem_ack0_i(video2mem_ack0),
    .mem_ack1_i(video2mem_ack1),
    .mem_sel_o(video2mem_sel),

    .vga_rgb(vga_rgb),
    .vga_hs(vga_hs),
    .vga_vs(vga_vs),
    .vga_hblank(vga_hblank),
    .vga_vblank(vga_vblank),
    .hdmi_rd(),
    .hdmi_newline(),
    .hdmi_newframe(),
    .hdmi_x(),
    .hdmi_y(),

    .debug_leds(),
    .debug(),
    // El video del LX no atiende la E/S CPC: en modo CPC la imagen sale de
    // cpc_video (temporizacion real). Le cede el puerto de video de la SDRAM.
    .cfg_native_i(1'b1),
    .ext_vid_sel(leg_m),
    .ext_vid_addr({8'h00, cpc_mem_addr}),
    .ext_vid_req(cpc_mem_req),
    .ext_vid_ack0(cpc_mem_ack0),
    .ext_vid_data(cpc_mem_data),
    .cfg_cpc_mode_i(cpc_mode),
    .crtc_hsync_o(),
    .crtc_vsync_o()
);

// ============================================================================
// SDRAM
// ============================================================================
logic [2:0] sdram_state;

// El sdram_wishbone del Aleste LX no se refresca solo: tiene una entrada
// wb_refresh_i que en el original va a 0, y la memoria que no barre el video
// (la ROM en 0xC00000, por ejemplo) se pierde en unos 64 ms. Aqui se pide un
// auto-refresh cada 7,2 us (8192 filas en 59 ms) y la peticion se retira en
// cuanto el controlador entra en REFRESH (estado 5). El controlador solo lo
// atiende en IDLE sin lecturas ni escrituras pendientes.
//
// La peticion solo se presenta tras REFRESH_IDLE ciclos seguidos en IDLE: el
// controlador vuelve a IDLE nada mas recoger la segunda palabra, pero la
// lectura es en rafaga de 4 con autoprecarga y el banco aun esta
// precargando. Un REFRESH en ese momento viola tRP (lo detecta el modelo de
// SDRAM de sim/). Lecturas y escrituras no tienen el problema porque el
// arbitro tarda mas en volver a pedir.
localparam int REFRESH_CYCLES = 780;            // 7,22 us a 108 MHz
localparam int REFRESH_IDLE   = 3;              // >= 2 ciclos de precarga pendiente
localparam [9:0] REFRESH_LAST = REFRESH_CYCLES - 1;
localparam [1:0] IDLE_MIN     = REFRESH_IDLE;
logic [9:0] refresh_cnt;
logic       refresh_req;
logic [1:0] idle_cnt;

always_ff @(posedge clk_system) begin
    if (mem_reset || sdram_state != 3'd2)      // 2 = IDLE
        idle_cnt <= '0;
    else if (idle_cnt != 2'd3)
        idle_cnt <= idle_cnt + 2'd1;
end
wire refresh_go = refresh_req && (idle_cnt >= IDLE_MIN);

always_ff @(posedge clk_system) begin
    if (mem_reset) begin
        refresh_cnt <= '0;
        refresh_req <= 1'b0;
    end else begin
        if (sdram_state == 3'd5)
            refresh_req <= 1'b0;
        if (refresh_cnt == REFRESH_LAST) begin
            refresh_cnt <= '0;
            refresh_req <= 1'b1;
        end else begin
            refresh_cnt <= refresh_cnt + 10'd1;
        end
    end
end

assign sdram_refreshing = (sdram_state == 3'd5);

// T_RC: el original trae 6 ciclos, que a 108 MHz son 55,6 ns y la SDRAM pide
// 60 (REFRESH tras REFRESH en la inicializacion y duracion del REFRESH).
`ifdef CALYPSO
// Calypso: chip de 8 MB = 4096 filas x 256 columnas x 4 bancos (12 + 8 + 2 bits);
// el puerto SDRAM_A del controlador es de 13 bits: con filas de 12, A12 queda a 0
sdram_wishbone #(
    .CLK_FREQ(108_000_000),
    .WB_ADDR_WIDTH(22),
    .WB_DATA_WIDTH(16),
    .ROW_WIDTH(12),
    .COL_WIDTH(8),
    .T_RC(5'd7)
) sdram_ctrl (
`else
sdram_wishbone #(
    .CLK_FREQ(108_000_000),
    .WB_ADDR_WIDTH(24),
    .WB_DATA_WIDTH(16),
    .T_RC(5'd7)
) sdram_ctrl (
`endif
    .wb_clk_i(clk_system),
    .wb_rst_i(mem_reset),
    .wb_cyc_i(video2mem_req),
    .wb_stb_i(video2mem_req),
    .wb_ack0_o(video2mem_ack0),
    .wb_ack1_o(video2mem_ack1),
    .wb_we_i(video2mem_we),
`ifdef CALYPSO
    .wb_adr_i(video2mem_addr[21:0]),
`else
    .wb_adr_i(video2mem_addr),
`endif
    .wb_dat_i(video2mem_data_out),
    .wb_dat_o(video2mem_data_in),
    .wb_sel_i(video2mem_sel),
    .wb_refresh_i(refresh_go),

    .SDRAM_DQ_I(sdram_dq_i),
    .SDRAM_DQ_O(sdram_dq_o),
    .SDRAM_DQOEN(sdram_dq_oe),
    .SDRAM_A(sdram_a),
    .SDRAM_BA(sdram_ba),
    .SDRAM_nCS(sdram_ncs),
    .SDRAM_nWE(sdram_nwe),
    .SDRAM_nRAS(sdram_nras),
    .SDRAM_nCAS(sdram_ncas),
    .SDRAM_CKE(sdram_cke),
    .SDRAM_DQM(sdram_dqm),

    .debug_state(sdram_state),
    .debug_init_complete(),
    .debug_ready(),
    .debug_initialized(),
    .debug_configured(),
    .debug_cycle(),
    .debug_busy(),
    .debug_rst_cnt(),
    .debug_rst_done(),
    .debug_cfg_busy()
);

endmodule

`default_nettype wire
