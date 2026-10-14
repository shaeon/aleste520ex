#!/usr/bin/env python3
"""
make_rom.py - Construye el ALESTE.ROM del modo CPC (Aleste 520EX) a partir de
AL512.BIN, la ROM de 64 KB del 520EX (MAME: al520ex, CRC32 e8c2a9a1).

El fichero que carga el firmware MiST por el indice 0 se reparte asi
(rtl/mist_loader.sv):

  0000-3FFF  arranque en modo nativo   -> C00000 (aqui arranca la MMU nativa)
  4000-13FFF AL512.BIN (4 paginas)     -> 400000 (ROMs del modo CPC)

El arranque es minimo. La CPU empieza en modo supervisor/nativo en 0000h, con
las cuatro paginas del Z80 en C00000. Hace

  0000  LD BC,7F89h      (los 3 primeros bytes de AL512: el mismo LD que la
                          ROM del CPC, para que no importe en que modo se
                          lea la primera instruccion tras el cambio)
  0003  XOR A
  0004  JP 0FFFEh        (la pagina 3 tambien es C00000: va a 3FFEh)
  3FFE  OUT (0F0h),A     GLOBAL_CTRL = 0: sale de supervisor y pasa a modo
                          legacy (CPC). La MMU hace el cambio en el siguiente
                          M1, que es el de 0000h tras dar la vuelta.

y la CPU sigue en 0000h ya con la ROM baja del CPC (pagina 0 de AL512), como
tras un reset de un 520EX.

Uso:  python3 tools/make_rom.py RUTA/AL512.BIN [-o ALESTE.ROM]
      python3 tools/make_rom.py --boot-only -o BOOT520.BIN

Con --boot-only solo se genera el arranque (16 KB, sin nada de AL512 salvo
LD BC,7F89h). Asi el ALESTE.ROM se puede montar sin Python:
      copy /b BOOT520.BIN + AL512.BIN ALESTE.ROM      (Windows)
      cat BOOT520.BIN AL512.BIN > ALESTE.ROM          (Linux/macOS)
"""
import argparse, pathlib, sys, zlib

AL512_CRC = 0xE8C2A9A1

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("al512", nargs="?", help="AL512.BIN (64 KB)")
    ap.add_argument("--boot-only", action="store_true", help="solo el arranque de 16 KB")
    ap.add_argument("-o", "--output", default="ALESTE.ROM")
    args = ap.parse_args()

    if args.boot_only:
        rom = bytes([0x01, 0x89, 0x7F]) + bytes(65533)     # LD BC,7F89h: la primera instruccion del CPC
    elif not args.al512:
        ap.error("falta AL512.BIN (o --boot-only)")
    else:
        rom = pathlib.Path(args.al512).read_bytes()
    if len(rom) != 65536:
        sys.exit(f"{args.al512}: {len(rom)} bytes, se esperaban 65536")
    crc = zlib.crc32(rom)
    if not args.boot_only and crc != AL512_CRC:
        print(f"Aviso: CRC32 {crc:08x}, no es el AL512.BIN de MAME ({AL512_CRC:08x})")
    if rom[0] != 0x01:
        sys.exit("AL512.BIN no empieza por LD BC,nn: el arranque supone que si")

    boot = bytearray(0x4000)
    boot[0:3] = rom[0:3]                       # LD BC,7F89h (igual que la ROM del CPC)
    boot[3] = 0xAF                             # XOR A
    boot[4:7] = bytes([0xC3, 0xFE, 0xFF])      # JP 0FFFEh
    boot[0x3FFE:0x4000] = bytes([0xD3, 0xF0])  # OUT (0F0h),A  -> modo CPC

    out = bytes(boot) if args.boot_only else bytes(boot) + rom
    pathlib.Path(args.output).write_bytes(out)
    print(f"{args.output}: {len(out)} bytes" + (" (arranque)" if args.boot_only else " (arranque 16 KB + AL512 64 KB)"))

if __name__ == "__main__":
    main()
