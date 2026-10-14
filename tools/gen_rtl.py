#!/usr/bin/env python3
"""
gen_rtl.py - Genera en rtl/ las copias PARCHEADAS de ficheros del Aleste LX.

El submodulo aleste-lx no se toca. Los pocos ficheros que hay que cambiar
para las placas MiST se generan desde el original con reemplazos exactos:
si upstream cambia y un reemplazo deja de encajar, el script falla en vez de
producir algo a medias. Despues de actualizar el submodulo:

    python3 tools/gen_rtl.py

  rtl/video_ctrl_vga.sv   video_ctrl.sv con salida VGA (vga_timing) en vez de
                          llhdmi/TMDS, sin clk_270m, clke_i del memory_arbiter
                          a 1 (el original le mete el reloj de 54 MHz como dato;
                          solo decide la fase del ack) y wb_clke_i de la paleta
                          conectado, y config_27mhz.vh copiado dentro (Quartus
                          no lo encontraba por SEARCH_PATH: error 10054).
  rtl/memory_arbiter.sv   sdram_req_o con '<=' en todo el always_ff. El original
                          mezcla '=' y '<=' en la misma variable: Quartus no lo
                          admite (error 10110) y Verilator tampoco. No se lee
                          dentro del bloque, asi que el comportamiento es igual.
  rtl/mc6845mod.sv        (fase 3) Modo CPC: chip select con A14=0 (BCxx-BFxx; el
                          original compara con el bit 14 de 6845h, que es 1, y
                          responderia al Gate Array y a la PPI), direccion de
                          pantalla con RA[2:0] como el CPC (el original usa RA[3:0]
                          y la pantalla de C000 sale de 18000), modos del Gate
                          Array activos en modo CPC y conversion de modo a bpp
                          corregida (0=4bpp, 1=2bpp, 2=1bpp, 3=4bpp).
  rtl/mc6845mod.sv        'localparam' dentro de la lista #(...) -> 'parameter'.
                          Es SystemVerilog-2009 y Quartus Lite no lo admite
                          (error 10170). Se usan en los anchos de los puertos,
                          asi que no se pueden pasar al cuerpo; nadie los
                          sobrescribe, asi que el resultado es el mismo.
  rtl/mmu_native.sv       (fase 2) Dos cambios:
                          1. Direccion MMIO: el original forma
                             {8'hFF, 2'b00, reg_mmio_page[7:0], cpu_a[7:0]}, que
                             son 26 bits truncados a 24: la CPU acaba en
                             FCpppp en vez de FF0000 + pagina*128 + puerto, que
                             es lo que dicen docs/lx_mmu7.md y address_decoder.
                             Sin esto la CPU no llega al CRTC ni a la paleta.
                          2. Las senales 'Основные сигналы' y 'Z80 сигналы' se
                             declaran antes de usarse (Quartus error 10161).
  rtl/cpc_colors.sv       (fase 3) 32 colores hardware del Gate Array (el original
  rtl/cpc_palette_520ex.mem  tiene 27, indexados como las tintas del firmware 0-26,
                          pero el Gate Array recibe el numero hardware 0-31, en
                          otro orden: el fondo azul del CPC salia morado). Tabla
                          de la PROM D62 del 520EX (RFCOLDAT 0x140-0x15F,
                          publicada en Aleste520EX/Documentation/roms-content.txt)
                          decodificada como MAME.
  rtl/z80_system.sv       (fase 3) salida int_ack_o (M1 + IORQ, reconocimiento de
                          interrupcion) para el contador de interrupciones del
                          Gate Array, que la necesita para bajar -INT.
  rtl/tv80lx.v            (fase 2) Dos cambios:
                          1. nxt_rd_n/wr_n/iorq_n/mreq_n declaradas 'wire' pero
                             asignadas en un always @*: es ilegal (Quartus error
                             10137, Verilator PROCASSWIRE). Pasan a 'reg'.
                          2. En las lecturas de E/S el core hace un T2 de mas
                             (espera automatica de E/S), pero tv80lx ya ha
                             soltado RD/IORQ; como di_reg se recoge en cada T2
                             con wait_n=1, se vuelve a recoger con el bus ya
                             vacio (z80_system lo pone a 00) y el IN devuelve
                             00 o el dato segun la fase del reloj. Ahora solo
                             se recoge mientras rd_n esta activo.
  rtl/mmu_legacy.sv       (fase 2) ';;' al final de dos declaraciones: es un
                          elemento vacio del modulo que SystemVerilog admite y
                          Quartus no (error 10170). Se quita el ';' sobrante.
                          (fase 3) Modo CPC del Aleste 520EX:
                          - las escrituras al Gate Array (7Fxx) tambien salen
                            al bus, para que lleguen a la paleta (el original
                            las deja dentro de la MMU y la paleta no cambia)
                          - ROM baja en 400000 (pagina 0 de AL512) y numero de
                            ROM alta recodificado como la PROM D62 del 520EX:
                            7 -> pagina 2 (AMSDOS), 3 -> 3 (SETUP/MSX-DOS),
                            resto -> 1 (BASIC). Ver doc/02-hardware-aleste520ex.md.
                          - peticion al bus combinacional, como mmu_native. El
                            original la registra con el reloj de la CPU y llega
                            tarde: z80_system pone WAIT cuando el Z80 ya ha leido
                            el bus y la CPU recibe 00 (NOP) en cada instruccion.
  rtl/pixel_pipeline.sv   (fase 3) modo 1 del CPC: la tinta es {bit3, bit7} (el bit 7
                          es el bit bajo); el original tenia {bit7, bit3} y cambiaba
                          las tintas 1 y 2 (el texto del BASIC salia cian).
  rtl/YM2149.sv           (fase 3b) AY del modo CPC. 'assign' de ymreg y dout
                          antes de sus declaraciones (Quartus error 10161 en
                          SystemVerilog): se pasan detras. Lectura del registro
                          15 con el puerto B (el original mezcla IOA_in).
  rtl/pixel_pipeline.sv   'logic [7:0] pixel = 0;' sin valor inicial: lo escribe
                          un always_comb y el inicializador cuenta como otro
                          proceso que escribe la misma variable. El case cubre
                          los cuatro modos, asi que no cambia nada.
  rtl/color_palette.sv    'logic x = control_logic[..];' y 'logic yjk_mode = ...'
                          -> 'wire' (Quartus error 10748). Con logic es
                          un valor inicial (IEEE 1800: se evalua una vez), no una
                          asignacion continua: yosys lo acepta como continua, pero
                          otras herramientas dejarian fijos el modo de escritura,
                          el autoincremento y el modificador de la paleta.
"""
import pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
UP   = ROOT / "aleste-lx/src"


