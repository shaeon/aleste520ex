#!/usr/bin/env python3
"""
dos_preload.py - Prepara la precarga de MSX-DOS para la simulacion (+preload_dos).

Saca BIOS.SYS y BDOS.SYS de una imagen raw de MSX-DOS (FAT12), los pone al
principio de dos paginas de 16 KB (el resto a cero) y calcula la suma de
comprobacion que el BOOTMENU del 520EX (CTRL_SUMM) guarda en el reloj
(registros 3C-3D para la BIOS y 3E-3F para la BDOS). Con eso en memoria y en
el reloj, el BOOTMENU no carga nada del disco y salta a la BIOS enseguida,
como en un 520EX real a partir del segundo arranque.

Salida: preload_p8.bin, preload_p9.bin (16 KB cada uno) y preload_rtc.txt
(4 bytes en hexadecimal: 3C 3D 3E 3F).

Uso:  python3 tools/dos_preload.py alestedos-dev.dsk carpeta_salida
"""
import pathlib, struct, sys


def fat_files(d):
    bps, spc, res, nfat, nroot, tot, media, spf = struct.unpack_from("<HBHBHHBH", d, 11)
    root = (res + nfat * spf) * bps
    data0 = root + nroot * 32
    fat = d[res * bps:(res + spf) * bps]
    def nxt(n):
        o = n * 3 // 2
        v = fat[o] | fat[o + 1] << 8
        return (v >> 4) if n & 1 else (v & 0xFFF)
    files = {}
    for i in range(nroot):
        e = d[root + 32 * i: root + 32 * i + 32]
        if e[0] in (0, 0xE5) or e[11] & 0x18:
            continue
        name = e[0:8].decode("latin1").strip() + "." + e[8:11].decode("latin1").strip()
        cl, size = struct.unpack_from("<H", e, 26)[0], struct.unpack_from("<I", e, 28)[0]
        out = b""
        while 2 <= cl < 0xFF8:
            out += d[data0 + (cl - 2) * spc * bps: data0 + (cl - 1) * spc * bps]
            cl = nxt(cl)
        files[name] = out[:size]
    return files


def ctrl_summ(page):
    """CTRL_SUMM del BOOTMENU, instruccion a instruccion (flags del Z80)."""
    b = c = 0
    for x in page:
        a = c + x; cy = a > 0xFF; c = a & 0xFF                 # LD A,C / ADD A,(HL) / LD C,A
        a = b + cy; cy = a > 0xFF; a &= 0xFF; b = a            # LD A,B / ADC A,0 / LD B,A
        c, cy = ((c << 1) | cy) & 0xFF, c >> 7                 # RL C
        b, cy = ((b << 1) | cy) & 0xFF, b >> 7                 # RL B   (A sigue valiendo el B de antes)
        if cy:                                                 # JR NC,C_SUMM1
            a = c ^ 2; c = a                                   # LD A,C / XOR 2 / LD C,A
        b = a                                                  # C_SUMM1: LD B,A
    return b, c


def main():
    img, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    f = fat_files(img.read_bytes())
    regs = []
    for name, page, reg in (("BIOS.SYS", 8, 0x3C), ("BDOS.SYS", 9, 0x3E)):
        data = f[name].ljust(16384, b"\0")[:16384]
        (out / f"preload_p{page}.bin").write_bytes(data)
        b, c = ctrl_summ(data)
        regs += [c, b]                       # WR_CLOCK: reg = C (suma baja), reg+1 = B
        print(f"{name}: {len(f[name])} bytes -> pagina {page}, suma B={b:02X} C={c:02X} (reloj {reg:02X}/{reg+1:02X})")
    (out / "preload_rtc.txt").write_text(" ".join(f"{x:02X}" for x in regs) + "\n")


if __name__ == "__main__":
    main()
