# Simulacion con Verilator (>= 5.0, con --timing)
#   make          fase 1: carga, SDRAM, video (tb_aleste_core)
#   make fase2    fase 2: el Z80 ejecuta ../tools/diag/DIAG.ROM (tb_fase2) y vuelca
#                 la pantalla en obj2/pantalla.ppm (y .png si hay Python+PIL)
#   make lint     lint del diseno completo
ROOT    := ..
A       := $(ROOT)/aleste-lx/src
FLAGS   := --binary --timing -j 0 -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD \
           -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-INITIALDLY \
           --top-module tb_aleste_core -Mdir obj
SRCS    := $(A)/components/reset/reset_controller.sv \
           $(A)/components/memory/sdram/sdram_wishbone.sv \
           $(ROOT)/rtl/mc6845mod.sv \
           $(A)/components/video/hdmi_scaler/dual_port_ram.sv \
           $(A)/components/video/hdmi_scaler/hdmi_scaler.sv \
           $(ROOT)/rtl/cpc_colors.sv \
           $(A)/components/video/palette/msx_colors.sv \
           $(ROOT)/rtl/color_palette.sv \
           $(A)/components/video/video_buffer/video_buffer.sv \
           $(ROOT)/rtl/pixel_pipeline.sv \
           $(ROOT)/rtl/memory_arbiter.sv \
           $(A)/systems/aleste_video/wb_arbiter.sv \
           $(A)/systems/aleste_video/address_decoder.sv \
           $(A)/components/cpu/tv80/tv80_core.v \
           $(A)/components/cpu/tv80/tv80_reg.v \
           $(A)/components/cpu/tv80/tv80_alu.v \
           $(A)/components/cpu/tv80/tv80_mcode.v \
           $(ROOT)/rtl/z80_system.sv \
           $(A)/components/io/ppi/i8255_wb.sv \
           $(A)/systems/aleste_system/z80_debug.sv \
           $(ROOT)/rtl/mmu_legacy.sv \
           $(A)/systems/aleste_system/system_arbiter.sv \
           $(A)/components/interconnect/wishbone/wb_wdt_simple.sv \
           $(ROOT)/rtl/tv80lx.v $(ROOT)/rtl/mmu_native.sv \
           $(ROOT)/rtl/vga_timing.sv $(ROOT)/rtl/video_ctrl_vga.sv \
           $(ROOT)/rtl/mist_loader.sv $(ROOT)/rtl/cpc/UM6845R.v $(ROOT)/rtl/cpc/cpc_video.sv $(ROOT)/rtl/cpc/kbd_520ex.sv $(ROOT)/rtl/cpc/rtc146818.sv $(ROOT)/rtl/cpc/magic_sound.sv $(ROOT)/rtl/cpc/serial_mouse.sv $(ROOT)/rtl/cpc/kempston_mouse.v $(ROOT)/rtl/cpc/symbiface_mouse.v $(ROOT)/rtl/cpc/multiplay_mouse.v $(ROOT)/rtl/cpc/amx_mouse.v $(ROOT)/rtl/cpc/tzxplayer.sv $(ROOT)/rtl/cpc/u765.sv $(ROOT)/rtl/YM2149.sv $(ROOT)/rtl/aleste_core.sv \
           sdram_model.sv

all: run

obj/Vtb_aleste_core: $(SRCS) tb_aleste_core.sv
	verilator $(FLAGS) $(SRCS) tb_aleste_core.sv

FLAGS2  := $(subst --top-module tb_aleste_core -Mdir obj,--top-module tb_fase2 -Mdir obj2,$(FLAGS))

obj2/Vtb_fase2: $(SRCS) tb_fase2.sv
	verilator $(FLAGS2) $(SRCS) tb_fase2.sv