def rev():
    try:
        return subprocess.check_output(["git", "-C", str(UP), "rev-parse", "--short", "HEAD"],
                                       text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        pass
    # Copia sin git (zip autonomo): el commit esta apuntado en ORIGEN.txt
    origen = ROOT / "aleste-lx/ORIGEN.txt"
    if origen.exists():
        for line in origen.read_text(encoding="utf-8").splitlines():
            if line.startswith("commit:"):
                return line.split()[1][:7]
    return "?"


def replace_once(text, old, new, what):
    n = text.count(old)
    if n != 1:
        sys.exit(f"ERROR ({what}): se esperaba 1 coincidencia y hay {n}:\n{old}")
    return text.replace(old, new)


def write(dst, src_rel, changes, text):
    header = (
        "// ============================================================================\n"
        "// FICHERO GENERADO por tools/gen_rtl.py - no editar a mano.\n"
        f"// Origen: aleste-lx/src/{src_rel} @ {rev()}\n"
        f"// Cambios: {changes}\n"
        "// ============================================================================\n"
    )
    (ROOT / dst).write_text(header + text, encoding="utf-8")
    print(f"Generado {dst}")


PORTS_HDMI = """    // HDMI Video Output
    output logic        tmds_red,
    output logic        tmds_green, 
    output logic        tmds_blue,
"""
PORTS_VGA = """    // Salida VGA (sustituye a la salida TMDS del original)
    output logic [11:0] vga_rgb,
    output logic        vga_hs,
    output logic        vga_vs,
    output logic        vga_hblank,
    output logic        vga_vblank,
"""

LLHDMI_START = "    llhdmi #("
LLHDMI_END   = "        .o_y(hdmi_y)\n    );\n"
VGA_INST = """    vga_timing #(
        .INPUT_LATENCY(1),
        .H_VISIBLE(HDMI_H_VISIBLE),
        .H_FRONT_PORCH(HDMI_H_FRONT_PORCH),
        .H_SYNC_PULSE(HDMI_H_SYNC_PULSE),
        .H_BACK_PORCH(HDMI_H_BACK_PORCH),
        .V_VISIBLE(HDMI_V_VISIBLE),
        .V_FRONT_PORCH(HDMI_V_FRONT_PORCH),
        .V_SYNC_PULSE(HDMI_V_SYNC_PULSE),
        .V_BACK_PORCH(HDMI_V_BACK_PORCH)
    ) vga (
        .i_pixclk(clk_pixel),
        .i_reset(system_reset),
        .i_rgb(scaler_pixel_o),
        .o_rd(hdmi_rd),
        .o_newline(hdmi_newline),
        .o_newframe(hdmi_newframe),
        .o_x(hdmi_x),
        .o_y(hdmi_y),
        .o_rgb(vga_rgb),
        .o_hs(vga_hs),
        .o_vs(vga_vs),
        .o_hblank(vga_hblank),
        .o_vblank(vga_vblank)
    );
"""

REPLACEMENTS = [
    # fase 3: modo grafico del Gate Array (CPC) hacia el CRTC
    ("        .cfg_cpc_bpp_i('0),\n", "        .cfg_cpc_bpp_i(cfg_cpc_mode_i),\n"),
    ("    // Конфигурационные сигналы\n    input  logic        cfg_native_i\n",
     "    // Конфигурационные сигналы\n    input  logic        cfg_native_i,\n"
     "    input  logic [1:0]  cfg_cpc_mode_i,     // modo del Gate Array (CPC)\n"
     "    output logic        crtc_hsync_o,       // sincronismos del CRTC (interrupciones del Gate Array)\n"
     "    output logic        crtc_vsync_o\n"),
    # nombre del modulo
    ("module video_ctrl #(", "module video_ctrl_vga #("),
    # sin reloj de 270 MHz
    ("    input  logic        clk_270m,        // 270MHz для TMDS\n", ""),
    # puertos de salida
    (PORTS_HDMI, PORTS_VGA),
    # clke_i del arbitro: en el original es el reloj de 54 MHz usado como
    # dato. Solo decide la fase del ack de Wishbone (110 u 011); con un 1 fijo
    # el ack dura igual dos ciclos de 108 MHz y cae en un flanco de 54 MHz.
    ("        .clke_i(clk_bus),\n", "        .clke_i(1'b1),           // MiST: ver tools/gen_rtl.py\n"),
    # puerto de la paleta que el original deja sin conectar (no se usa)
    ("        .wb_clk_i(clk_bus),\n        .cfg_legacy_i(~cfg_native_i),\n\n        // Wishbone interface\n        .wb_adr_i(system2palette_adr),",
     "        .wb_clk_i(clk_bus),\n        .wb_clke_i(1'b0),\n        .cfg_legacy_i(~cfg_native_i),\n\n        // Wishbone interface\n        .wb_adr_i(system2palette_adr),"),
]


def gen_video_ctrl():
    src = "systems/aleste_video/video_ctrl.sv"
    text = (UP / src).read_text(encoding="utf-8")
    for old, new in REPLACEMENTS:
        text = replace_once(text, old, new, "video_ctrl")
    a = text.find(LLHDMI_START)
    b = text.find(LLHDMI_END, a)
    if a < 0 or b < 0 or text.count(LLHDMI_START) != 1:
        sys.exit("ERROR (video_ctrl): no encuentro la instancia de llhdmi")
    text = text[:a] + VGA_INST + text[b + len(LLHDMI_END):]
    # El include se mete dentro del fichero: Quartus no encuentra
    # config_27mhz.vh con SEARCH_PATH desde un .qip (error 10054).
    inc = '`include "config_27mhz.vh"\n'
    cfg = (UP / "systems/aleste_video/config_27mhz.vh").read_text(encoding="utf-8")
    text = replace_once(text, inc,
                        "// ---- config_27mhz.vh (incluido por tools/gen_rtl.py) ----\n"
                        + cfg.rstrip() + "\n// ---- fin de config_27mhz.vh ----\n", "video_ctrl include")
    text = replace_once(text, "endmodule", "    assign crtc_hsync_o = crtc_hsync;\n    assign crtc_vsync_o = crtc_vsync;\n\nendmodule", "video_ctrl sync")
    # Puerto de video de la SDRAM compartido con el video CPC (rtl/cpc/cpc_video.sv):
    # con ext_vid_sel=1 lo usa el, con la misma prioridad que el video del LX.
    text = replace_once(text,
        "        .video_addr_i(crtc2mem_addr),\n        .video_req_i(vbuf_req),\n        .video_data_o(vbuf_data),\n        .video_ack0_o(vbuf_ack0),\n        .video_ack1_o(vbuf_ack1),",
        "        .video_addr_i(ext_vid_sel ? ext_vid_addr : crtc2mem_addr),   // video CPC - tools/gen_rtl.py\n"
        "        .video_req_i(ext_vid_sel ? ext_vid_req : vbuf_req),\n"
        "        .video_data_o(vid_mem_data),\n"
        "        .video_ack0_o(vid_mem_ack0),\n"
        "        .video_ack1_o(vid_mem_ack1),",
        "video_ctrl puerto de video")
    text = replace_once(text,
        "    input  logic        cfg_native_i,\n",
        "    input  logic        cfg_native_i,\n"
        "    // Puerto de video de la SDRAM para el video CPC (clk_system) - tools/gen_rtl.py\n"
        "    input  logic        ext_vid_sel,\n"
        "    input  logic [23:0] ext_vid_addr,\n"
        "    input  logic        ext_vid_req,\n"
        "    output logic        ext_vid_ack0,\n"
        "    output logic [15:0] ext_vid_data,\n",
        "video_ctrl puertos ext")
    text = replace_once(text,
        "    // ===========================================\n    // Memory Arbiter (Video + System WB)\n",
        "    logic [15:0] vid_mem_data;\n"
        "    logic        vid_mem_ack0, vid_mem_ack1;\n"
        "    assign vbuf_data    = vid_mem_data;\n"
        "    assign vbuf_ack0    = vid_mem_ack0 & ~ext_vid_sel;\n"
        "    assign vbuf_ack1    = vid_mem_ack1 & ~ext_vid_sel;\n"
        "    assign ext_vid_data = vid_mem_data;\n"
        "    assign ext_vid_ack0 = vid_mem_ack0 & ext_vid_sel;\n\n"
        "    // ===========================================\n    // Memory Arbiter (Video + System WB)\n",
        "video_ctrl senales ext")
    write("rtl/video_ctrl_vga.sv", src,
          "llhdmi -> vga_timing (salida VGA), sin clk_270m, clke_i del memory_arbiter a 1, wb_clke_i de la paleta conectado, config_27mhz.vh incluido en linea.",
          text)


CALYPSO_DECL = "`ifdef CALYPSO\nlogic [22:0] calypso_byte;                 // direccion de bytes dentro de los 8 MB\nalways_comb begin\n    case (saved_addr[23:22])\n        2'd0: calypso_byte = {2'b00,  saved_addr[20:0]};     // RAM       000000h, 2 MB\n        2'd1: calypso_byte = {3'b010, saved_addr[19:0]};     // ROM CPC   200000h, 1 MB\n        2'd3: calypso_byte = {3'b011, saved_addr[19:0]};     // nativo    300000h, 1 MB\n        default: calypso_byte = {1'b1, saved_addr[21:0]};    // cinta     400000h, 4 MB\n    endcase\nend\n// palabra de 16 bits: banco (2) + fila (12) + columna (8), con la misma\n// disposicion que el original: fila con los bits bajos, columna con los altos\nwire [21:0] calypso_word = {calypso_byte[22:21], calypso_byte[13:2], calypso_byte[20:14], calypso_byte[1]};\n`endif\n"
CALYPSO_OLD_ADDR = "        sdram_addr_o = {\n            saved_addr[23:22],                     // BANK 2 bits \n            1'b0, saved_addr[13:2],                // ROW 13 bits (half of memory is unused)\n            saved_addr[21:14], saved_addr[1]      // COL  9 bits (сохраняем для burst)\n        };\n"
CALYPSO_NEW_ADDR = "`ifdef CALYPSO\n        // Calypso: SDRAM de 8 MB (4096 filas x 256 columnas x 4 bancos). Las\n        // cuatro regiones del core (bits 23-22 de la direccion de bytes) se\n        // recolocan en ventanas dentro de los 8 MB:\n        //   region 0, RAM (1 MB usado)          -> 2 MB en 000000h\n        //   region 1, ROM del modo CPC (64 KB)  -> 1 MB en 200000h\n        //   region 3, arranque nativo (16 KB)   -> 1 MB en 300000h\n        //   region 2, cinta (hasta 4 MB)        -> 4 MB en 400000h\n        // (en modo nativo, mas de 1-2 MB por region se repetiria)\n        sdram_addr_o = {2'b00, calypso_word};\n`else\n        sdram_addr_o = {\n            saved_addr[23:22],                     // BANK 2 bits \n            1'b0, saved_addr[13:2],                // ROW 13 bits (half of memory is unused)\n            saved_addr[21:14], saved_addr[1]      // COL  9 bits (сохраняем для burst)\n        };\n`endif\n"


def gen_memory_arbiter():
    src = "systems/aleste_video/memory_arbiter.sv"
    out, n = [], 0
    for line in (UP / src).read_text(encoding="utf-8").splitlines(keepends=True):
        code, sep, comment = line.partition("//")
        new = re.sub(r"\bsdram_req_o\s*=\s*", "sdram_req_o <= ", code)
        n += new != code
        out.append(new + sep + comment)
    if n != 7:
        sys.exit(f"ERROR (memory_arbiter): se esperaban 7 asignaciones bloqueantes a sdram_req_o y hay {n}")
    text = "".join(out)
    # wb_enabled (proteccion contra atender dos veces la misma peticion) se
    # desactivaba con sdram_ack1, despues de haber contestado al maestro. Si al
    # maestro le sigue otro sin pausa (el cargador o la DMA de la MagicSound y
    # luego la CPU), el unico ciclo sin stb llega antes de ack1, la proteccion se
    # reactiva, ack1 la vuelve a quitar y la peticion de la CPU (stb mantenido)
    # no se atiende nunca: la cortaba el watchdog con error. Se desactiva al
    # programar la respuesta (sdram_ack0), asi el ciclo libre posterior la
    # reactiva siempre.
    text = replace_once(text,
        "                    wb_ack_ff <= clke_i ? 3'b110 : 3'b011;    \n",
        "                    wb_ack_ff <= clke_i ? 3'b110 : 3'b011;    \n"
        "                    wb_enabled <= '0;  // antes de contestar: ver tools/gen_rtl.py\n",
        "memory_arbiter wb_enabled en ack0")
    text = replace_once(text,
        "                    wb_enabled <= '0;  // Disable to prevent second call\n",
        "                    // (wb_enabled ya se quito en ack0 - tools/gen_rtl.py)\n",
        "memory_arbiter wb_enabled en ack1")
    # Calypso (macro CALYPSO): SDRAM de 8 MB; las cuatro regiones del core se
    # recolocan en ventanas dentro de los 8 MB (ver README.md, apartado Calypso)
    text = replace_once(text, "logic [23:0] saved_addr;\n",
        "logic [23:0] saved_addr;\n" + CALYPSO_DECL, "memory_arbiter Calypso (declaracion)")
    text = replace_once(text, CALYPSO_OLD_ADDR, CALYPSO_NEW_ADDR, "memory_arbiter Calypso (direccion)")
    write("rtl/memory_arbiter.sv", src, "sdram_req_o con '<=' en todo el always_ff (Quartus error 10110); wb_enabled se quita al contestar (ack0), no en ack1; Calypso: mapa de memoria en 8 MB.", text)


def gen_color_palette():
    src = "components/video/palette/color_palette.sv"
    text = (UP / src).read_text(encoding="utf-8")
    for name in ("modifier_enabled", "modifier_is_xor", "auto_increment", "[1:0] palette_write_mode", "yjk_mode"):
        pat = re.compile(r"^logic(\s+" + re.escape(name) + r"\s*=)", re.M)
        text, n = pat.subn(r"wire\1", text)
        if n != 1:
            sys.exit(f"ERROR (color_palette): no encuentro 'logic {name} ='")
    write("rtl/color_palette.sv", src,
          "senales derivadas de control_logic declaradas wire (asignacion continua) en vez de logic (valor inicial).",
          text)


def gen_mc6845mod():
    src = "components/video/mc6845mod/mc6845mod.sv"
    text = (UP / src).read_text(encoding="utf-8")
    text = replace_once(text,
        "assign legacy_cs = cfg_legacy_i && wb_tag_i[2] && (wb_adr_i[14] == WB_ADDRESS[14]);",
        "assign legacy_cs = cfg_legacy_i && wb_tag_i[2] && (wb_adr_i[14] == 1'b0);  // CPC: BCxx-BFxx (A14=0) - tools/gen_rtl.py",
        "mc6845mod legacy_cs")
    text = replace_once(text,
        "crtc_ext_addr_o = {reg_high_address, crtc_ma_addr[13:12], crtc_ra_o[3:0], crtc_ma_addr[9:0], 1'b0};",
        "crtc_ext_addr_o = {reg_high_address, crtc_ma_addr[13:12], crtc_ra_o[2:0], crtc_ma_addr[9:0], 1'b0};  // CPC: RA[2:0] - tools/gen_rtl.py",
        "mc6845mod cpc addr")
    text = replace_once(text,
        "wire       use_cpc_modes   = reg_video_control[5];",
        "wire       use_cpc_modes   = reg_video_control[5] | cfg_legacy_i;  // modo CPC: modos del Gate Array - tools/gen_rtl.py",
        "mc6845mod use_cpc_modes")
    text = replace_once(text,
        "assign cfg_bpp_o= use_cpc_modes ? ~cfg_cpc_bpp_i : bpp_mode;",
        "assign cfg_bpp_o= use_cpc_modes ? ((cfg_cpc_bpp_i == 2'd1) ? 2'b01 : (cfg_cpc_bpp_i == 2'd2) ? 2'b00 : 2'b10) : bpp_mode;  // CPC 0=4bpp 1=2bpp 2=1bpp 3=4bpp - tools/gen_rtl.py",
        "mc6845mod bpp")
    for name in ("H_PIX_COUNTER_WIDTH", "V_PIX_COUNTER_WIDTH"):
        text, n = re.subn(r"^(\s*)localparam(\s+" + name + r"\s*=)", r"\1parameter\2", text, flags=re.M)
        if n != 1:
            sys.exit(f"ERROR (mc6845mod): no encuentro 'localparam {name}' en la lista de parametros")
    write("rtl/mc6845mod.sv", src,
          "localparam en la lista de parametros -> parameter (Quartus error 10170).", text)


def gen_pixel_pipeline():
    src = "components/video/pixel_pipeline/pixel_pipeline.sv"
    text = replace_once((UP / src).read_text(encoding="utf-8"),
                        "logic [7:0] pixel = 0;", "logic [7:0] pixel;", "pixel_pipeline")
    # CPC modo 1: tinta = {bit3, bit7} (bit 7 es el bit bajo, como el modo 0
    # de este mismo fichero). El original pone {bit7, bit3}: tintas 1 y 2 cambiadas.
    text = replace_once(text, "pixel = {6'b0, shift_reg[7], shift_reg[3]};",
                        "pixel = {6'b0, shift_reg[3], shift_reg[7]};  // CPC: bit 7 = bit bajo de la tinta - tools/gen_rtl.py",
                        "pixel_pipeline modo 1")
    write("rtl/pixel_pipeline.sv", src,
          "'pixel' sin valor inicial (la escribe un always_comb); orden de bits del modo 1 del CPC.", text)


def gen_mmu_native():
    src = "components/memory/mmu/mmu_native.sv"
    text = (UP / src).read_text(encoding="utf-8")
    # 1. direccion MMIO
    text = replace_once(text,
        "m_wb_adr_o = {8'hFF, 2'b00, reg_mmio_page[7:0], cpu_a[7:0]};",
        "m_wb_adr_o = {8'hFF, 2'b00, reg_mmio_page[6:0], cpu_a[6:0]};  // FF0000 + pagina*128 + puerto (tools/gen_rtl.py)",
        "mmu_native MMIO")
    # 2. mover declaraciones antes de su primer uso
    start = "    // =========================================================================\n    // Основные сигналы"
    end   = "    // For memory acces the page selected by A[15:14]"
    target = "    wire addr_is_mmio_space = !cpu_a[7];"
    a = text.find(start); b = text.find(end)
    if a < 0 or b < 0 or a > b or text.count(start) != 1 or text.count(target) != 1:
        sys.exit("ERROR (mmu_native): no encuentro los bloques de senales a mover")
    block = text[a:b]
    text = text[:a] + text[b:]
    text = replace_once(text, target, block + "\n" + target, "mmu_native mover")
    # Igual que en mmu_legacy: el INTA (M1 + IORQ sin RD ni WR) no es E/S.
    text = replace_once(text, "    wire is_io_access  = ~cpu_iorq_n;",
        "    wire is_io_access  = ~cpu_iorq_n & (~cpu_rd_n | ~cpu_wr_n);  // E/S (no INTA) - tools/gen_rtl.py",
        "mmu_native is_io_access")
    write("rtl/mmu_native.sv", src,
          "direccion MMIO FF0000+pagina*128+puerto; senales declaradas antes de usarse (Quartus 10161).", text)


def gen_tv80lx():
    src = "components/cpu/tv80/tv80lx.v"
    text = (UP / src).read_text(encoding="utf-8")
    for n in ("nxt_rd_n", "nxt_wr_n", "nxt_iorq_n", "nxt_mreq_n"):
        text, k = re.subn(r"^(\s*)wire(\s+" + n + r"\s*;)", r"\1reg \2", text, flags=re.M)
        if k != 1:
            sys.exit(f"ERROR (tv80lx): no encuentro 'wire {n};'")
    text = replace_once(text,
        "if (tstate[2] && wait_n && !write && !no_read)",
        "if (tstate[2] && wait_n && !write && !no_read && !rd_n)  // solo con RD activo (tools/gen_rtl.py)",
        "tv80lx di_reg")
    write("rtl/tv80lx.v", src,
          "nxt_* de wire a reg (Quartus error 10137); di_reg solo se recoge con rd_n activo (lecturas de E/S).", text)


def gen_mmu_legacy():
    src = "components/memory/mmu/mmu_legacy.sv"
    text = (UP / src).read_text(encoding="utf-8")
    for line in ("wire is_io_write   = is_io_access & ~cpu_wr_n;;", "wire is_io_read    = is_io_access &  cpu_wr_n;;"):
        text = replace_once(text, line, line[:-1], "mmu_legacy")
    text = replace_once(text, "wire is_internal_cs = (is_7fxx_cs | is_dfxx_cs);",
        "wire is_internal_cs = is_dfxx_cs;   // 7Fxx tambien sale al bus (paleta) - tools/gen_rtl.py", "mmu_legacy 7Fxx")
    text = replace_once(text, "localparam LOWER_ROM_BANK = 8'hFC;",
        "localparam LOWER_ROM_BANK = 8'h00;   // 520EX: ROM baja = pagina 0 de AL512 en 400000 - tools/gen_rtl.py", "mmu_legacy lower")
    text = replace_once(text, "reg_upper_rom <= cpu_din;        // Upper ROM bank select",
        "reg_upper_rom <= (cpu_din == 8'd7) ? 8'd2 : (cpu_din == 8'd3) ? 8'd3 : 8'd1;  // PROM D62 del 520EX - tools/gen_rtl.py",
        "mmu_legacy D62")
    # Peticion al bus combinacional, como mmu_native. El original la registra
    # con clke: llega un ciclo de CPU tarde, z80_system activa WAIT cuando el
    # Z80 ya ha muestreado y la CPU lee 00 (NOP) en cada instruccion.
    a = text.find("    // WISHBONE MASTER INTERFACE CONTROL")
    b = text.find("    // CPU DATA READING")
    if a < 0 or b < 0 or a > b:
        sys.exit("ERROR (mmu_legacy): no encuentro el bloque del maestro Wishbone")
    a = text.rfind("\n", 0, text.rfind("\n", 0, a)) + 1      # incluye la linea // ==== anterior
    b = text.rfind("\n", 0, text.rfind("\n", 0, b)) + 1
    comb = (
        "    // =========================================================================\n"
        "    // WISHBONE MASTER INTERFACE (combinacional, como mmu_native - tools/gen_rtl.py)\n"
        "    // =========================================================================\n"
        "    // z80_system registra la direccion al empezar el ciclo y mantiene WAIT\n"
        "    // hasta el ack; aqui solo se dice si hay acceso y a donde.\n"
        "    always_comb begin\n"
        "        m_wb_cyc_o = is_mem_access | is_external_io_acc;\n"
        "        m_wb_stb_o = is_mem_access | is_external_io_acc;\n"
        "        m_wb_we_o  = is_mem_write | (is_io_access & ~cpu_wr_n);\n"
        "        m_wb_adr_o = physical_address;\n"
        "        m_wb_dat_o = cpu_din;\n"
        "    end\n"
        "    assign wb_busy = 1'b0;\n\n")
    text = text[:a] + comb + text[b:]
    # E/S solo con IORQ y ademas RD o WR, como en el bus del Z80. El original
    # toma cualquier ciclo con IORQ: el reconocimiento de interrupcion (INTA:
    # M1 + IORQ, sin RD ni WR) salia al bus como una lectura en la direccion
    # del PC. Con PC=C907 eso es el registro de datos del 765 para la
    # decodificacion del CPC (A10=0, A8=1, A7=0, A0=1): se comia ST0 y AMSDOS
    # daba por mala cada lectura que acababa justo antes de una interrupcion.
    text = replace_once(text, "    wire is_io_access  = legacy_mode_i & ~cpu_iorq_n;    // I/O access active",
        "    wire is_io_access  = legacy_mode_i & ~cpu_iorq_n & (~cpu_rd_n | ~cpu_wr_n);  // E/S (no INTA) - tools/gen_rtl.py",
        "mmu_legacy is_io_access")
    # (fase 3d) Modo Aleste: mapper MSX y paginas unificadas.
    #  - El Gate Array del 520EX se decodifica solo con A15 (CPCWiki): las
    #    escrituras con D7..6=11 a 7Cxx-7Fxx son, con MAPMOD (FABF D2), el
    #    mapper MSX: registro = A9..A8 (cuarto del Z80), pagina = D5..D0.
    #  - Toda la RAM son paginas de 16 KB en p*16K (0..63): 0-3 la RAM base y
    #    4-7... la ampliacion. Las configuraciones del CPC usan las mismas
    #    paginas (banco b -> paginas 4+4b..7+4b), como hace la PROM MAPPER del
    #    520EX; asi CPC y mapper ven la misma memoria.
    text = replace_once(text, "    input  logic        legacy_mode_i,            // Legacy mode active\n",
        "    input  logic        legacy_mode_i,            // Legacy mode active\n"
        "    input  logic        mapmod_i,                 // 520EX: FABF D2, mapper MSX - tools/gen_rtl.py\n",
        "mmu_legacy mapmod port")
    text = replace_once(text, "    wire is_7fxx_cs = (cpu_a[15:8] == 8'h7F);                   // Gate Array select (7Fxxh)",
        "    wire is_7fxx_cs = ~cpu_a[15];                               // Gate Array del 520EX: solo A15 - tools/gen_rtl.py",
        "mmu_legacy GA A15")
    text = replace_once(text, "            reg_upper_rom  <= 8'h00;              // Default upper ROM bank 0\n",
        "            reg_upper_rom  <= 8'h00;              // Default upper ROM bank 0\n"
        "            mapper_reg[0]  <= 6'd0; mapper_reg[1] <= 6'd1; mapper_reg[2] <= 6'd2; mapper_reg[3] <= 6'd3;\n",
        "mmu_legacy mapper reset")
    text = replace_once(text, "                    2'b11: reg_mmr <= cpu_din;   // MMR write (Memory mapping)",
        "                    2'b11: if (mapmod_i) mapper_reg[cpu_a[9:8]] <= cpu_din[5:0];   // mapper MSX - tools/gen_rtl.py\n"
        "                           else          reg_mmr <= cpu_din;   // MMR write (Memory mapping)",
        "mmu_legacy mapper write")
    text = replace_once(text, '    logic [7:0] reg_upper_rom;                    // Upper ROM selection registe           ' + "\n",
        '    logic [7:0] reg_upper_rom;                    // Upper ROM selection registe           ' + "\n    logic [5:0]  mapper_reg [0:3];          // mapper MSX (520EX) - tools/gen_rtl.py\n",
        "mmu_legacy mapper decl")
    text = replace_once(text,
        "            if (ram_page_num[2] == 0) begin\n"
        "                // standart\n"
        "                //                         2bits      3bits    3bits       16bits\n"
        "                ram_physical_address = {CPC_RAM_SLOT, 3'b000, 3'b000,   cpu_a[15:0]};\n"
        "            end else begin\n"
        "                // expanded\n"
        "                //                         2bits      3bits    3bits        2bits           14bits\n"
        "                ram_physical_address = {CPC_RAM_SLOT, 3'b010, rmr_bank, ram_page_num[1:0], cpu_a[13:0]};\n"
        "            end",
        "            if (mapmod_i) begin\n"
        "                // mapper MSX: pagina del cuarto del Z80 (p * 16K) - tools/gen_rtl.py\n"
        "                ram_physical_address = {CPC_RAM_SLOT, 2'b00, mapper_reg[cpu_a[15:14]], cpu_a[13:0]};\n"
        "            end else if (ram_page_num[2] == 0) begin\n"
        "                // RAM base: paginas 0-3\n"
        "                ram_physical_address = {CPC_RAM_SLOT, 6'b000000, cpu_a[15:0]};\n"
        "            end else begin\n"
        "                // ampliacion: banco b -> paginas 4+4b..7+4b (como la PROM MAPPER del 520EX)\n"
        "                ram_physical_address = {CPC_RAM_SLOT, 2'b00, ({1'b0, rmr_bank} + 4'd1), ram_page_num[1:0], cpu_a[13:0]};\n"
        "            end",
        "mmu_legacy direccion RAM")
    write("rtl/mmu_legacy.sv", src,
          "';;' -> ';'; 7Fxx tambien al bus; ROMs del 520EX (ROM baja en 400000, recodificacion D62); "
          "peticion al bus combinacional como mmu_native.", text)


def gen_z80_system():
    src = "systems/aleste_system/z80_system.sv"
    text = (UP / src).read_text(encoding="utf-8")
    text = replace_once(text, "    input  logic        int_req_i,",
        "    input  logic        int_req_i,\n    output logic        int_ack_o,          // M1 + IORQ: reconocimiento de INT - tools/gen_rtl.py",
        "z80_system port")
    text = replace_once(text, "    assign z80_int_n = ~int_req_i;",
        "    assign z80_int_n = ~int_req_i;\n    assign int_ack_o = ~z80_m1_n & ~z80_iorq_n;", "z80_system ack")
    # Reloj de la CPU a 4 MHz exactos en modo CPC (como el 520EX en modo
    # AMSTRAD). El original saca un cke cada (conf+1) ciclos de clk_i: con el
    # valor de reset (2) el Z80 va a 18 MHz, y todo lo que el firmware
    # temporiza con bucles (AMSDOS: tiempo de paso del cabezal) se acorta.
    text = replace_once(text, "    input  logic        int_req_i,\n",
        "    input  logic        int_req_i,\n"
        "    input  logic        cpu_4mhz_i,         // 1: Z80 a 4 MHz (modo CPC) - tools/gen_rtl.py\n"
        "    input  logic [1:0]  cpu_turbo_i,        // modo CPC: 0 4 MHz, 1 8 MHz (turbo del 520EX), 2-3 16 MHz\n",
        "z80_system cpu_4mhz port")
    old_div = """            z80_cke <= 0;
            if (z80_clock_divider == '0) begin
                z80_clock_divider <= z80_clock_conf;
                z80_cke <= 1'b1;
            end else begin 
                z80_clock_divider <= z80_clock_divider - 1;
            end"""
    new_div = """            z80_cke <= 0;
            if (cpu_4mhz_i) begin
                // acumulador de fase: 4, 8 o 16 de cada 54 ciclos de clk_i (54 MHz):
                // 4 MHz como el 520EX, 8 MHz como su modo turbo, o 16 MHz - tools/gen_rtl.py
                if (z80_clock_phase + z80_clock_step >= 7'd54) begin
                    z80_clock_phase <= z80_clock_phase + z80_clock_step - 7'd54;
                    z80_cke <= 1'b1;
                end else begin
                    z80_clock_phase <= z80_clock_phase + z80_clock_step;
                end
            end else if (z80_clock_divider == '0) begin
                z80_clock_divider <= z80_clock_conf;
                z80_cke <= 1'b1;
            end else begin 
                z80_clock_divider <= z80_clock_divider - 1;
            end"""
    text = replace_once(text, old_div, new_div, "z80_system divisor")
    text = replace_once(text, "    logic z80_cke;\n", "    logic z80_cke;\n    logic [6:0] z80_clock_phase = '0;\n"
        "    wire  [6:0] z80_clock_step = (cpu_turbo_i == 2'd0) ? 7'd4 : (cpu_turbo_i == 2'd1) ? 7'd8 : 7'd16;\n", "z80_system fase")
    # (fase 3d) MAPMOD del 520EX (FABF D2) hasta la MMU legacy
    text = replace_once(text, "    input  logic        int_req_i,\n",
        "    input  logic        int_req_i,\n    input  logic        mapmod_i,           // 520EX: FABF D2 - tools/gen_rtl.py\n",
        "z80_system mapmod port")
    text = replace_once(text, "        .legacy_mode_i(~native_mode),\n",
        "        .legacy_mode_i(~native_mode),\n        .mapmod_i(mapmod_i),\n", "z80_system mapmod conn")
    write("rtl/z80_system.sv", src, "salida int_ack_o (M1+IORQ) para las interrupciones del Gate Array.", text)


# PROM D62 (RFCOLDAT) 0x140-0x15F: color hardware 0-31 -> {b[1:0], g[1:0], r[1:0]}
D62_COLORS = [0x15, 0x15, 0x1C, 0x1F, 0x10, 0x13, 0x14, 0x17, 0x13, 0x1F, 0x0F, 0x3F, 0x03, 0x33, 0x07, 0x37,
              0x10, 0x1C, 0x0C, 0x3C, 0x00, 0x30, 0x04, 0x34, 0x11, 0x1D, 0x0D, 0x3D, 0x01, 0x31, 0x05, 0x35]


def gen_cpc_colors():
    src = "components/video/palette/cpc_colors.sv"
    text = (UP / src).read_text(encoding="utf-8")
    text = replace_once(text, "reg [11:0] cpc_hw_to_rgb [0:26];", "reg [11:0] cpc_hw_to_rgb [0:31];", "cpc_colors size")
    text = replace_once(text, '$readmemh("cpc_palette.mem", cpc_hw_to_rgb);',
                        '$readmemh("cpc_palette_520ex.mem", cpc_hw_to_rgb);  // tools/gen_rtl.py', "cpc_colors file")
    text = replace_once(text, "if (hw_register <= 26)", "if (1'b1)  // 32 colores hardware", "cpc_colors range")
    write("rtl/cpc_colors.sv", src, "32 colores hardware del Gate Array, tabla del 520EX (cpc_palette_520ex.mem).", text)
    lv = [0x0, 0x5, 0xA, 0xF]
    lines = ["// Colores hardware del Gate Array 0-31 del Aleste 520EX, R4G4B4. GENERADO por tools/gen_rtl.py",
             "// PROM D62 RFCOLDAT 0x140-0x15F (Aleste520EX/Documentation/roms-content.txt); r=bits 1..0, g=3..2, b=5..4"]
    for i, v in enumerate(D62_COLORS):
        lines.append(f"{lv[v & 3]:x}{lv[(v >> 2) & 3]:x}{lv[(v >> 4) & 3]:x}  // {i:2d}")
    (ROOT / "rtl/cpc_palette_520ex.mem").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("Generado rtl/cpc_palette_520ex.mem")


def gen_ym2149():
    src = "components/sound/ym2149/YM2149.sv"
    text = (UP / src).read_text(encoding="utf-8")
    io = "assign IOA_out = ymreg[14];\nassign IOB_out = ymreg[15];\n"
    text = replace_once(text, io, "", "ym2149 assign IO")
    act = "assign ACTIVE  = ~ymreg[7][5:0];\n"
    text = replace_once(text, act, "", "ym2149 assign ACTIVE")
    io = act + io
    text = replace_once(text, "reg [7:0] ymreg[16];\n", "reg [7:0] ymreg[16];\n" + io, "ym2149 ymreg")
    text = replace_once(text, "assign DO = dout;\nreg [7:0] dout;\n", "reg [7:0] dout;\nassign DO = dout;\n", "ym2149 dout")
    text = replace_once(text, "15: dout = ymreg[7][7] ? ymreg[15] & IOA_in : IOB_in;",
                        "15: dout = ymreg[7][7] ? ymreg[15] & IOB_in : IOB_in;   // tools/gen_rtl.py", "ym2149 reg 15")
    write("rtl/YM2149.sv", src, "assign de ymreg/dout tras declararlos (Quartus 10161); registro 15 con IOB_in.", text)


if __name__ == "__main__":
    gen_video_ctrl()
    gen_memory_arbiter()
    gen_color_palette()
    gen_mc6845mod()
    gen_pixel_pipeline()
    gen_mmu_native()
    gen_tv80lx()
    gen_mmu_legacy()
    gen_ym2149()
    gen_z80_system()
    gen_cpc_colors()
