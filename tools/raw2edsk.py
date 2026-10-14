#!/usr/bin/env python3
"""
raw2edsk.py - Convierte imagenes de disco en bruto (raw) a EDSK para el core
del Aleste 520EX (y para cualquier emulador de CPC).

El core ya monta imagenes raw directamente (rtl/cpc/u765.sv), pero un EDSK
es el formato que entienden todas las herramientas de CPC y deja fijada la
geometria y los numeros de sector. Como raw2dsk.py del core NewBrain, pero
autonomo (no necesita td0conv.py) y con la geometria del 520EX.

Una imagen raw es solo los sectores, pista tras pista (C0H0, C0H1, C1H0...),
cada pista con sus sectores en orden de numero. Este programa los envuelve en
la estructura EDSK (Disk-Info y un Track-Info por pista).

Geometria, por este orden:
  1. lo que se pida con --cyls / --heads / --spt / --secsize
  2. el sector de arranque FAT (MSX-DOS, como los discos del 520EX):
     bytes por sector, sectores por pista, caras y total de sectores
  3. el tamano (la misma tabla que el core):
       720 KB -> 80 x 2 x 9    360 KB -> 80 x 1 x 9    800 KB -> 80 x 2 x 10
       640 KB -> 80 x 2 x 8    320 KB -> 80 x 1 x 8    180 KB -> 40 x 1 x 9
Lo que sobre de un numero entero de pistas se ignora (msx-games.dsk trae
16 bytes de mas al final).

Numeros de sector: 1..N por defecto (MSX-DOS, PC). Para imagenes raw de
CPC: --cpc-data (C1..C9) o --cpc-system (41..49).

Ejemplos:
  python3 raw2edsk.py alestedos-dev.dsk               -> alestedos-dev.edsk.dsk
  python3 raw2edsk.py *.dsk -d edsk/ -v                -> carpeta entera, con directorio
  python3 raw2edsk.py juego.raw --cpc-data -o juego.dsk
"""

import argparse
import glob
import os
import struct
import sys

# bloques de 512 bytes -> (pistas, caras, sectores por pista); como rtl/cpc/u765.sv
BY_BLOCKS = {
    1440: (80, 2, 9),
    720:  (80, 1, 9),
    1600: (80, 2, 10),
    1280: (80, 2, 8),
    640:  (80, 1, 8),
    360:  (40, 1, 9),
}


def read_bpb(d):
    """Geometria del sector de arranque FAT (MSX-DOS/PC), o None."""
    if len(d) < 512:
        return None
    bps, spc, res, nfat, nroot, tot, media, spf, spt, heads = struct.unpack_from("<HBHBHHBHHH", d, 0x0B)
    if bps not in (128, 256, 512, 1024) or not 1 <= spt <= 18 or heads not in (1, 2):
        return None
    if media < 0xF0 or tot == 0 or tot % (spt * heads):
        return None
    return dict(secsize=bps, spt=spt, heads=heads, cyls=tot // (spt * heads),
                spc=spc, res=res, nfat=nfat, nroot=nroot, spf=spf, media=media)


def fat_listing(d, bpb):
    """Directorio raiz FAT12: [(nombre, tamano)]."""
    bps = bpb["secsize"]
    root = (bpb["res"] + bpb["nfat"] * bpb["spf"]) * bps
    out = []
    for i in range(bpb["nroot"]):
        e = d[root + 32 * i: root + 32 * i + 32]
        if len(e) < 32 or e[0] == 0:
            break
        if e[0] == 0xE5 or e[11] & 0x08:
            continue
        name = e[0:8].decode("latin-1").rstrip() + "." + e[8:11].decode("latin-1").rstrip()
        out.append((name.rstrip("."), struct.unpack_from("<I", e, 28)[0]))
    return out


def amsdos_listing(d):
    """Directorio AMSDOS/CP/M (formato DATA: pista 0, sectores 1-4)."""
    files = {}
    for i in range(64):
        e = d[32 * i: 32 * i + 32]
        if len(e) < 32 or e[0] > 15:
            continue
        name = bytes(b & 0x7F for b in e[1:12]).decode("latin-1")
        key = (e[0], name[:8].rstrip() + "." + name[8:].rstrip())
        files[key] = files.get(key, 0) + 128 * e[15]          # registros de 128 bytes de esta extension
    return sorted(files.items())


def edsk(d, cyls, heads, spt, secsize, first_id, side_order=False, interleave=1, gap3=0x54, filler=0xE5):
    code = {128: 0, 256: 1, 512: 2, 1024: 3}[secsize]
    # orden fisico de los sectores en la pista (entrelazado 1 = seguidos)
    order, pos = [None] * spt, 0
    for s in range(spt):
        while order[pos] is not None:
            pos = (pos + 1) % spt
        order[pos] = s
        pos = (pos + interleave) % spt
    tsize = 0x100 + spt * secsize
    hdr = bytearray(256)
    hdr[0:34] = b"EXTENDED CPC DSK File\r\nDisk-Info\r\n"
    hdr[0x22:0x30] = b"raw2edsk.py   "
    hdr[0x30], hdr[0x31] = cyls, heads
    for t in range(cyls * heads):
        hdr[0x34 + t] = tsize // 256
    out = bytearray(hdr)
    for c in range(cyls):
        for h in range(heads):
            idx = (h * cyls + c) if side_order else (c * heads + h)
            base = idx * spt * secsize
            ti = bytearray(256)
            ti[0:12] = b"Track-Info\r\n"
            ti[0x10], ti[0x11], ti[0x12], ti[0x13] = c, h, 1, 2      # DD, MFM
            ti[0x14], ti[0x15], ti[0x16], ti[0x17] = code, spt, gap3, filler
            data = bytearray()
            for k, s in enumerate(order):
                ti[0x18 + 8 * k: 0x20 + 8 * k] = bytes([c, h, first_id + s, code, 0, 0]) + struct.pack("<H", secsize)
                data += d[base + s * secsize: base + (s + 1) * secsize].ljust(secsize, bytes([filler]))
            out += ti + data
    return bytes(out)


