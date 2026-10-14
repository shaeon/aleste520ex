#!/usr/bin/env python3
"""
make_msxdisk.py - Crea un disquete de MSX-DOS (Aleste 520EX) con los ficheros
de una carpeta.

Genera una imagen raw con el formato de los discos de MSX-DOS del 520EX
(FAT12; 720 KB: 512 bytes/sector, 2 sectores/cluster, 2 FAT de 3 sectores,
112 entradas de directorio, 9 sectores/pista, 2 caras, medio F9; o 360 KB de
una cara, medio F8). El core la monta directamente; con --edsk se genera
tambien la version EDSK.

Para que el disco arranque MSX-DOS en el 520EX, --system toma de un disco de
sistema existente (por ejemplo alestedos-dev.dsk) el sector de arranque y los
ficheros BIOS.SYS, BDOS.SYS, MSXDOS.SYS y COMMAND.COM. Un fichero de la
carpeta con el mismo nombre tiene preferencia. --2drives activa la segunda
disquetera en esa BDOS (como tools/bdos_2drives.py).

Sin --system el disco es solo de datos: el sector de arranque lleva el BPB y
un RET (no arranca, pero MSX-DOS lo lee desde cualquier unidad).

Nombres: se pasan a 8.3 en mayusculas; los caracteres que MSX-DOS no admite
se cambian por '_' y, si dos ficheros acaban con el mismo nombre, se numeran
(NOMBRE~1.EXT). MSX-DOS 1 no tiene subcarpetas: se avisa y se saltan. Las
fechas de los ficheros se conservan.

Disco existente (como wrdsk / rddsk de fMSX, en Tools/rdwrdsk de hww):
    --list IMAGEN                     lista los ficheros (tamano y fecha)
    --extract IMAGEN [-d CARPETA] [NOMBRE...]
                                      saca todos los ficheros o los indicados,
                                      con la fecha que tienen en el disco
    --add IMAGEN FICHERO|CARPETA...   mete ficheros en los clusteres libres; si
                                      ya hay uno con el mismo nombre, lo sustituye

Ejemplos:
    python3 tools/make_msxdisk.py juegos/ -o JUEGOS.DSK
    python3 tools/make_msxdisk.py juegos/ -o JUEGOS.DSK --system alestedos-dev.dsk --2drives
    python3 tools/make_msxdisk.py juegos/ -o JUEGOS.DSK --edsk
    python3 tools/make_msxdisk.py --list ALESTDOS.DSK
    python3 tools/make_msxdisk.py --add ALESTDOS.DSK TIME.COM juegos/
    python3 tools/make_msxdisk.py --extract ALESTDOS.DSK -d copia/ COMMAND.COM
"""
import argparse, datetime, os, re, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from raw2edsk import edsk                       # noqa: E402

GEOM = {
    720: dict(total=1440, media=0xF9, spf=3, spt=9, heads=2, cyls=80),
    360: dict(total=720,  media=0xF8, spf=2, spt=9, heads=1, cyls=80),
}
BPS, SPC, RES, NFAT, NROOT = 512, 2, 1, 2, 112
SYSTEM_FILES = ("MSXDOS.SYS", "BIOS.SYS", "BDOS.SYS", "COMMAND.COM")   # en este orden, al principio
BDOS_1DRV = bytes.fromhex("3A F1 FB AF 2E 01 28 01 2C DD 75 09")
VALID = re.compile(r"[^A-Z0-9!#$%&'()\-@^_`{}~]")


def short_name(name, used):
    """Nombre 8.3 de MSX-DOS, unico dentro del disco."""
    base, ext = os.path.splitext(name.upper())
    base = VALID.sub("_", base.replace(" ", ""))[:8] or "_"
    ext = VALID.sub("_", ext[1:].replace(" ", ""))[:3]
    cand, n = (base, ext), 1
    while cand in used:
        tail = f"~{n}"
        cand, n = (base[:8 - len(tail)] + tail, ext), n + 1
    used.add(cand)
    return cand


