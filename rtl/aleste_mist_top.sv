// ============================================================================
// aleste_mist_top.sv - Aleste LX para placas de la familia MiST
//
// FASE 3: modo CPC del 520EX con video de temporizacion real (15 kHz).
// FASE 2: Z80 + MMU nativa del Aleste LX, arrancando desde la ROM que el
// firmware carga de la SD (ALESTE.ROM). Ver aleste_core.sv.
//
// Placa por macro, como en NewBrain: POSEIDON (50 MHz). La estructura deja
// sitio para MIST y SIDI (27 MHz), que necesitan su propio PLL.
//
// Relojes (todos del mismo PLL y en fase, el Aleste LX los trata como
// sincronos entre si):
//   clk_system 108 MHz  SDRAM, arbitro de memoria, buffer de video
//   clk_bus     54 MHz  Wishbone, user_io, data_io, mist_loader
//   clk_pixel   27 MHz  barrido 720x480 a 59,94 Hz, OSD y salida VGA
// ============================================================================
`default_nettype none

`ifdef SIDI
`define RELOJ_27
`endif
`ifdef MIST
`define RELOJ_27
`endif
// Calypso (CYC1000, Cyclone 10 LP): reloj de 12 MHz, 8 LED, VGA de 4 bits y
// SDRAM de 8 MB (12 lineas de direccion; ver memory_arbiter.sv)
`ifdef CALYPSO
`define VGA_BITS 4
`else
`define VGA_BITS 6
`endif


module aleste_mist_top(
`ifdef RELOJ_27
    input         CLOCK_27,
`elsif POSEIDON
    input         CLOCK_50,
`elsif CALYPSO
    input         CLK12M,
`else
    `error "Placa sin definir: POSEIDON, MIST, SIDI o CALYPSO"
`endif
`ifdef CALYPSO
    output [7:0]  LED,          // activos a nivel alto; LED[0] = actividad
`else
    output        LED,          // activo a nivel bajo, como en MiST
`endif

    output [`VGA_BITS-1:0] VGA_R,
    output [`VGA_BITS-1:0] VGA_G,
    output [`VGA_BITS-1:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,

    input         SPI_SCK,
    inout         SPI_DO,
    input         SPI_DI,
    input         SPI_SS2,
    input         SPI_SS3,
    input         CONF_DATA0,
`ifndef NO_DIRECT_UPLOAD
    input         SPI_SS4,
`endif

`ifdef I2S_AUDIO
    output        I2S_BCK,
    output        I2S_LRCK,
    output        I2S_DATA,
`endif
`ifdef DELTASIGMA_AUDIO
    // Placas sin I2S (SiDi): sigma-delta de un bit por canal, con el filtro RC
    // en la placa (common/mist-modules/dac.vhd)
    output        AUDIO_L,
    output        AUDIO_R,
`endif
`ifdef USE_AUDIO_IN
    input         AUDIO_IN,
`endif

`ifdef CALYPSO
    output [11:0] SDRAM_A,      // 8 MB: 12 lineas de direccion
`else
    output [12:0] SDRAM_A,
`endif
    inout  [15:0] SDRAM_DQ,
    output        SDRAM_DQML,
    output        SDRAM_DQMH,
    output        SDRAM_nWE,
    output        SDRAM_nCAS,
    output        SDRAM_nRAS,
    output        SDRAM_nCS,
    output [1:0]  SDRAM_BA,
    output        SDRAM_CLK,
    output        SDRAM_CKE
);

`ifdef BIG_OSD
localparam bit BIG_OSD = 1;
`define SEP "-;",
`else
localparam bit BIG_OSD = 0;
`define SEP
`endif

`include "build_id.v"
parameter CONF_STR = {
    "ALESTE;;",
    // Indice 0: el firmware la carga sola al arrancar el core si en la SD
    // hay un ALESTE.ROM. Va a 0xC00000, donde arranca la MMU nativa; la CPU
    // esta en reset mientras se carga y arranca al terminar.
    "F0,ROM,Reload ROM;",
    // Indice 1: imagen en bruto a partir de 0x000000 (pantallas de prueba)
    "F1,SCRBIN,Load RAM image;",
    // Indice 2: guion de escrituras de bus (CRTC, paleta, memoria...)
    "F2,WBS,Run bus script;",
    // Indice 3: cinta del modo AMSTRAD (CDT = TZX del CPC), a la SDRAM en 0x800000
    "F3,CDTTZX,Load tape;",
    // Disquetera: DSK/EDSK de CPC o imagenes en bruto (MSX-DOS 720 KB)
    "S0U,DSKIMG,Mount Drive A:;",
    "S1U,DSKIMG,Mount Drive B:;",
    // RAM del reloj (SETUP del 520EX): ALESTE.CMO, se guarda sola
    "S2U,CMO,Mount CMOS (setup):;",
    `SEP
    // Modo CPC (ROM del 520EX): el SETUP de la ROM 3 arranca en AMSTRAD si
    // SHIFT esta pulsado al encender; si no, intenta MSX-DOS desde disco.
    "ODE,CPC boot,Aleste 520EX,AMSTRAD (Shift),Aleste BIOS;",
    "OF,Mouse (CPC),Enabled,Disabled;",
    "OG,AMX mouse,Disabled,Joystick 1;",
    "OHI,CPU speed,4 MHz,8 MHz (turbo),16 MHz;",
    "O23,Scanlines,Off,25%,50%,75%;",
    "O4,Audio,Mono,Stereo ABC;",
    "O5,Disk speed,Original,Fast;",
    "O6,Floppy drives,2,1;",
    "O79,H centre,0,+8,+16,+24,-32,-24,-16,-8;",
    "OAC,V centre,0,+2,+4,+6,-8,-6,-4,-2;",
    "P1,Tape & audio;",
    "P1OK,Tape sound,Disabled,Enabled;",
    "P1OR,Invert tape in,Off,On;",
    "P1OP,Test tone,No,Yes;",
    "T0,Reset & apply model;",
    "V,", `BUILD_VERSION, "-", `BUILD_DATE
};

