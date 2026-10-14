#!/usr/bin/env python3
"""
gen_font.py - Saca de la fuente de la BIOS del Aleste LX los caracteres
0x20-0x5F (espacio, signos, cifras y mayusculas) y los escribe como include
de pasmo para la ROM de diagnostico.

Uso: python3 tools/gen_font.py   ->  tools/diag/font.inc
"""
import pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "aleste-lx/firmware/bios/src/fonts/font_win1252.asm"
DST = ROOT / "tools/diag/font.inc"

data = [int(x, 16)
        for line in SRC.read_text(encoding="utf-8").splitlines() if line.strip().lower().startswith("defb")
        for x in re.findall(r"0x([0-9A-Fa-f]{2})", line)]
# la tabla empieza en el caracter 0x20, 8 bytes por caracter
glyphs = data[: 64 * 8]
out = ["; FICHERO GENERADO por tools/gen_font.py - no editar a mano.",
       "; Caracteres 0x20-0x5F de aleste-lx/firmware/bios/src/fonts/font_win1252.asm",
       "; (8x8, bit 7 a la izquierda)."]
for c in range(64):
    g = glyphs[c * 8:(c + 1) * 8]
    out.append("        defb " + ",".join(f"{b:03X}h" for b in g) + f"    ; '{chr(0x20 + c)}'")
DST.write_text("\n".join(out) + "\n")
print(f"Generado {DST.relative_to(ROOT)}: 64 caracteres")
