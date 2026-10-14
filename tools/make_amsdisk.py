#!/usr/bin/env python3
"""
make_amsdisk.py - Crea disquetes de AMSDOS (modo AMSTRAD del Aleste 520EX)
con los ficheros de una carpeta.

Formato DATA del AMSDOS (el de los discos de CPC; el Aleste lo usa en modo
AMSTRAD): 40 pistas, una cara, 9 sectores de 512 bytes por pista (C1h-C9h),
bloques de 1 KB, 64 entradas de directorio, 178 KB utiles. La imagen sale en
EDSK, que el core monta directamente.

Los ficheros se copian tal cual: si llevan la cabecera AMSDOS de 128 bytes
(los BASIC y binarios guardados por el CPC), la conservan, porque el AMSDOS la
guarda dentro del propio fichero. Los que no la llevan (texto) se rellenan con
1Ah (fin de texto) hasta el final del registro de 128 bytes.

Si no caben en un disco, --split los reparte en varios (NOMBRE1.DSK,
NOMBRE2.DSK...), manteniendo juntos los ficheros de un mismo programa: los que
comparten nombre (DRILLER.BAS, DRILLER.BIN...) y las familias tipo SPT1SPR /
SPT1SYS / SPT1TAB.

Ejemplos:
    python3 tools/make_amsdisk.py juegos/ -o JUEGOS.DSK
    python3 tools/make_amsdisk.py juegos/ -o JUEGOS.DSK --split
"""
import argparse, os, re, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from raw2edsk import edsk                       # noqa: E402

TRACKS, SPT, SECSIZE, FIRST_ID = 40, 9, 512, 0xC1
BLOCK = 1024
DIR_BLOCKS, DIR_ENTRIES = 2, 64
TOTAL_BLOCKS = TRACKS * SPT * SECSIZE // BLOCK          # 180
DATA_BLOCKS = TOTAL_BLOCKS - DIR_BLOCKS                 # 178
VALID = re.compile(r"[^A-Z0-9!#$%&'()\-@^_`{}~]")


def has_amsdos_header(b):
    return len(b) >= 128 and (sum(b[:67]) & 0xFFFF) == struct.unpack_from("<H", b, 67)[0] and b[0] == 0


def short_name(name, used):
    base, ext = os.path.splitext(name.upper())
    base = VALID.sub("_", base)[:8] or "_"
    ext = VALID.sub("_", ext[1:])[:3]
    cand, n = (base, ext), 1
    while cand in used:
        tail = str(n)
        cand, n = (base[:8 - len(tail)] + tail, ext), n + 1
    used.add(cand)
    return cand