fase2: obj2/Vtb_fase2
	$(MAKE) -C ../rom
	cp -f $(A)/components/video/palette/*.mem $(ROOT)/rtl/*.mem obj2/ 2>/dev/null; cd obj2 && ./Vtb_fase2 +rom=../../tools/diag/DIAG.ROM
	-python3 -c "from PIL import Image; Image.open('obj2/pantalla.ppm').save('obj2/pantalla.png')" 2>/dev/null

run: obj/Vtb_aleste_core
	cp -f $(A)/components/video/palette/*.mem $(ROOT)/rtl/*.mem obj/ 2>/dev/null; cd obj && ./Vtb_aleste_core $(PLUSARGS)

# make run PLUSARGS=+wbs=/ruta/BARS.WBS   ejecuta ademas un guion real

wave: FLAGS += --trace-fst -DWAVE
wave: run

FLAGS3  := $(subst --top-module tb_aleste_core -Mdir obj,--top-module tb_fase3 -Mdir obj3,$(FLAGS))

obj3/Vtb_fase3: $(SRCS) tb_fase3.sv
	verilator $(FLAGS3) $(SRCS) tb_fase3.sv

# Lo mismo con la SDRAM y el mapa de memoria de la Calypso (8 MB): make obj3c/Vtb_fase3
obj3c/Vtb_fase3: $(SRCS) tb_fase3.sv
	verilator $(subst -Mdir obj3,-Mdir obj3c,$(FLAGS3)) -DCALYPSO $(SRCS) tb_fase3.sv

# Lo mismo con el disco 10 veces mas rapido (solo simulacion): make obj3f/Vtb_fase3
obj3f/Vtb_fase3: $(SRCS) tb_fase3.sv
	verilator $(subst -Mdir obj3,-Mdir obj3f,$(FLAGS3)) -DFDC_CYCLES=385 $(SRCS) tb_fase3.sv

# make fase3 AL512=/ruta/AL512.BIN [PLUSARGS=+ms=1500]
fase3: obj3/Vtb_fase3
	python3 ../tools/make_rom.py $(AL512) -o obj3/ALESTE_CPC.ROM
	cp -f $(A)/components/video/palette/*.mem $(ROOT)/rtl/*.mem obj3/ 2>/dev/null; cd obj3 && ./Vtb_fase3 +rom=ALESTE_CPC.ROM $(PLUSARGS)
	-cd obj3 && for f in cpc_*.ppm; do python3 -c "from PIL import Image; im=Image.open('$$f'); im.resize((1024, 640), Image.NEAREST).save('$${f%.ppm}.png')"; done

clean:
	rm -rf obj obj2 obj3 obj3c obj3f obj4

.PHONY: all run wave clean lint fase2 fase3 fase2

# Lint del diseno completo (top incluido), desde la raiz del repositorio.
# Verilator no admite los tri-estado de user_io.v y data_io.v (SPI_DO): esos
# 4 errores son esperados y Quartus los sintetiza sin problema.
lint:
	cd $(ROOT) && verilator --lint-only --no-timing -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-TIMESCALEMOD \
	  -Wno-PINCONNECTEMPTY -Wno-PINMISSING -DPOSEIDON -DI2S_AUDIO -DUSE_AUDIO_IN \
	  -DNO_DIRECT_UPLOAD -DBIG_OSD --top-module aleste_mist_top -f sim/files.f

.PHONY: lint

# Controlador de disco solo, con una imagen real:
#   make u765 IMG=disco.dsk C=0 H=0 R=1     (guarda el sector en obj4/sector.bin)
obj4/Vtb_u765: $(ROOT)/rtl/cpc/u765.sv tb_u765.sv
	verilator --binary --timing -j 0 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN --top-module tb_u765 -Mdir obj4 $^

u765: obj4/Vtb_u765
	cd obj4 && ./Vtb_u765 +img=$(abspath $(IMG)) +c=$(or $(C),0) +h=$(or $(H),0) +r=$(or $(R),1) +out=sector.bin $(PLUSARGS)

.PHONY: u765

# Copia aparte del banco de la fase 3 (para no tocar el binario de una simulacion en marcha)
obj3t/Vtb_fase3: $(SRCS) tb_fase3.sv
	verilator $(subst -Mdir obj3,-Mdir obj3t,$(FLAGS3)) $(SRCS) tb_fase3.sv
