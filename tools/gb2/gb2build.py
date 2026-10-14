"""
gb2build.py - Monta el cargador generico de la GameBios v2 (gb2load.asm) para
un juego de MSX2 con mapper de Konami.

Las paginas compuestas de 16 KB salen de los bancos que el juego pone en cada
ventana: cuarto de 4000h = banco 0 + banco de 6000h (Q1), cuarto de 8000h =
banco de 8000h + banco de A000h (Q2). La GameBios y sus tablas se toman de un
cargador del Aleste (VKILLER.COM): no se incluyen en este proyecto.

Usa los binarios ya ensamblados (gb2load.bin, gb2bank.bin) y sus simbolos, asi
que no hace falta pasmo (las fuentes estan al lado).
"""
import os, re

HERE = os.path.dirname(os.path.abspath(__file__))
FIRST_PAGE = 0x20                       # paginas compuestas: 20h en adelante
LAST_PAGE = 0x3E                        # 3Fh es la RAM del juego

# GameBios v2 dentro de VKILLER.COM (Vampire Killer, 1995): ver doc/gamebios
VKILLER_GB = dict(gb=(0x3F5, 0xDC2), t3e=0x12DF, t3f=0x13DF, t2f=0x14DF)


def symbols(name):
    sym = {}
    for line in open(os.path.join(HERE, name + ".sym")):
        m = re.match(r"(\w+)\s+EQU\s+0*([0-9A-Fa-f]+)H", line)
        if m:
            sym[m.group(1)] = int(m.group(2), 16)
    return sym


def gamebios_from_vkiller(com):
    """GameBios v2 y sus tablas de un VKILLER.COM."""
    def at(addr, n):
        return com[addr - 0x100: addr - 0x100 + n]
    a, n = VKILLER_GB["gb"]
    gb = at(a, n)
    if len(gb) != n or gb[0x47] != 0xC3 or gb[0x38] != 0xC3:
        raise ValueError("VKILLER.COM no tiene la GameBios v2 esperada")
    return gb, at(VKILLER_GB["t3e"], 256), at(VKILLER_GB["t3f"], 256), at(VKILLER_GB["t2f"], 256)


# La rutina de sprites de la GameBios lee la lista de sprites del juego en RAM
# (atributos: 4 bytes por sprite; colores: 16 bytes por sprite, una por linea).
# En VKILLER.COM son las de Vampire Killer (D600h y D400h); en LEO.COM, las de
# King's Valley II (E800h y D200h). Para otro juego se cambian estas direcciones.
VKILLER_SPRITES = {                     # offset en la GameBios: (bytes originales, que cambia)
    0x0452: (b"\xDD\x21\x7C\xD6", "attr"), 0x0475: (b"\xDD\x21\x7C\xD6", "attr"),
    0x050D: (b"\x21\x00\xD6", "attr"), 0x0510: (b"\x11\x01\xD6", "attr"),
    0x0AC8: (b"\xDD\x21\x00\xD6", "attr"),
    0x0B2E: (b"\x11\x00\xD4", "color"), 0x0BEE: (b"\x11\x00\xD4", "color"),
}


def gamebios_sprites(gamebios, attr, color):
    """Cambia en la GameBios de VKILLER.COM las direcciones de la lista de sprites (alineadas a 256 bytes)."""
    gb, t3e, t3f, t2f = gamebios
    gb = bytearray(gb)
    for off, (orig, what) in VKILLER_SPRITES.items():
        if bytes(gb[off:off + len(orig)]) != orig:
            raise ValueError(f"GameBios: en {off:04X}h no esta la direccion de sprites esperada")
        gb[off + len(orig) - 1] = (attr if what == "attr" else color) >> 8
    return bytes(gb), t3e, t3f, t2f


def layout(q1_banks, q2_low, q2_high):
    """Paginas compuestas: {('q1', n): pagina, ('q2', m, k): pagina} y la tabla de destinos por banco."""
    pages, p = {}, FIRST_PAGE
    for n in q1_banks:
        pages[("q1", n)] = p; p += 1
    for m in q2_low:
        for k in q2_high:
            pages[("q2", m, k)] = p; p += 1
    if p - 1 > LAST_PAGE:
        raise ValueError(f"demasiadas paginas compuestas ({p - FIRST_PAGE})")
    dest = {b: [] for b in range(16)}
    for key, pg in pages.items():
        if key[0] == "q1":
            dest[0].append((pg, 0x40)); dest[key[1]].append((pg, 0x60))
        else:
            dest[key[1]].append((pg, 0x40)); dest[key[2]].append((pg, 0x60))
    return pages, dest


