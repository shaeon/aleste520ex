#!/usr/bin/env python3
"""
bdos_2drives.py - Activa la segunda disquetera en la BDOS de MSX-DOS del 520EX.

La rutina DRIVES de la BDOS.SYS de los discos del 520EX lee el resultado de la
deteccion de la unidad B (recalibrado y senal de pista 0, guardado en FBF1) y
lo borra con un XOR A antes de decidir:

    LD A,(FBF1) ; XOR A ; LD L,1 ; JR Z,+1 ; INC L ; LD (IX+9),L
    3A F1 FB      AF      2E 01    28 01    2C      DD 75 09

Asi siempre declara una sola disquetera fisica y B: es una unidad fantasma de
A: ("Insert diskette for drive B:"). Cambiando XOR A (AF) por OR A (B7) la
deteccion funciona: con B: presente, dos disqueteras de verdad.

Busca esa secuencia exacta en la imagen (raw o EDSK) y cambia solo ese byte.
Si la imagen ya esta parcheada o no tiene esa BDOS, no toca nada.

Uso:  python3 tools/bdos_2drives.py disco.dsk [-o disco_2drv.dsk]
"""
import argparse, sys

PAT = bytes.fromhex("3A F1 FB AF 2E 01 28 01 2C DD 75 09")
DONE = bytes.fromhex("3A F1 FB B7 2E 01 28 01 2C DD 75 09")


def main():
    ap = argparse.ArgumentParser(description="Activa la segunda disquetera en la BDOS de MSX-DOS del 520EX")
    ap.add_argument("image")
    ap.add_argument("-o", "--output", help="fichero de salida (por defecto, sobre la misma imagen)")
    a = ap.parse_args()
    d = bytearray(open(a.image, "rb").read())
    n = d.count(PAT)
    if n == 0:
        print(f"{a.image}: " + ("ya estaba parcheada" if DONE in d else "no tiene esa BDOS (no se cambia nada)"))
        sys.exit(0 if DONE in d else 1)
    if n > 1:
        sys.exit(f"{a.image}: la secuencia aparece {n} veces; no se toca por seguridad")
    i = d.index(PAT) + 3
    d[i] = 0xB7
    out = a.output or a.image
    open(out, "wb").write(d)
    print(f"{a.image}: XOR A -> OR A en el byte {i} (0x{i:X}) -> {out}")


if __name__ == "__main__":
    main()