// ============================================================================
// Relojes y reset
// ============================================================================
wire clk_system, clk_bus, clk_pixel;
wire pll_locked;

`ifdef RELOJ_27
wire clk_entrada = CLOCK_27;
`elsif CALYPSO
wire clk_entrada = CLK12M;
`else
wire clk_entrada = CLOCK_50;
`endif

pll pll(
    .inclk0(clk_entrada),
    .c0(clk_system),    // 108 MHz
    .c1(clk_bus),       //  54 MHz
    .c2(clk_pixel),     //  27 MHz
    .locked(pll_locked)
);

// PLL de video: 80 MHz para el video del modo CPC (16 MHz = 80/5 en modo
// AMSTRAD y 13,333 MHz = 80/6 en modo Aleste). Asincrono con el resto: todos
// los cruces van sincronizados (rtl/cpc/cpc_video.sv).
wire clk_vid, pll_vid_locked;
pll_video pll_video(
    .inclk0(clk_entrada),
    .c0(clk_vid),
    .locked(pll_vid_locked)
);

wire [63:0] status;
wire [31:0] sd_lba;
wire [2:0]  sd_rd, sd_wr, img_mounted;
wire        sd_ack, sd_buff_wr;
wire [8:0]  sd_buff_addr;
wire [7:0]  sd_buff_dout, sd_buff_din;
wire [63:0] img_size;
wire        key_strobe, key_pressed, key_extended;
wire [8:0]  mouse_x, mouse_y;
wire [7:0]  mouse_flags;
wire        mouse_strobe;
wire [63:0] mist_rtc;                // hora del firmware (si la placa tiene reloj)
wire [7:0]  key_code;
wire [31:0] joystick_0;
wire [15:0] audio_l, audio_r;
wire        scandoubler_disable, ypbpr, no_csync;
wire        cpu_legacy;
wire        cpc_ce_pix, cpc_hs, cpc_vs, cpc_hblank, cpc_vblank;
wire        cpc_hires;
wire [7:0]  cpc_r, cpc_g, cpc_b;
wire [1:0]  buttons;