def convert(path, a, log=print):
    d = open(path, "rb").read()
    if d[:8] in (b"EXTENDED", b"MV - CPC"):
        log(f"{path}: ya es DSK/EDSK, no se toca")
        return
    bpb = read_bpb(d)
    secsize = a.secsize or (bpb["secsize"] if bpb else 512)
    if bpb and not (a.cpc_data or a.cpc_system):
        cyls, heads, spt = bpb["cyls"], bpb["heads"], bpb["spt"]
        src = f"sector de arranque FAT (media {bpb['media']:02X})"
    elif len(d) // 512 in BY_BLOCKS:
        cyls, heads, spt = BY_BLOCKS[len(d) // 512]
        src = "tamano"
    else:
        cyls, heads, spt = 80, 2 if len(d) > 720 * 512 else 1, 9
        src = "tamano desconocido: se supone"
    if a.cpc_data or a.cpc_system:
        cyls, heads, spt = 40, 1, 9
        src = "formato CPC"
    cyls, heads, spt = a.cyls or cyls, a.heads or heads, a.spt or spt
    first_id = 0xC1 if a.cpc_data else 0x41 if a.cpc_system else a.first_id
    need = cyls * heads * spt * secsize
    log(f"{path}: {len(d)} bytes; {cyls} pistas x {heads} caras x {spt} sectores de {secsize} "
        f"({src}); sectores {first_id:02X}-{first_id + spt - 1:02X}")
    if len(d) != need:
        log(f"  aviso: la geometria da {need} bytes; " +
            ("se rellena con E5" if len(d) < need else f"se ignoran {len(d) - need} bytes del final"))
        d = d.ljust(need, b"\xE5")[:need]
    if a.verbose:
        if bpb and first_id == 1:
            for name, size in fat_listing(d, bpb):
                log(f"    {name:<13} {size:8d}")
        elif first_id == 0xC1:
            for (user, name), size in amsdos_listing(d):
                log(f"    {user:>2}: {name}")
    out = a.output or os.path.join(a.dest or os.path.dirname(path) or ".",
                                   os.path.splitext(os.path.basename(path))[0] + a.suffix + ".dsk")
    with open(out, "wb") as f:
        f.write(edsk(d, cyls, heads, spt, secsize, first_id, a.side_order, a.interleave))
    log(f"  -> {out} [EDSK, {os.path.getsize(out)} bytes]")


def main():
    ap = argparse.ArgumentParser(description="Convierte imagenes de disco raw a EDSK (Aleste 520EX, CPC)",
                                 formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    ap.add_argument("images", nargs="+", help="imagenes raw (se admiten comodines)")
    ap.add_argument("-o", "--output", help="fichero de salida (solo con una entrada)")
    ap.add_argument("-d", "--dest", help="carpeta de salida")
    ap.add_argument("--suffix", default=".edsk", help="sufijo del nombre de salida (por defecto .edsk)")
    ap.add_argument("-v", "--verbose", action="store_true", help="lista el directorio del disco")
    ap.add_argument("--cyls", type=int, help="numero de pistas")
    ap.add_argument("--heads", type=int, help="numero de caras")
    ap.add_argument("--spt", type=int, help="sectores por pista")
    ap.add_argument("--secsize", type=int, choices=(128, 256, 512, 1024), help="bytes por sector")
    ap.add_argument("--first-id", type=lambda x: int(x, 0), default=1, help="numero del primer sector (por defecto 1)")
    ap.add_argument("--cpc-data", action="store_true", help="formato DATA de CPC: 40 x 1 x 9, sectores C1-C9")
    ap.add_argument("--cpc-system", action="store_true", help="formato SYSTEM de CPC: 40 x 1 x 9, sectores 41-49")
    ap.add_argument("--side-order", action="store_true", help="la imagen tiene toda la cara 0 y luego la 1")
    ap.add_argument("--interleave", type=int, default=1, help="entrelazado fisico de sectores (por defecto 1)")
    a = ap.parse_args()

    paths = []
    for p in a.images:
        paths += sorted(glob.glob(p)) if any(ch in p for ch in "*?[") else [p]
    paths = [p for p in paths if os.path.isfile(p)]
    if not paths:
        sys.exit("ERROR: no hay ficheros de entrada")
    if a.output and len(paths) > 1:
        sys.exit("ERROR: -o solo con un fichero de entrada")
    if a.dest:
        os.makedirs(a.dest, exist_ok=True)
    for p in paths:
        try:
            convert(p, a)
        except (OSError, ValueError, KeyError) as e:
            print(f"{p}: ERROR: {e}")


if __name__ == "__main__":
    main()
