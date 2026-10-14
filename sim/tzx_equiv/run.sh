#!/bin/sh
# Comprueba que rtl/cpc/tzxplayer.sv (traduccion) y el tzxplayer.vhd original de
# gyurco dan la misma senal de cinta, ciclo a ciclo, con cintas TZX sinteticas
# que usan todos los tipos de bloque. Necesita GHDL y Verilator.
set -e
cd "$(dirname "$0")"
rm -rf obj; verilator --binary --timing -j 0 -Wno-fatal -Wno-lint -Wno-style --top-module tb_sv -Mdir obj ../../rtl/cpc/tzxplayer.sv tb_sv.sv > build.log 2>&1
for s in 1 2 3 4; do
  python3 gen_tzx.py tape.tzx $s > /dev/null
  python3 - <<'PY'
d = open("tape.tzx", "rb").read()
open("tape.hex", "w").write("\n".join(f"{x:02x}" for x in d) + "\n")
vals = ", ".join(f'x"{x:02X}"' for x in d)
open("tape_pkg.vhd", "w").write("library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;\n"
  f"package tape_pkg is\n  type tape_t is array (0 to {len(d)-1}) of unsigned(7 downto 0);\n"
  f"  constant TAPE : tape_t := ({vals});\n  constant TAPE_LEN : integer := {len(d)};\nend package;\n")
PY
  ghdl -a --std=08 tzxplayer_orig.vhd tape_pkg.vhd tb_vhd.vhd; ghdl -e --std=08 tb_vhd
  ghdl -r --std=08 tb_vhd 2>/dev/null | grep -E "^[0-9]+ '" | awk '$1 >= 5' > a.txt
  obj/Vtb_sv 2>/dev/null | grep -E "^[0-9]+ '" | awk '$1 >= 5' > b.txt
  if diff -q a.txt b.txt > /dev/null; then echo "cinta $s: $(wc -l < a.txt) cambios, IDENTICAS"; else echo "cinta $s: DISTINTAS"; exit 1; fi
done