// ============================================================================
// Firmware MiST: user_io (OSD, botones) y data_io (ficheros de la SD)
// ============================================================================
user_io #(
    .STRLEN($size(CONF_STR)>>3),
    .SD_IMAGES(3),
    // Reloj PS/2 = clk_sys / (2*(PS2DIV+1)) = 54 MHz / 4002 = 13,49 kHz (PS/2: 10-16,7 kHz)
    .PS2DIV(2000),
    .FEATURES(BIG_OSD ? 32'h0000_2000 : 32'h0000_0000))
user_io (
    .clk_sys(clk_bus),
    .clk_sd(clk_bus),
    .SPI_SS_IO(CONF_DATA0),
    .SPI_CLK(SPI_SCK),
    .SPI_MOSI(SPI_DI),
    .SPI_MISO(SPI_DO),
    .conf_str(CONF_STR),
    .conf_chr(8'h00),
    .status(status),
    .buttons(buttons),
    .scandoubler_disable(scandoubler_disable),
    .ypbpr(ypbpr),
    .no_csync(no_csync),
    .key_strobe(key_strobe),
    .key_pressed(key_pressed),
    .key_extended(key_extended),
    .key_code(key_code),
    .mouse_x(mouse_x),
    .mouse_y(mouse_y),
    .mouse_flags(mouse_flags),
    .mouse_strobe(mouse_strobe),
    .rtc(mist_rtc),
    .joystick_0(joystick_0),
    .sd_lba(sd_lba),
    .sd_rd(sd_rd),
    .sd_wr(sd_wr),
    .sd_ack(sd_ack),
    .sd_conf(1'b0),
    .sd_sdhc(1'b1),
    .sd_din(sd_buff_din),
    .sd_dout(sd_buff_dout),
    .sd_dout_strobe(sd_buff_wr),
    .sd_buff_addr(sd_buff_addr),
    .img_mounted(img_mounted),
    .img_size(img_size),
    .ps2_kbd_clk_i(1'b1),
    .ps2_kbd_data_i(1'b1),
    .ps2_mouse_clk_i(1'b1),
    .ps2_mouse_data_i(1'b1),
    .kbd_out_data(8'h00),
    .kbd_out_strobe(1'b0),
    .leds(8'h00),
    .i2c_din(8'h00),
    .i2c_ack(1'b0),
    .i2c_end(1'b0),
    .serial_data(8'h00),
    .serial_strobe(1'b0)
);

wire        ioctl_download;
wire [7:0]  ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire [7:0]  ioctl_dout;

data_io data_io(
    .clk_sys(clk_bus),
    .SPI_SCK(SPI_SCK),
    .SPI_SS2(SPI_SS2),
`ifdef NO_DIRECT_UPLOAD
    .SPI_SS4(1'b1),
`else
    .SPI_SS4(SPI_SS4),
`endif
    .SPI_DI(SPI_DI),
    .SPI_DO(SPI_DO),
    .clkref_n(1'b0),            // sin espera: la FIFO de mist_loader absorbe
    .ioctl_download(ioctl_download),
    .ioctl_index(ioctl_index),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_din(8'h00),
    .QCSn(1'b1),
    .QSCK(1'b1),
    .QDAT(4'hF),
    .hdd_clk(1'b0),
    .hdd_cmd_req(1'b0),
    .hdd_cdda_req(1'b0),
    .hdd_dat_req(1'b0),
    .hdd_data_in(16'h0000)
);

// ============================================================================
// Nucleo: cargador, bus, video y SDRAM
// ============================================================================
wire [11:0] vid_rgb;
wire        vid_hs, vid_vs, vid_hblank, vid_vblank;
wire        loader_busy, loader_overflow, loader_timeout;
wire        cpu_running, cpu_halted;
wire [12:0] sdram_a_w;
`ifdef CALYPSO
assign SDRAM_A = sdram_a_w[11:0];          // 12 lineas (A12 no existe en su chip)
`else
assign SDRAM_A = sdram_a_w;
`endif
wire [15:0] sdram_dq_o;
wire        sdram_dq_oe;
wire [1:0]  sdram_dqm;

aleste_core core (
    .clk_system(clk_system),
    .clk_bus(clk_bus),
    .clk_pixel(clk_pixel),
    .clk_vid(clk_vid),
    .pll_locked(pll_locked),
    .user_reset(status[0] | buttons[1]),
    .boot_mode(status[14:13]),
    .key_strobe(key_strobe),
    .key_pressed(key_pressed),
    .key_extended(key_extended),
    .key_code(key_code),
    .joystick(joystick_0[7:0]),
    .audio_stereo(status[4]),
    .fdc_fast(status[5]),
    .fdc_one_drive(status[6]),
    .mouse_x(mouse_x),
    .mouse_y(mouse_y),
    .mouse_flags(mouse_flags),
    .mouse_strobe(mouse_strobe),
    .mist_rtc(mist_rtc),
    .cpc_mouse_en(~status[15]),
    .amx_mouse_en(status[16]),
    .cpu_turbo(status[18:17]),
    .video_h_off(status[9:7]),
    .video_v_off(status[12:10]),
    .tape_sound(status[20]),
    .tape_invert(status[27]),
    .test_tone(status[25]),
    .img_mounted(img_mounted),
    .img_wp(1'b0),
    .img_size(img_size[31:0]),
    .sd_lba(sd_lba),
    .sd_rd(sd_rd),
    .sd_wr(sd_wr),
    .sd_ack(sd_ack),
    .sd_buff_addr(sd_buff_addr),
    .sd_buff_dout(sd_buff_dout),
    .sd_buff_din(sd_buff_din),
    .sd_buff_wr(sd_buff_wr),
    .audio_l(audio_l),
    .audio_r(audio_r),

    .ioctl_download(ioctl_download),
    .ioctl_index(ioctl_index),
    .ioctl_wr(ioctl_wr),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),

    .sdram_dq_i(SDRAM_DQ),
    .sdram_dq_o(sdram_dq_o),
    .sdram_dq_oe(sdram_dq_oe),
    .sdram_a(sdram_a_w),
    .sdram_ba(SDRAM_BA),
    .sdram_dqm(sdram_dqm),
    .sdram_ncs(SDRAM_nCS),
    .sdram_nras(SDRAM_nRAS),
    .sdram_ncas(SDRAM_nCAS),
    .sdram_nwe(SDRAM_nWE),
    .sdram_cke(SDRAM_CKE),

    .vga_rgb(vid_rgb),
    .vga_hs(vid_hs),
    .vga_vs(vid_vs),
    .vga_hblank(vid_hblank),
    .vga_vblank(vid_vblank),

    .loader_busy(loader_busy),
    .loader_overflow(loader_overflow),
    .loader_timeout(loader_timeout),
    .sdram_refreshing(),
    .cpu_running(cpu_running),
    .cpu_halted(cpu_halted),
    .cpu_legacy(cpu_legacy),
    .cpc_ce_pix(cpc_ce_pix),
    .cpc_r(cpc_r), .cpc_g(cpc_g), .cpc_b(cpc_b),
    .cpc_hs(cpc_hs), .cpc_vs(cpc_vs), .cpc_hires(cpc_hires),
    .cpc_hblank(cpc_hblank), .cpc_vblank(cpc_vblank)
);

assign SDRAM_DQ   = sdram_dq_oe ? sdram_dq_o : 16'hZZZZ;
assign SDRAM_DQML = sdram_dqm[0];
assign SDRAM_DQMH = sdram_dqm[1];

// Reloj de la SDRAM: clk_system invertido, sacado por un registro DDR del
// propio pin (lo mismo que el ODDRX1F del original y que NewBrain). Va medio
// periodo adelantado y con el mismo retardo de salida que ordenes y datos.
`ifdef MIST
localparam FAMILIA = "Cyclone III";
`elsif SIDI
localparam FAMILIA = "Cyclone IV E";
`else
localparam FAMILIA = "Cyclone IV GX";
`endif

altddio_out #(
    .extend_oe_disable("OFF"),
    .intended_device_family(FAMILIA),
    .invert_output("OFF"),
    .lpm_hint("UNUSED"),
    .lpm_type("altddio_out"),
    .oe_reg("UNREGISTERED"),
    .power_up_high("OFF"),
    .width(1)
) sdramclk_ddr (
    .datain_h(1'b0),
    .datain_l(1'b1),
    .outclock(clk_system),
    .dataout(SDRAM_CLK),
    .aclr(1'b0),
    .aset(1'b0),
    .oe(1'b1),
    .outclocken(1'b1),
    .sclr(1'b0),
    .sset(1'b0)
);

// ============================================================================
// Salida VGA con OSD
// ============================================================================
// El barrido ya es de 31 kHz (720x480), asi que no se usa el scandoubler de
// mist_video: el OSD va directamente sobre la imagen. 12 bits -> 6 bits por
// color repitiendo los bits altos.
wire [5:0] r6 = {vid_rgb[11:8], vid_rgb[11:10]};
wire [5:0] g6 = {vid_rgb[7:4],  vid_rgb[7:6]};
wire [5:0] b6 = {vid_rgb[3:0],  vid_rgb[3:2]};
wire [5:0] osd_r, osd_g, osd_b;

osd #(
    .OSD_COLOR(3'd4),
    .OSD_AUTO_CE(1'b1),
    .USE_BLANKS(1'b1),
    .OUT_COLOR_DEPTH(6),
    .BIG_OSD(BIG_OSD)
) osd (
    .clk_sys(clk_pixel),
    .ce(1'b1),
    .SPI_SCK(SPI_SCK),
    .SPI_SS3(SPI_SS3),
    .SPI_DI(SPI_DI),
    .rotate(2'b00),
    .R_in(r6),
    .G_in(g6),
    .B_in(b6),
    .HBlank(vid_hblank),
    .VBlank(vid_vblank),
    .HSync(vid_hs),
    .VSync(vid_vs),
    .R_out(osd_r),
    .G_out(osd_g),
    .B_out(osd_b),
    .osd_enable()
);

// ---- Video del modo CPC: 15 kHz con la temporizacion del CRTC. mist_video
// pone el OSD y lo dobla a 31 kHz, o lo deja a 15 kHz para RGB/SCART si el
// firmware tiene scandoubler_disable (mist.ini: scandoubler_disable=1).
wire [5:0] cpc_vr, cpc_vg, cpc_vb;
wire       cpc_vhs, cpc_vvs;

mist_video #(
    .COLOR_DEPTH(8),
    .SD_HCNT_WIDTH(11),
    .USE_BLANKS(1'b1),     // zona visible de cpc_video (OSD centrado)
    .OSD_COLOR(3'd4),
    .OUT_COLOR_DEPTH(6),
    .BIG_OSD(BIG_OSD))
cpc_video_out (
    .clk_sys(clk_vid),
    .SPI_SCK(SPI_SCK),
    .SPI_SS3(SPI_SS3),
    .SPI_DI(SPI_DI),
    .scanlines(status[3:2]),
    // El doblador muestrea al ritmo del pixel: 80/5 = 16 MHz (CPC) u 80/6 =
    // 13,33 MHz (alta resolucion del 520EX). Con 16 MHz fijos, en alta
    // resolucion uno de cada cinco pixeles salia doble y el texto de 640
    // columnas se leia mal. El doblador recoge el divisor en cada linea.
    .ce_divider(cpc_hires ? 3'd5 : 3'd4),
    .scandoubler_disable(scandoubler_disable),
    .no_csync(no_csync),
    .ypbpr(ypbpr),
    .rotate(2'b00),
    .blend(1'b0),
    .R(cpc_r), .G(cpc_g), .B(cpc_b),
    .HBlank(cpc_hblank), .VBlank(cpc_vblank),
    .HSync(cpc_hs), .VSync(cpc_vs),
    .VGA_R(cpc_vr), .VGA_G(cpc_vg), .VGA_B(cpc_vb),
    .VGA_VS(cpc_vvs), .VGA_HS(cpc_vhs),
    .VGA_HB(), .VGA_VB(), .VGA_DE()
);

// Que salida va a los pines: la del CPC cuando la CPU esta en modo CPC, la
// del video del LX (720x480, 31 kHz) en modo nativo. La seleccion cambia muy
// pocas veces (al arrancar una ROM); el monitor se resincroniza.
logic [1:0] sel_cpc_s;
always_ff @(posedge clk_vid) sel_cpc_s <= {sel_cpc_s[0], cpu_legacy};
logic [5:0] cpc_r_q, cpc_g_q, cpc_b_q;
logic       cpc_hs_q, cpc_vs_q;
always_ff @(posedge clk_vid) begin
    cpc_r_q  <= cpc_vr;
    cpc_g_q  <= cpc_vg;
    cpc_b_q  <= cpc_vb;
    cpc_hs_q <= cpc_vhs;
    cpc_vs_q <= cpc_vvs;
end

logic [5:0] vga_r_q, vga_g_q, vga_b_q;
logic       vga_hs_q, vga_vs_q;
always_ff @(posedge clk_pixel) begin
    vga_r_q  <= osd_r;
    vga_g_q  <= osd_g;
    vga_b_q  <= osd_b;
    vga_hs_q <= vid_hs;
    vga_vs_q <= vid_vs;
end
wire [5:0] vga_r_out = sel_cpc_s[1] ? cpc_r_q : vga_r_q;
wire [5:0] vga_g_out = sel_cpc_s[1] ? cpc_g_q : vga_g_q;
wire [5:0] vga_b_out = sel_cpc_s[1] ? cpc_b_q : vga_b_q;
assign VGA_R  = vga_r_out[5 -: `VGA_BITS];      // Calypso: los 4 bits altos
assign VGA_G  = vga_g_out[5 -: `VGA_BITS];
assign VGA_B  = vga_b_out[5 -: `VGA_BITS];
assign VGA_HS = sel_cpc_s[1] ? cpc_hs_q : vga_hs_q;
assign VGA_VS = sel_cpc_s[1] ? cpc_vs_q : vga_vs_q;

// ============================================================================
// Audio (AY, MagicSound, cinta): I2S (Poseidon) o sigma-delta (SiDi)
// ============================================================================
`ifdef I2S_AUDIO
i2s #(.AUDIO_DW(16)) i2s (
    .reset(1'b0),
    .clk(clk_bus),
    .clk_rate(32'd54_000_000),
    .sclk(I2S_BCK),
    .lrclk(I2S_LRCK),
    .sdata(I2S_DATA),
    .left_chan(audio_l),
    .right_chan(audio_r)
);
`endif

`ifdef DELTASIGMA_AUDIO
// El modulador de dac.vhd quiere la muestra sin signo: se invierte el bit de
// signo (el silencio queda a media escala), como en el port de NewBrain.
dac #(.C_bits(16)) dac_l (
    .clk_i(clk_bus),
    .res_n_i(1'b1),
    .dac_i({~audio_l[15], audio_l[14:0]}),
    .dac_o(AUDIO_L)
);
dac #(.C_bits(16)) dac_r (
    .clk_i(clk_bus),
    .res_n_i(1'b1),
    .dac_i({~audio_r[15], audio_r[14:0]}),
    .dac_o(AUDIO_R)
);
`endif

// ============================================================================
// LED: encendido mientras se carga; parpadeo lento si la CPU esta en HALT;
// parpadeo rapido si hubo error del cargador (FIFO desbordada o escritura a
// una direccion sin dispositivo)
// ============================================================================
logic [25:0] blink;
always_ff @(posedge clk_bus) blink <= blink + 26'd1;
wire led_on = loader_busy
            | ((loader_overflow | loader_timeout) & blink[22])
            | (cpu_halted & blink[25]);
`ifdef CALYPSO
assign LED = {7'b0000000, led_on};
`else
assign LED = ~led_on;
`endif

endmodule

`default_nettype wire