def fat_time(ts):
    t = datetime.datetime.fromtimestamp(ts)
    year = min(max(t.year, 1980), 2107)
    date = ((year - 1980) << 9) | (t.month << 5) | t.day
    time = (t.hour << 11) | (t.minute << 5) | (t.second // 2)
    return time, date


def read_fat_files(img):
    """Ficheros de la raiz de una imagen FAT12 raw: {nombre: (datos, hora, fecha)}."""
    bps, spc, res, nfat, nroot, tot, media, spf = struct.unpack_from("<HBHBHHBH", img, 11)
    root = (res + nfat * spf) * bps
    data0 = root + nroot * 32
    fat = img[res * bps:(res + spf) * bps]

    def nxt(c):
        o = c * 3 // 2
        v = fat[o] | fat[o + 1] << 8
        return (v >> 4) if c & 1 else (v & 0xFFF)

    files = {}
    for i in range(nroot):
        e = img[root + 32 * i: root + 32 * i + 32]
        if e[0] in (0, 0xE5) or e[11] & 0x18:
            continue
        name = e[0:8].decode("latin1").rstrip() + "." + e[8:11].decode("latin1").rstrip()
        cl, size = struct.unpack_from("<H", e, 26)[0], struct.unpack_from("<I", e, 28)[0]
        data, seen = b"", set()
        while 2 <= cl < 0xFF8 and cl not in seen:
            seen.add(cl)
            data += img[data0 + (cl - 2) * spc * bps: data0 + (cl - 1) * spc * bps]
            cl = nxt(cl)
        files[name.rstrip(".")] = (data[:size], *struct.unpack_from("<HH", e, 22))
    return files


def build(entries, g, boot):
    """entries: [(nombre8, ext3, datos, hora, fecha)] -> imagen raw."""
    total, spf = g["total"], g["spf"]
    img = bytearray(b"\xE5" * (total * BPS))
    img[:BPS] = boot
    fat_off, root_off = RES * BPS, (RES + NFAT * spf) * BPS
    data0 = root_off + NROOT * 32
    nclusters = (total * BPS - data0) // (SPC * BPS)
    fat = bytearray(spf * BPS)

    def setf(c, v):
        o = c * 3 // 2
        if c & 1:
            fat[o] = (fat[o] & 0x0F) | ((v << 4) & 0xF0); fat[o + 1] = v >> 4
        else:
            fat[o] = v & 0xFF; fat[o + 1] = (fat[o + 1] & 0xF0) | (v >> 8)

    setf(0, 0xF00 | g["media"]); setf(1, 0xFFF)
    root = bytearray(NROOT * 32)
    if len(entries) > NROOT:
        sys.exit(f"demasiados ficheros: {len(entries)} (el directorio de MSX-DOS admite {NROOT})")
    nxt_cl, csize = 2, SPC * BPS
    for k, (b8, e3, data, tm, dt) in enumerate(entries):
        need = (len(data) + csize - 1) // csize
        if nxt_cl - 2 + need > nclusters:
            free = (nclusters - (nxt_cl - 2)) * csize
            sys.exit(f"no cabe {b8}.{e3} ({len(data)} bytes): quedan {free} bytes libres en el disco")
        first = nxt_cl if need else 0
        for j in range(need):
            c = nxt_cl + j
            setf(c, c + 1 if j + 1 < need else 0xFFF)
            chunk = data[j * csize:(j + 1) * csize]
            img[data0 + (c - 2) * csize: data0 + (c - 2) * csize + len(chunk)] = chunk
        nxt_cl += need
        e = bytearray(32)
        e[0:8] = b8.ljust(8).encode("latin1"); e[8:11] = e3.ljust(3).encode("latin1")
        e[11] = 0x20                                                # archivo
        struct.pack_into("<HHHI", e, 22, tm, dt, first, len(data))
        root[32 * k: 32 * k + 32] = e
    for f in range(NFAT):
        img[fat_off + f * spf * BPS: fat_off + (f + 1) * spf * BPS] = fat
    img[root_off:root_off + len(root)] = root
    used = (nxt_cl - 2) * csize
    return bytes(img), used, nclusters * csize


def data_boot(g):
    """Sector de arranque de un disco de datos: BPB de MSX-DOS y un RET."""
    b = bytearray(BPS)
    b[0:3] = b"\xEB\xFE\x90"
    b[3:11] = b"ALESTE  "
    struct.pack_into("<HBHBHHBHHHH", b, 11, BPS, SPC, RES, NFAT, NROOT, g["total"], g["media"], g["spf"],
                     g["spt"], g["heads"], 0)
    b[0x1E] = 0xC9                     # el disk ROM de MSX llama aqui: RET = no arranca
    return bytes(b)


class FatImage:
    """Imagen raw FAT12 de MSX-DOS existente: listar, leer, borrar y anadir ficheros."""

    def __init__(self, path):
        self.path = path
        self.img = bytearray(open(path, "rb").read())
        if self.img[:8] in (b"EXTENDED", b"MV - CPC"):
            sys.exit(f"{path}: es EDSK; estas opciones trabajan con la imagen raw")
        (self.bps, self.spc, self.res, self.nfat, self.nroot, self.total, self.media,
         self.spf) = struct.unpack_from("<HBHBHHBH", self.img, 11)
        if self.bps != 512 or self.spc not in (1, 2, 4) or not 1 <= self.spf <= 9:
            sys.exit(f"{path}: el sector de arranque no parece de un disco de MSX-DOS")
        self.fat_off = self.res * self.bps
        self.root = (self.res + self.nfat * self.spf) * self.bps
        self.data0 = self.root + self.nroot * 32
        self.csize = self.spc * self.bps
        self.nclusters = (self.total * self.bps - self.data0) // self.csize
        self.fat = self.img[self.fat_off:self.fat_off + self.spf * self.bps]

    def get(self, c):
        o = c * 3 // 2
        v = self.fat[o] | self.fat[o + 1] << 8
        return (v >> 4) if c & 1 else (v & 0xFFF)

    def set(self, c, v):
        o = c * 3 // 2
        if c & 1:
            self.fat[o] = (self.fat[o] & 0x0F) | ((v << 4) & 0xF0); self.fat[o + 1] = (v >> 4) & 0xFF
        else:
            self.fat[o] = v & 0xFF; self.fat[o + 1] = (self.fat[o + 1] & 0xF0) | ((v >> 8) & 0x0F)

    def entries(self):
        for i in range(self.nroot):
            e = self.img[self.root + 32 * i: self.root + 32 * i + 32]
            if e[0] == 0:
                break
            if e[0] == 0xE5 or e[11] & 0x18:
                continue
            name = e[0:8].decode("latin1").rstrip() + ("." + e[8:11].decode("latin1").rstrip() if e[8:11].strip() else "")
            tm, dt, cl = struct.unpack_from("<HHH", e, 22)
            yield i, name, cl, struct.unpack_from("<I", e, 28)[0], tm, dt

    def chain(self, cl):
        out, seen = [], set()
        while 2 <= cl < 0xFF8 and cl not in seen and cl < self.nclusters + 2:
            seen.add(cl); out.append(cl); cl = self.get(cl)
        return out

    def read(self, cl, size):
        data = b"".join(bytes(self.img[self.data0 + (c - 2) * self.csize: self.data0 + (c - 1) * self.csize]) for c in self.chain(cl))
        return data[:size]

    def delete(self, i, cl):
        for c in self.chain(cl):
            self.set(c, 0)
        self.img[self.root + 32 * i] = 0xE5

    def add(self, b8, e3, data, tm, dt):
        need = (len(data) + self.csize - 1) // self.csize
        free = [c for c in range(2, self.nclusters + 2) if self.get(c) == 0][:need]
        if len(free) < need:
            raise ValueError(f"no cabe: hacen falta {need * self.csize} bytes y quedan {self.free_bytes()}")
        slot = next((i for i in range(self.nroot) if self.img[self.root + 32 * i] in (0, 0xE5)), None)
        if slot is None:
            raise ValueError(f"el directorio esta lleno ({self.nroot} entradas)")
        for k, c in enumerate(free):
            self.set(c, free[k + 1] if k + 1 < len(free) else 0xFFF)
            chunk = data[k * self.csize:(k + 1) * self.csize]
            self.img[self.data0 + (c - 2) * self.csize: self.data0 + (c - 2) * self.csize + len(chunk)] = chunk
        e = bytearray(32)
        e[0:8] = b8.ljust(8).encode("latin1"); e[8:11] = e3.ljust(3).encode("latin1"); e[11] = 0x20
        struct.pack_into("<HHHI", e, 22, tm, dt, free[0] if free else 0, len(data))
        self.img[self.root + 32 * slot: self.root + 32 * slot + 32] = e

    def free_bytes(self):
        return sum(1 for c in range(2, self.nclusters + 2) if self.get(c) == 0) * self.csize

    def save(self):
        for f in range(self.nfat):
            self.img[self.fat_off + f * self.spf * self.bps: self.fat_off + (f + 1) * self.spf * self.bps] = self.fat
        open(self.path, "wb").write(self.img)


def fat_date(tm, dt):
    """Fecha y hora de FAT -> (texto, segundos desde 1970 o None)."""
    y, mo, d = 1980 + (dt >> 9), (dt >> 5) & 15, dt & 31
    h, mi, se = tm >> 11, (tm >> 5) & 63, (tm & 31) * 2
    try:
        ts = datetime.datetime(y, mo, d, h, mi, se).timestamp()
    except ValueError:
        ts = None
    return f"{y:04}-{mo:02}-{d:02} {h:02}:{mi:02}", ts


def do_list(path):
    im = FatImage(path)
    n = tot = 0
    for _, name, _, size, tm, dt in im.entries():
        print(f"  {name:13} {size:8}  {fat_date(tm, dt)[0]}"); n += 1; tot += size
    print(f"{n} ficheros, {tot} bytes; libres {im.free_bytes()} bytes")


def do_extract(path, dest, names):
    im = FatImage(path)
    os.makedirs(dest, exist_ok=True)
    want = {x.upper() for x in names}
    got = set()
    for _, name, cl, size, tm, dt in im.entries():
        if want and name not in want:
            continue
        out = os.path.join(dest, name)
        open(out, "wb").write(im.read(cl, size))
        ts = fat_date(tm, dt)[1]
        if ts:
            os.utime(out, (ts, ts))
        print(f"  {name:13} {size:8} -> {out}"); got.add(name)
    for x in sorted(want - got):
        print(f"  aviso: {x} no esta en el disco")


def do_add(path, sources):
    im = FatImage(path)
    files = []
    for src in sources:
        if os.path.isdir(src):
            for n in sorted(os.listdir(src)):
                p = os.path.join(src, n)
                if os.path.isdir(p):
                    print(f"  aviso: {p}/ es una carpeta (MSX-DOS 1 no tiene subcarpetas), se salta")
                else:
                    files.append(p)
        else:
            files.append(src)
    existing = {name: (i, cl) for i, name, cl, _, _, _ in im.entries()}
    used = {(n.split(".")[0], n.split(".")[1] if "." in n else "") for n in existing}
    for p in files:
        b8, e3 = short_name(os.path.basename(p), set())
        key = b8 + ("." + e3 if e3 else "")
        if key in existing:                                     # sustituir
            im.delete(*existing.pop(key))
            print(f"  {key}: se sustituye")
        else:
            b8, e3 = short_name(os.path.basename(p), used)
            key = b8 + ("." + e3 if e3 else "")
        data = open(p, "rb").read()
        try:
            im.add(b8, e3, data, *fat_time(os.path.getmtime(p)))
        except ValueError as err:
            sys.exit(f"{key}: {err} (no se ha cambiado el disco)")
        print(f"  {key:13} {len(data):8}" + (f"  ({os.path.basename(p)})" if key != os.path.basename(p).upper() else ""))
    im.save()
    print(f"{path}: libres {im.free_bytes()} bytes")


def main():
    ap = argparse.ArgumentParser(description="Crea un disquete de MSX-DOS (Aleste 520EX) a partir de una carpeta",
                                 formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    ap.add_argument("folder", nargs="*", help="carpeta con los ficheros (con --add: ficheros o carpetas; con --extract: nombres)")
    ap.add_argument("-o", "--output", help="imagen raw de salida (.DSK)")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--list", metavar="IMAGEN", help="listar los ficheros de un disco")
    mode.add_argument("--extract", metavar="IMAGEN", help="sacar ficheros de un disco (todos o los nombrados)")
    mode.add_argument("--add", metavar="IMAGEN", help="anadir ficheros a un disco existente")
    ap.add_argument("-d", "--dest", default=".", help="carpeta de destino para --extract")
    ap.add_argument("--size", type=int, choices=(720, 360), default=720, help="720 KB (2 caras, por defecto) o 360 KB")
    ap.add_argument("--system", metavar="DISCO", help="disco de sistema del que copiar el arranque y BIOS/BDOS/COMMAND")
    ap.add_argument("--2drives", dest="two", action="store_true", help="activar la segunda disquetera en la BDOS")
    ap.add_argument("--edsk", action="store_true", help="generar tambien la version EDSK (<salida>.edsk.dsk)")
    a = ap.parse_args()
    if a.list:
        return do_list(a.list)
    if a.extract:
        return do_extract(a.extract, a.dest, a.folder)
    if a.add:
        if not a.folder:
            ap.error("--add necesita ficheros o carpetas")
        return do_add(a.add, a.folder)
    if len(a.folder) != 1 or not a.output:
        ap.error("para crear un disco: una carpeta y -o IMAGEN")
    a.folder = a.folder[0]

    g = GEOM[a.size]
    used, entries, boot = set(), [], data_boot(g)
    if a.system:
        sysimg = open(a.system, "rb").read()
        if sysimg[:8] in (b"EXTENDED", b"MV - CPC"):
            sys.exit(f"{a.system}: es EDSK; usa la imagen raw del disco de sistema")
        sysfiles = read_fat_files(sysimg)
        boot = bytearray(sysimg[:BPS])
        struct.pack_into("<HBHBHHBHHH", boot, 11, BPS, SPC, RES, NFAT, NROOT, g["total"], g["media"], g["spf"],
                         g["spt"], g["heads"])     # geometria del disco nuevo
        boot = bytes(boot)
    else:
        sysfiles = {}

    local = {}
    for name in sorted(os.listdir(a.folder)):
        path = os.path.join(a.folder, name)
        if os.path.isdir(path):
            print(f"  aviso: {name}/ es una carpeta; MSX-DOS 1 no tiene subcarpetas, se salta")
            continue
        local[name] = path

    # primero los ficheros del sistema (los de la carpeta tienen preferencia)
    for sname in SYSTEM_FILES:
        lname = next((n for n in local if n.upper() == sname), None)
        if lname:
            p = local.pop(lname)
            data, (tm, dt) = open(p, "rb").read(), fat_time(os.path.getmtime(p))
            src = "carpeta"
        elif sname in sysfiles:
            data, tm, dt = sysfiles[sname]
            src = os.path.basename(a.system)
        else:
            continue
        if sname == "BDOS.SYS" and a.two:
            if BDOS_1DRV in data:
                i = data.index(BDOS_1DRV) + 3
                data = data[:i] + b"\xB7" + data[i + 1:]
                print("  BDOS.SYS: segunda disquetera activada (XOR A -> OR A)")
            else:
                print("  BDOS.SYS: no tiene la deteccion de una sola disquetera (ya admite dos o es otra version)")
        b8, e3 = short_name(sname, used)
        entries.append((b8, e3, data, tm, dt))
        print(f"  {b8 + '.' + e3:<13} {len(data):8d}  ({src})")

    for name, path in local.items():
        b8, e3 = short_name(name, used)
        data = open(path, "rb").read()
        entries.append((b8, e3, data, *fat_time(os.path.getmtime(path))))
        shown = b8 + ("." + e3 if e3 else "")
        print(f"  {shown:<13} {len(data):8d}" + (f"  ({name})" if shown != name.upper() else ""))

    img, used_b, cap = build(entries, g, boot)
    open(a.output, "wb").write(img)
    print(f"{a.output}: {len(entries)} ficheros, {used_b // 1024} KB usados de {cap // 1024} KB"
          + (" (arranca MSX-DOS)" if a.system else " (disco de datos)"))
    if a.edsk:
        out = os.path.splitext(a.output)[0] + ".edsk.dsk"
        open(out, "wb").write(edsk(img, g["cyls"], g["heads"], g["spt"], BPS, 1))
        print(f"  -> {out} [EDSK]")


if __name__ == "__main__":
    main()
