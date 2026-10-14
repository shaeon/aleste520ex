# Restricciones de la SiDi (CLOCK_27) para el Aleste 520EX
# ============================================================================
#
#   clk[0] 108 MHz  clk_system (SDRAM)
#   clk[1]  54 MHz  clk_bus
#   clk[2]  27 MHz  clk_pixel
#
# Los tres salen del mismo PLL y en fase. NO se declaran asincronos entre si:
# el Aleste LX pasa datos entre ellos sin sincronizadores, contando con que
# son multiplos exactos, y TimeQuest tiene que analizar esas rutas.
# ============================================================================

create_clock -name "CLOCK_27" -period 37.037 [get_ports {CLOCK_27}]
create_clock -name {SPI_SCK}  -period 41.666 [get_ports {SPI_SCK}]

derive_pll_clocks -create_base_clocks

set clk_sys {pll|altpll_component|auto_generated|pll1|clk[0]}

# SDRAM_CLK sale de un registro DDR del pin (sdramclk_ddr en el top) que da
# clk_system invertido: el reloj de la SDRAM va medio periodo por detras.
create_generated_clock -name sdram_clk -source [get_pins $clk_sys] -invert [get_ports {SDRAM_CLK}]

derive_clock_uncertainty

# Tres grupos asincronos: SPI del firmware, PLL principal (108/54/27 MHz y el
# reloj de la SDRAM) y PLL de video (80 MHz, rtl/cpc/cpc_video.sv). Todos los
# cruces entre grupos pasan por sincronizadores o handshakes; los datos que
# cruzan estan quietos varios ciclos.
set_clock_groups -asynchronous \
    -group [get_clocks {SPI_SCK}] \
    -group [get_clocks {pll|altpll_component|auto_generated|pll1|clk[*] sdram_clk}] \
    -group [get_clocks {pll_video|altpll_component|auto_generated|pll1|clk[0]}]

# ----------------------------------------------------------------------------
# SDRAM. Retardos del chip (los mismos que en NewBrain para esta placa):
#   entrada: tAC 6 ns + rutado (max), tOH (min)
#   salida:  tIS 1,5 ns (setup), tIH 0,8 ns (hold)
# ----------------------------------------------------------------------------
set_input_delay  -clock [get_clocks {sdram_clk}] -max 6.4  [get_ports {SDRAM_DQ[*]}]
set_input_delay  -clock [get_clocks {sdram_clk}] -min 3.2  [get_ports {SDRAM_DQ[*]}]

set_output_delay -clock [get_clocks {sdram_clk}] -max 1.5  [get_ports {SDRAM_DQ[*] SDRAM_A[*] SDRAM_BA[*] SDRAM_DQML SDRAM_DQMH SDRAM_n* SDRAM_CKE}]
set_output_delay -clock [get_clocks {sdram_clk}] -min -0.8 [get_ports {SDRAM_DQ[*] SDRAM_A[*] SDRAM_BA[*] SDRAM_DQML SDRAM_DQMH SDRAM_n* SDRAM_CKE}]

# Lectura: sdram_wishbone saca READ en el flanco N de clk_system y recoge el
# dato en N+3 (ack0 en el ciclo T_RCD+CAS, muestreado en el siguiente). Con
# CL2, la palabra la lanza el flanco de sdram_clk que cae en N+2,5, asi que la
# captura esta 1,5 periodos despues del lanzamiento, no medio periodo (que es
# lo que TimeQuest supondria por defecto). Ver doc/04-fase1-video.md.
set_multicycle_path -from [get_clocks {sdram_clk}] -to [get_clocks $clk_sys] -setup -end 2
set_multicycle_path -from [get_clocks {sdram_clk}] -to [get_clocks $clk_sys] -hold  -end 1

# ----------------------------------------------------------------------------
# Salidas lentas o asincronas: no hace falta analizarlas
# ----------------------------------------------------------------------------
set_false_path -to [get_ports {VGA_* LED AUDIO_L AUDIO_R}]
set_false_path -from [get_ports {AUDIO_IN}]