def blocks_needed(size):
    return max(1, (size + BLOCK - 1) // BLOCK)


def extents_needed(size):
    return max(1, (size + 16383) // 16384)


def build(files):
    """files: [(nombre8, ext3, datos)] -> imagen raw de 40 x 9 x 512."""
    img = bytearray(b"\xE5" * (TRACKS * SPT * SECSIZE))
    directory = bytearray(b"\xE5" * (DIR_ENTRIES * 32))
    nxt, slot = DIR_BLOCKS, 0
    for b8, e3, data in files:
        if not has_amsdos_header(data) and len(data) % 128:
            data = data + b"\x1A" * (128 - len(data) % 128)     # texto: relleno de fin de texto
        nblk = blocks_needed(len(data))
        if nxt + nblk > TOTAL_BLOCKS or slot + extents_needed(len(data)) > DIR_ENTRIES:
            raise ValueError(f"no cabe {b8}.{e3}")
        blocks = list(range(nxt, nxt + nblk))
        for k, blk in enumerate(blocks):
            chunk = data[k * BLOCK:(k + 1) * BLOCK]
            img[blk * BLOCK: blk * BLOCK + len(chunk)] = chunk
        nxt += nblk
        records = (len(data) + 127) // 128
        for ex in range(extents_needed(len(data))):
            e = bytearray(32)
            e[0] = 0                                             # usuario 0
            e[1:9] = b8.ljust(8).encode("latin1"); e[9:12] = e3.ljust(3).encode("latin1")
            e[12] = ex                                           # numero de extension (16 KB cada una)
            rc = min(128, records - ex * 128)
            e[15] = rc
            al = blocks[ex * 16:(ex + 1) * 16]
            e[16:16 + len(al)] = bytes(al)
            directory[slot * 32:(slot + 1) * 32] = e
            slot += 1
    img[0:len(directory)] = directory                            # bloques 0 y 1 = directorio
    return bytes(img), nxt - DIR_BLOCKS, slot


def stem(name):
    return name.upper().lstrip("!").split(".")[0]


def family(st):
    m = re.match(r"^(.+?)(SPR|SYS|TAB)$", st)                   # SPT1SPR / SPT1SYS / SPT1TAB
    return m.group(1) if m else st


def references(data):
    """Ficheros que nombra un programa (cadenas entre comillas: LOAD"KT.BIN", RUN"!DISCO")."""
    return {stem(r.decode("latin1")) for r in re.findall(rb'"(!?[A-Za-z0-9#$%&\-_]{1,8}(?:\.[A-Za-z0-9]{0,3})?)', data)}


def split(entries):
    """Reparte en discos. Van juntos: los ficheros con el mismo nombre, las familias
    SPR/SYS/TAB y cada programa con los ficheros que carga. Un fichero que cargan
    3 o mas programas (una biblioteca, como LASER) se copia en cada disco que lo
    necesita."""
    by_stem = {}
    for k, ent in enumerate(entries):
        by_stem.setdefault(stem(ent[3]), []).append(k)
    refs = {k: (references(ent[2]) & set(by_stem)) - {stem(ent[3])} for k, ent in enumerate(entries)}
    referrers = {}
    for k, r in refs.items():
        for st in r:
            referrers.setdefault(st, set()).add(stem(entries[k][3]))
    shared = {st for st, who in referrers.items() if len(who) >= 3}
    parent = list(range(len(entries)))
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]; x = parent[x]
        return x
    def union(a, b): parent[find(a)] = find(b)
    fam = {}
    for k, ent in enumerate(entries):
        st = stem(ent[3])
        if st in shared:
            continue
        fam.setdefault(family(st), []).append(k)
        for st2 in refs[k] - shared:
            for k2 in by_stem[st2]:
                union(k, k2)
    for ks in fam.values():
        for k in ks[1:]:
            union(ks[0], k)
    groups = {}
    for k, ent in enumerate(entries):
        if stem(ent[3]) not in shared:
            groups.setdefault(find(k), []).append(k)
    size = lambda k: blocks_needed(len(entries[k][2]) + (0 if has_amsdos_header(entries[k][2]) else 127))
    order = sorted(groups.values(), key=lambda g: -sum(size(k) for k in g))
    disks = []                                                   # [bloques, entradas, indices]
    for g in order:
        need = sorted({k2 for k in g for st in refs[k] & shared for k2 in by_stem[st]})
        for d in disks:
            extra = [k for k in need if k not in d[2]]
            nb = sum(size(k) for k in g + extra); ne = sum(extents_needed(len(entries[k][2])) for k in g + extra)
            if d[0] + nb <= DATA_BLOCKS and d[1] + ne <= DIR_ENTRIES:
                d[0] += nb; d[1] += ne; d[2].extend(g + extra); break
        else:
            nb = sum(size(k) for k in g + need); ne = sum(extents_needed(len(entries[k][2])) for k in g + need)
            if nb > DATA_BLOCKS or ne > DIR_ENTRIES:
                sys.exit(f"el grupo de {entries[g[0]][3]} no cabe en un disco ({nb} KB)")
            disks.append([nb, ne, g + need])
    # los que nadie carga (bibliotecas sin usar) tambien van
    placed = {k for d in disks for k in d[2]}
    for k in range(len(entries)):
        if k not in placed:
            for d in disks:
                if d[0] + size(k) <= DATA_BLOCKS and d[1] + 1 <= DIR_ENTRIES:
                    d[0] += size(k); d[1] += 1; d[2].append(k); break
            else:
                disks.append([size(k), 1, [k]])
    if shared:
        print("  bibliotecas compartidas (copiadas en cada disco que las usa): " + ", ".join(sorted(shared)))
    return [[entries[k] for k in sorted(d[2])] for d in disks]


def main():
    ap = argparse.ArgumentParser(description="Crea disquetes de AMSDOS (modo AMSTRAD del Aleste) a partir de una carpeta",
                                 formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    ap.add_argument("folder", help="carpeta con los ficheros")
    ap.add_argument("-o", "--output", required=True, help="imagen de salida (.DSK, en EDSK)")
    ap.add_argument("--split", action="store_true", help="repartir en varios discos si no caben en uno")
    a = ap.parse_args()

    used, entries = set(), []
    for name in sorted(os.listdir(a.folder)):
        path = os.path.join(a.folder, name)
        if os.path.isdir(path):
            print(f"  aviso: {name}/ es una carpeta, se salta")
            continue
        b8, e3 = short_name(name, used)
        entries.append((b8, e3, open(path, "rb").read(), name))

    disks = split(entries) if a.split else [entries]
    stem, ext = os.path.splitext(a.output)
    for n, files in enumerate(disks, 1):
        out = a.output if len(disks) == 1 else f"{stem}{n}{ext or '.DSK'}"
        try:
            raw, used_blk, slots = build([(b, e, d) for b, e, d, _ in files])
        except ValueError as err:
            sys.exit(f"{err}: no caben en un disco (178 KB, 64 entradas); prueba con --split")
        open(out, "wb").write(edsk(raw, TRACKS, 1, SPT, SECSIZE, FIRST_ID))
        names = ", ".join(f"{b}.{e}".rstrip(".") for b, e, _, _ in files)
        print(f"{out}: {len(files)} ficheros, {used_blk} KB de {DATA_BLOCKS} KB, {slots} entradas de {DIR_ENTRIES}")
        print(f"   {names}")


if __name__ == "__main__":
    main()