def sprite_limit_blob(src, lines):
    """Rutina del limite de 8 sprites por linea (gb2spr.asm) con la lista del juego y el tramo de lineas."""
    ss = symbols("gb2spr")
    blob = bytearray(open(os.path.join(HERE, "gb2spr.bin"), "rb").read())
    base = 0x0F68
    blob[ss["src"] - base: ss["src"] - base + 2] = bytes([src & 0xFF, src >> 8])
    lo, hi = lines
    for k in ("lo1", "lo2", "lo3"):
        blob[ss[k] - base] = lo
    for k in ("hi1", "hi2", "hi3"):
        blob[ss[k] - base] = hi + 1
    blob[ss["lo4"] - base] = lo
    blob[ss["nlin"] - base] = hi - lo + 1
    if base + len(blob) > ss["CNT"] or ss["DST"] < ss["CNT"] + 0x100 and ss["DST"] + 0x80 > ss["CNT"]:
        raise ValueError("la rutina del limite de sprites pisa sus tablas")
    return base, bytes(blob), ss["SPRLIM"], ss["DST"]


def build(fcb_name, q1_banks, q2_low, q2_high, gamebios, extra=None):
    """Devuelve (COM del cargador, simbolos de la rutina de bancos, informe).
    extra: (direccion, bytes) que se anaden a la pagina de la GameBios detras de la rutina de bancos."""
    gb, t3e, t3f, t2f = gamebios
    pages, dest = layout(q1_banks, q2_low, q2_high)
    for b, d in dest.items():
        if len(d) > 5:
            raise ValueError(f"el banco {b} va en {len(d)} paginas (maximo 5)")
    # rutina de bancos (0E00h al ejecutar) con sus tablas
    bs = symbols("gb2bank")
    bank = bytearray(open(os.path.join(HERE, "gb2bank.bin"), "rb").read())
    q1 = lambda n: 0xC0 | pages.get(("q1", n), pages[("q1", q1_banks[0])])
    def q2(m, k):
        if ("q2", m, k) in pages: return 0xC0 | pages[("q2", m, k)]
        if m in q2_low: return 0xC0 | pages[("q2", m, q2_high[0])]       # combinacion de paso
        return 0xC0 | pages[("q2", q2_low[0], q2_high[0])]
    for n in range(16):
        bank[bs["q1tab"] - 0x0E00 + n] = q1(n)
    for m in range(16):
        for k in range(16):
            bank[bs["q2tab"] - 0x0E00 + m * 16 + k] = q2(m, k)
    bank[bs["cur6"] - 0x0E00] = q1_banks[0]
    bank[bs["cur8"] - 0x0E00] = q2_low[0]
    bank[bs["curA"] - 0x0E00] = q2_high[0]
    # cargador
    ls = symbols("gb2load")
    com = bytearray(open(os.path.join(HERE, "gb2load.bin"), "rb").read())
    off = lambda sym: ls[sym] - 0x100
    com[off("fcb") + 1: off("fcb") + 12] = fcb_name.ljust(8)[:8].encode() + b"DAT"
    com[off("q1init")] = q1(q1_banks[0])
    com[off("q2init")] = q2(q2_low[0], q2_high[0])
    for b in range(16):
        e = bytearray(11)
        for i, (pg, half) in enumerate(dest[b]):
            e[2 * i] = 0xC0 | pg; e[2 * i + 1] = half
        com[off("dest") + 11 * b: off("dest") + 11 * b + 11] = e
    def put(sym, data, length_sym=None):
        addr = 0x100 + len(com)
        com[off(sym): off(sym) + 2] = bytes([addr & 0xFF, addr >> 8])
        if length_sym:
            com[off(length_sym): off(length_sym) + 2] = bytes([len(data) & 0xFF, len(data) >> 8])
        com.extend(data)
    put("p_gb", gb, "p_gblen")
    put("p_t3e", t3e); put("p_t3f", t3f); put("p_t2f", t2f)
    if extra:
        base, blob = extra
        if base < 0x0E00 + len(bank):
            raise ValueError("el anadido pisa la rutina de bancos")
        bank = bank + bytes(base - 0x0E00 - len(bank)) + blob
    put("p_bank", bytes(bank), "p_banklen")
    if 0x100 + len(com) > 0x4000:
        raise ValueError("el cargador no cabe por debajo de 4000h")
    rep = (f"{len(pages)} paginas compuestas ({FIRST_PAGE:02X}h-{FIRST_PAGE + len(pages) - 1:02X}h); "
           f"bancos: BANK6={bs['BANK6']:04X}h BANK8={bs['BANK8']:04X}h BANKA={bs['BANKA']:04X}h")
    return bytes(com), bs, rep
