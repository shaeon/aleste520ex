// PLL de la Calypso: CLK12M (12 MHz) -> c0 108 MHz (x9), c1 54 MHz (x9/2),
// c2 27 MHz (x9/4), las tres en fase.
//
//   c0  108 MHz  clk_system: SDRAM, arbitro de memoria, buffer de video.
//                Tambien sale invertido por SDRAM_CLK (altddio_out del top).
//   c1   54 MHz  clk_bus: Wishbone, user_io, data_io, cargador
//   c2   27 MHz  clk_pixel: barrido 720x480 y salida VGA
//
// El Aleste LX trata estos tres relojes como sincronos entre si (hay rutas
// entre ellos sin sincronizadores), asi que tienen que salir del mismo PLL y
// en fase. Si se regenera con el asistente ALTPLL hay que conservar el
// orden c0/c1/c2, que es el que espera el .sdc.
`timescale 1 ps / 1 ps
module pll (
	inclk0,
	c0,
	c1,
	c2,
	locked);

	input	  inclk0;
	output	  c0;
	output	  c1;
	output	  c2;
	output	  locked;

	wire [4:0] sub_wire0;
	wire  sub_wire3;
	wire [0:0] sub_wire6 = 1'h0;
	wire  c0 = sub_wire0[0];
	wire  c1 = sub_wire0[1];
	wire  c2 = sub_wire0[2];
	wire  locked = sub_wire3;
	wire  sub_wire4 = inclk0;
	wire [1:0] sub_wire5 = {sub_wire6, sub_wire4};

	altpll	altpll_component (
				.inclk (sub_wire5),
				.clk (sub_wire0),
				.locked (sub_wire3),
				.activeclock (),
				.areset (1'b0),
				.clkbad (),
				.clkena ({6{1'b1}}),
				.clkloss (),
				.clkswitch (1'b0),
				.configupdate (1'b0),
				.enable0 (),
				.enable1 (),
				.extclk (),
				.extclkena ({4{1'b1}}),
				.fbin (1'b1),
				.fbmimicbidir (),
				.fbout (),
				.fref (),
				.icdrclk (),
				.pfdena (1'b1),
				.phasecounterselect ({4{1'b1}}),
				.phasedone (),
				.phasestep (1'b1),
				.phaseupdown (1'b1),
				.pllena (1'b1),
				.scanaclr (1'b0),
				.scanclk (1'b0),
				.scanclkena (1'b1),
				.scandata (1'b0),
				.scandataout (),
				.scandone (),
				.scanread (1'b0),
				.scanwrite (1'b0),
				.sclkout0 (),
				.sclkout1 (),
				.vcooverrange (),
				.vcounderrange ());
	defparam
		altpll_component.bandwidth_type = "AUTO",
		altpll_component.clk0_divide_by = 1,
		altpll_component.clk0_duty_cycle = 50,
		altpll_component.clk0_multiply_by = 9,
		altpll_component.clk0_phase_shift = "0",
		altpll_component.clk1_divide_by = 2,
		altpll_component.clk1_duty_cycle = 50,
		altpll_component.clk1_multiply_by = 9,
		altpll_component.clk1_phase_shift = "0",
		altpll_component.clk2_divide_by = 4,
		altpll_component.clk2_duty_cycle = 50,
		altpll_component.clk2_multiply_by = 9,
		altpll_component.clk2_phase_shift = "0",
		altpll_component.compensate_clock = "CLK0",
		altpll_component.inclk0_input_frequency = 83333,
		altpll_component.intended_device_family = "Cyclone 10 LP",
		altpll_component.lpm_hint = "CBX_MODULE_PREFIX=pll",
		altpll_component.lpm_type = "altpll",
		altpll_component.operation_mode = "NORMAL",
		altpll_component.pll_type = "AUTO",
		altpll_component.port_activeclock = "PORT_UNUSED",
		altpll_component.port_areset = "PORT_UNUSED",
		altpll_component.port_clkbad0 = "PORT_UNUSED",
		altpll_component.port_clkbad1 = "PORT_UNUSED",
		altpll_component.port_clkloss = "PORT_UNUSED",
		altpll_component.port_clkswitch = "PORT_UNUSED",
		altpll_component.port_configupdate = "PORT_UNUSED",
		altpll_component.port_fbin = "PORT_UNUSED",
		altpll_component.port_inclk0 = "PORT_USED",
		altpll_component.port_inclk1 = "PORT_UNUSED",
		altpll_component.port_locked = "PORT_USED",
		altpll_component.port_pfdena = "PORT_UNUSED",
		altpll_component.port_phasecounterselect = "PORT_UNUSED",
		altpll_component.port_phasedone = "PORT_UNUSED",
		altpll_component.port_phasestep = "PORT_UNUSED",
		altpll_component.port_phaseupdown = "PORT_UNUSED",
		altpll_component.port_pllena = "PORT_UNUSED",
		altpll_component.port_scanaclr = "PORT_UNUSED",
		altpll_component.port_scanclk = "PORT_UNUSED",
		altpll_component.port_scanclkena = "PORT_UNUSED",
		altpll_component.port_scandata = "PORT_UNUSED",
		altpll_component.port_scandataout = "PORT_UNUSED",
		altpll_component.port_scandone = "PORT_UNUSED",
		altpll_component.port_scanread = "PORT_UNUSED",
		altpll_component.port_scanwrite = "PORT_UNUSED",
		altpll_component.port_clk0 = "PORT_USED",
		altpll_component.port_clk1 = "PORT_USED",
		altpll_component.port_clk2 = "PORT_USED",
		altpll_component.port_clk3 = "PORT_UNUSED",
		altpll_component.port_clk4 = "PORT_UNUSED",
		altpll_component.port_clk5 = "PORT_UNUSED",
		altpll_component.port_clkena0 = "PORT_UNUSED",
		altpll_component.port_clkena1 = "PORT_UNUSED",
		altpll_component.port_clkena2 = "PORT_UNUSED",
		altpll_component.port_clkena3 = "PORT_UNUSED",
		altpll_component.port_clkena4 = "PORT_UNUSED",
		altpll_component.port_clkena5 = "PORT_UNUSED",
		altpll_component.port_extclk0 = "PORT_UNUSED",
		altpll_component.port_extclk1 = "PORT_UNUSED",
		altpll_component.port_extclk2 = "PORT_UNUSED",
		altpll_component.port_extclk3 = "PORT_UNUSED",
		altpll_component.self_reset_on_loss_lock = "OFF",
		altpll_component.width_clock = 5;

endmodule
