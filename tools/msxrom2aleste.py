#!/usr/bin/env python3
"""
msxrom2aleste.py - Pasa cartuchos de MSX al Aleste 520EX y crea el disquete.

El 520EX no tiene VDP, ni slots, ni MSX-BASIC: los cartuchos de MSX se
adaptaron a mano (la gente del Aleste: King's Valley, Vampire Killer, Leo...).
Cada acceso al hardware del MSX se sustituye por una llamada a un cargador
.COM que emula el VDP por software (OUT (C),A al VDP -> NOP + RST 18h, por
ejemplo), y se reescriben a mano las partes que dependen de la temporizacion
del MSX (bucle principal, interrupcion, lectura del estado del VDP).

Esta herramienta:
  1. Reconoce la ROM por su MD5 y le aplica la conversion ya hecha
     (tools/msxpatches/*.txt: desplazamiento y bytes nuevos).
  2. Toma el cargador .COM de un disco del Aleste (msx-games.dsk): no se
     incluye aqui, no es de este proyecto.
  3. Con --dsk crea un disquete de arranque (tools/make_msxdisk.py) con el
     sistema de un disco de MSX-DOS, el cargador y el juego.
  --analyze lista, en una ROM no conocida, los accesos al hardware del MSX que
  habria que parchear (orientativo: un recorrido lineal tambien ve datos).

Ejemplos:
  python3 tools/msxrom2aleste.py KINGSVALLEY.ROM --games msx-games.dsk \\
          --dsk VALLEY.DSK --system alestedos-dev.dsk
  python3 tools/msxrom2aleste.py OTRO.ROM --analyze
"""
import argparse, glob, hashlib, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PATCH_DIR = os.path.join(HERE, "msxpatches")

# juegos conocidos: md5 de la ROM original -> parche, ficheros del cargador y nombre del juego en el disco
GAMES = {
    "c5698102c7e452b03fc7b9bb80a3768a": dict(
        title="King's Valley (Konami RC-727, 1985)", patch="kingsvalley1.txt",
        loader="VALLEY.COM", out=["VALLEY.DAT"], split=[16384]),
    "5d50c1c7bc164c3d01c41b0b8a501d72": dict(
        title="Vampire Killer - Akumajo Dracula (Konami RC-744, 1986), cartucho europeo",
        patch="vampirekiller.txt", loader="VKILLER.COM",
        out=["VKILLER.1", "VKILLER.2"], split=[16384, 114688]),
}


# otras versiones conocidas de esos juegos, para decir cual hace falta
OTHER = {
    "51d021af50c3a48124331a9fbc738b97": "Vampire Killer, cartucho japones (sha1 5460a88c...)",
    "273c3dff8315a6a4fced758f07d54aaa": "Vampire Killer, mini cartucho europeo (sha1 e78511a2...)",
    "3b4671f4c188c985e3817e7f6f2e7cb8": "Vampire Killer, version modificada JoySNES (sha1 83550d07...)",
    "803a5a442b9d690373bd9b98667b0218": "King's Valley, otra version (sha1 bbbb29b2...)",
}
NEEDED = {
    "Vampire Killer": "el cartucho europeo, sha1 b58e77f819dfbde72845801cff4b4e0a2f20ef5f "
                      "(openMSX softwaredb: GoodMSX, European Cartridge)",
    "King's Valley": "sha1 dda0d1bf4da8b159d08add8b7f4dc75da3e6e242",
}


# ---------------------------------------------------------------------------
# Conversion generica: motor de Konami de 16 KB (King's Valley, Yie Ar Kung-Fu...)
# Reglas sacadas de la conversion de King's Valley del Aleste:
#  1. El gancho de interrupcion (H.KEYI) espera al VDP con RDVDP; en el Aleste
#     RDVDP no hace nada: la interrupcion pasa a llamar solo al sonido y la logica
#     va a un bucle principal que termina en CALL 0003h (espera de cuadro).
#  2. El EI / JR $ del arranque salta a ese bucle (JR: mismos 2 bytes).
#  3. EXX / OUT (C),A / EXX (dato a la VRAM) -> EXX / NOP / RST 18h / EXX.
# El cargador es VALLEY.COM (King's Valley) con otro nombre de fichero.
KONAMI_HANDLER = re.compile(
    rb"\xCD\x3E\x01\xF3\xCD(..)\x21(..)\xCB\x46\x20\x0C\x34\xFB\xCD(..)\xCD(..)\xAF\x32\2"
    rb"\xCD\x3E\x01\xB7\xF3\xFC\1\xFB\xC9", re.S)


def konami16(rom):
    """Aplica las reglas del motor de Konami; devuelve (rom, informe) o (None, motivo)."""
    if len(rom) != 16384 or rom[:2] != b"AB":
        return None, "no es un cartucho de 16 KB"
    m = KONAMI_HANDLER.search(rom)
    if not m:
        return None, "no tiene el gancho de interrupcion del motor de Konami"
    d = bytearray(rom)
    h = m.start()
    snd, flag, logic1, logic2 = m.group(1), m.group(2), m.group(3), m.group(4)
    # interrupcion: el sonido y un cuadro mas en el contador (el indicador del juego)
    new = b"\xF3\xCD" + snd + b"\x21" + flag + b"\x34\xFB\xC9"      # DI / CALL / LD HL / INC (HL) / EI / RET
    loop = h + len(new)
    # bucle principal: un paso de logica por cada cuadro pendiente (se pone al dia), y
    # despues de cada paso CALL 0003h; el emulador solo redibuja los sprites una de
    # cada SPRITE_EVERY llamadas, asi que siempre se dibujan y la logica no espera
    new += (b"\x21" + flag +                       # loop: LD HL,contador
            b"\x7E\xB7\x28\xFC" +                   # w:    LD A,(HL) / OR A / JR Z,w
            b"\x35" +                                # DEC (HL)
            b"\xCD" + logic1 + b"\xCD" + logic2 +    # CALL logica x2
            b"\xCD\x03\x00" +                        # CALL 0003h: sprites (1 de cada SPRITE_EVERY)
            b"\x18" + bytes([(-(3 + 1 + 1 + 2 + 1 + 3 + 3 + 3 + 2)) & 0xFF]))   # JR loop
    new += b"\x00" * (len(m.group(0)) - 1 - len(new)) + b"\xC9"
    d[h:h + len(new)] = new
    rep = [f"gancho de interrupcion en {0x4000 + h:04X}h: sonido {snd[0] | snd[1] << 8:04X}h e indicador "
           f"{flag[0] | flag[1] << 8:04X}h (cuenta cuadros); bucle principal en {0x4000 + loop:04X}h: la logica se pone al dia y los sprites se dibujan siempre"]
    idles = [i for i in range(len(d) - 2) if d[i:i + 3] == b"\xFB\x18\xFE"]
    if len(idles) != 1:
        return None, f"no se encuentra un unico EI / JR $ ({len(idles)})"
    j = idles[0] + 1
    off = loop - (j + 2)
    if not -128 <= off <= 127:
        return None, "el bucle principal queda lejos del JR $"
    d[j:j + 2] = bytes([0x18, off & 0xFF])
    rep.append(f"EI / JR $ en {0x4000 + j:04X}h -> JR {0x4000 + loop:04X}h")
    outs = [i for i in range(len(d) - 4) if d[i:i + 4] == b"\xD9\xED\x79\xD9"]
    for i in outs:
        d[i + 1:i + 3] = b"\x00\xDF"
    rep.append("OUT (C),A a la VRAM -> NOP / RST 18h en " + ", ".join(f"{0x4000 + i + 1:04X}h" for i in outs))
    # la copia de la lista de sprites (E0B0h) a la VRAM (3B00h): el emulador la lee de la RAM
    spr = SPRITE_COPY.search(bytes(d))
    if spr:
        d[spr.start()] = 0xC9
        rep.append(f"copia de sprites E0B0h -> VRAM 3B00h anulada en {0x4000 + spr.start():04X}h")
    else:
        rep.append("AVISO: no se encuentra la copia de sprites E0B0h -> 3B00h")
    return bytes(d), rep


# LD BC,n / LD HL,3B00h / LD DE,E0B0h  o  LD DE,E0B0h / LD HL,3B00h / LD BC,n
SPRITE_COPY = re.compile(rb"\x01..\x21\x00\x3B\x11\xB0\xE0|\x11\xB0\xE0\x21\x00\x3B\x01..", re.S)
# en el emulador de VALLEY.COM, la rutina de 0003h dibuja los sprites una de cada 5 llamadas
VALLEY_SPRITE_RATE = (bytes.fromhex("3ae9043c32e904fe05"), 8)   # FE 05 -> FE SPRITE_EVERY
SPRITE_EVERY = 3                                                   # sprites a 60/3 = 20 por segundo


# GameBios v1 (VALLEY.COM): interrupciones durante el dibujo de los sprites.
# La rutina de sprites (0554h, 05A3h) dibujaba cada sprite con DI (~7 ms a
# 4 MHz, mas de dos periodos de la interrupcion del Aleste): se perdian
# interrupciones y la musica y el juego se ralentizaban. El DI hacia falta
# porque pone la pantalla en los cuartos de 4000h/8000h, donde esta la ROM del
# juego. Ahora la interrupcion es segura: una rutina nueva (al final del
# cargador: 0728h al ejecutar) guarda esas dos paginas (el mapper se puede
# leer), pone las normales (C5h, C6h), llama al gancho y al teclado (0177h) y las
# restaura; y los dos DI pasan a NOP.
VALLEY_EMU_BASE = 0x6D8 - 0x100                 # offset en VALLEY.COM de la pagina 0 del emulador
VALLEY_INT_SAFE = bytes.fromhex(
    "c5"            # PUSH BC
    "01007d" "ed78" "f5"    # LD BC,7D00h / IN A,(C) / PUSH AF   (pagina de 4000h)
    "067e" "ed78" "f5"      # LD B,7Eh / IN A,(C) / PUSH AF       (pagina de 8000h)
    "01c57d" "ed49"         # LD BC,7DC5h / OUT (C),C             (ROM del juego en 4000h)
    "01c67e" "ed49"         # LD BC,7EC6h / OUT (C),C
    "cd7701"                # CALL 0177h: gancho del juego y teclado
    "f1" "01007e" "ed79"    # POP AF / LD BC,7E00h / OUT (C),A    (restaura 8000h)
    "f1" "067d" "ed79"      # POP AF / LD B,7Dh / OUT (C),A       (restaura 4000h)
    "c1" "c9")              # POP BC / RET


def valley_int_safe(loader):
    """Aplica el cambio a una copia de VALLEY.COM; devuelve (cargador, informe)."""
    b = bytearray(loader)
    chk = {0x0171: b"\xCD\x77\x01", 0x0554: b"\xF3", 0x05A3: b"\xF3", 0x0162: b"\xF5\x3A\x8F\xFD"}
    for a, v in chk.items():
        if bytes(b[VALLEY_EMU_BASE + a: VALLEY_EMU_BASE + a + len(v)]) != v:
            return loader, f"AVISO: el emulador no es el esperado en {a:04X}h; sin el cambio de interrupciones"
    new = len(b) - VALLEY_EMU_BASE                     # direccion al ejecutar de la rutina nueva
    if new + len(VALLEY_INT_SAFE) > 0x2F00:
        return loader, "AVISO: no cabe la rutina de interrupcion segura"
    b[VALLEY_EMU_BASE + 0x0171: VALLEY_EMU_BASE + 0x0174] = bytes([0xCD, new & 0xFF, new >> 8])
    b[VALLEY_EMU_BASE + 0x0554] = 0x00
    b[VALLEY_EMU_BASE + 0x05A3] = 0x00
    b += VALLEY_INT_SAFE
    return bytes(b), f"interrupciones durante los sprites: rutina segura en {new:04X}h, sin DI en el dibujo"


# GameBios v1: fin de lista de sprites (Y = D0h). En el VDP, un sprite con
# Y = D0h termina la lista: los de detras no se dibujan. Yie Ar lo usa (505Dh,
# 508Fh); el emulador de King's Valley no, y dibujaba los datos viejos de detras
# (piezas sueltas por la pantalla, y sus borrados sobre el fondo). Antes de cada
# redibujado, una rutina copia la lista del juego (E0B0h, 32 entradas) a una
# intermedia con esa entrada y las siguientes ocultas (Y = E0h, que el emulador
# no dibuja y borra de su sitio anterior), y el emulador lee la intermedia.
VALLEY_SPR_PRE_AT = 0x04F4                      # XOR A / LD (04E9h),A -> CALL rutina / NOP
VALLEY_SPR_BASES = {0x04FC: 0x00, 0x0509: 0x18, 0x0516: 0x10}   # LD IX,E0B0h / E0C8h / E0C0h


def valley_sprite_list(loader, tmp=0x0780):
    b = bytearray(loader)
    chk = {VALLEY_SPR_PRE_AT: b"\xAF\x32\xE9\x04", 0x04FC: b"\xDD\x21\xB0\xE0",
           0x0509: b"\xDD\x21\xC8\xE0", 0x0516: b"\xDD\x21\xC0\xE0"}
    for a, v in chk.items():
        if bytes(b[VALLEY_EMU_BASE + a: VALLEY_EMU_BASE + a + len(v)]) != v:
            return loader, f"AVISO: el emulador no es el esperado en {a:04X}h; sin el fin de lista de sprites"
    pre = len(b) - VALLEY_EMU_BASE
    byte_copy = b"\x7E\x12\x23\x13"                           # LD A,(HL) / LD (DE),A / INC HL / INC DE
    body = (b"\x7E\xFE\xD0\x20\x02\x0E\xE0"                    # L1: LD A,(HL) / CP D0h / JR NZ,+2 / LD C,E0h
            b"\x79\xB7\x20\x01\x7E"                            #     LD A,C / OR A / JR NZ,+1 / LD A,(HL)
            b"\x12\x23\x13" + byte_copy * 3)                   #     LD (DE),A / INC HL / INC DE / 3 bytes mas
    code = (b"\xAF\x32\xE9\x04"                                # XOR A / LD (04E9h),A (lo que habia)
            b"\xC5\xD5\xE5"                                    # PUSH BC / DE / HL
            b"\x21\xB0\xE0" + bytes([0x11, tmp & 0xFF, tmp >> 8]) +   # LD HL,E0B0h / LD DE,intermedia
            b"\x06\x20\x0E\x00" + body +                       # LD B,32 / LD C,0 (0: visible)
            bytes([0x10, (-(len(body) + 2)) & 0xFF]) +         # DJNZ L1
            b"\xE1\xD1\xC1\xC9")                               # POP HL / DE / BC / RET
    if pre + len(code) > tmp or tmp + 0x80 > 0x2F00:
        return loader, "AVISO: no cabe la rutina del fin de lista de sprites"
    b[VALLEY_EMU_BASE + VALLEY_SPR_PRE_AT: VALLEY_EMU_BASE + VALLEY_SPR_PRE_AT + 4] = bytes([0xCD, pre & 0xFF, pre >> 8, 0x00])
    for a, off in VALLEY_SPR_BASES.items():
        v = tmp + off
        b[VALLEY_EMU_BASE + a + 2: VALLEY_EMU_BASE + a + 4] = bytes([v & 0xFF, v >> 8])
    b += code
    return bytes(b), f"fin de lista de sprites (D0h): rutina en {pre:04X}h, lista intermedia en {tmp:04X}h"


def read_patch(path):
    patch = []
    for line in open(path):
        line = line.split("#")[0].strip()
        if line:
            off, data = line.split()
            patch.append((int(off, 16), bytes.fromhex(data)))
    return patch


def fat_file(img, name):
    """Lee un fichero de la raiz de una imagen FAT12 raw de MSX-DOS."""
    sys.path.insert(0, HERE)
    from make_msxdisk import read_fat_files
    files = read_fat_files(img)
    return files.get(name.upper(), (None,))[0]


def analyze(rom):
    """Accesos al hardware del MSX (recorrido lineal: orientativo)."""
    try:
        from z80dis import z80
    except ImportError:
        sys.exit("--analyze necesita el paquete z80dis (pip install z80dis)")
    base = 0x4000
    names = {0x0C: "RDSLT", 0x24: "ENASLT", 0x41: "DISSCR", 0x44: "ENASCR", 0x47: "WRTVDP", 0x4A: "RDVRM",
             0x4D: "WRTVRM", 0x50: "SETRD", 0x53: "SETWRT", 0x56: "FILVRM", 0x59: "LDIRMV", 0x5C: "LDIRVM",
             0x5F: "CHGMOD", 0x62: "CHGCLR", 0x69: "CLRSPR", 0x72: "INIGRP", 0x90: "GICINI", 0x93: "WRTPSG",
             0x96: "RDPSG", 0xD5: "GTSTCK", 0xD8: "GTTRIG", 0x138: "RSLREG", 0x13B: "WSLREG", 0x13E: "RDVDP",
             0x141: "SNSMAT"}
    found = {"OUT (C) (VDP probable)": [], "OUT (n) al VDP/PSG": [], "IN del VDP/PSG": [],
             "llamadas a la BIOS del MSX": [], "escrituras a un mapper (6000-BFFF)": [], "ganchos de interrupcion (FD9A/FD9F)": []}
    a = 0
    while a < len(rom):
        dec = z80.decode(rom[a:a + 4], base + a)
        L = max(1, dec.len)
        txt = z80.disasm(dec)
        b = rom[a:a + L]
        where = f"{base + a:04X}"
        if b[:2] == b"\xED\x79" or b[:2] == b"\xED\x41" or b[:2] == b"\xED\x51":
            found["OUT (C) (VDP probable)"].append(where)
        elif b[0] == 0xD3 and L == 2 and b[1] in (0x98, 0x99, 0x9A, 0x9B, 0xA0, 0xA1):
            found["OUT (n) al VDP/PSG"].append(f"{where} {b[1]:02X}h")
        elif b[0] == 0xDB and L == 2 and b[1] in (0x98, 0x99, 0xA2):
            found["IN del VDP/PSG"].append(f"{where} {b[1]:02X}h")
        elif b[0] in (0xCD, 0xC3) and L == 3:
            t = b[1] | b[2] << 8
            if t in names:
                found["llamadas a la BIOS del MSX"].append(f"{where} {names[t]}")
            elif t in (0xFD9A, 0xFD9F):
                found["ganchos de interrupcion (FD9A/FD9F)"].append(where)
        elif b[0] == 0x32 and L == 3:
            t = b[1] | b[2] << 8
            if 0x6000 <= t < 0xC000 and t & 0x07FF == 0:
                found["escrituras a un mapper (6000-BFFF)"].append(f"{where} ({t:04X}h)")
            elif t in (0xFD9A, 0xFD9F):
                found["ganchos de interrupcion (FD9A/FD9F)"].append(where)
        a += L
    print(f"ROM de {len(rom)} bytes, cabecera {rom[:2]!r}, inicio {rom[2] | rom[3] << 8:04X}h")
    for k, v in found.items():
        print(f"  {k}: {len(v)}" + (": " + ", ".join(v[:12]) + (" ..." if len(v) > 12 else "") if v else ""))
    print("Conversion: los OUT (C),A al VDP se cambian por NOP + RST 18h del cargador; las\n"
          "llamadas a la BIOS, el mapper y la interrupcion necesitan revisar el juego a mano.")


def main():
    ap = argparse.ArgumentParser(description="Pasa cartuchos de MSX al Aleste 520EX y crea el disquete",
                                 formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    ap.add_argument("rom", help="ROM del cartucho de MSX")
    ap.add_argument("--analyze", action="store_true", help="listar los accesos al hardware del MSX")
    ap.add_argument("--games", metavar="DISCO", help="disco del Aleste con los cargadores (msx-games.dsk)")
    ap.add_argument("-o", "--outdir", default=".", help="carpeta para los ficheros convertidos")
    ap.add_argument("--dsk", metavar="DISCO", help="crear un disquete con el juego")
    ap.add_argument("--system", metavar="DISCO", help="disco de MSX-DOS del que tomar el sistema (obligatorio con --dsk)")
    ap.add_argument("--autostart", choices=("command", "bat", "no"), default="command",
                    help="como arranca el juego: command (el cargador hace de COMMAND.COM: arranca solo "
                         "y sin el A> de MSX-DOS; por defecto), bat (AUTOEXEC.BAT) o no")
    ap.add_argument("--2drives", dest="two", action="store_true", help="segunda disquetera en la BDOS (para --dsk)")
    ap.add_argument("--name", help="nombre del juego en el disco (8 letras; por defecto, el de la ROM)")
    a = ap.parse_args()

    rom = open(a.rom, "rb").read()
    md5 = hashlib.md5(rom).hexdigest()
    if a.analyze:
        analyze(rom)
        return
    game = GAMES.get(md5)
    if not game and md5 in OTHER:
        name = OTHER[md5]
        need = next(v for k, v in NEEDED.items() if name.startswith(k))
        sys.exit(f"Es {name}: la conversion del Aleste es de otra version.\n"
                 f"Hace falta {need}.\nTienen el codigo desplazado: el parche no se puede aplicar.")
    if not game:                                           # Metal Gear (MSX2): GameBios v2
        sys.path.insert(0, os.path.join(HERE, "gb2"))
        import gb2build, metalgear
        bs = gb2build.symbols("gb2bank")
        try:
            conv, rep = metalgear.convert(rom, (bs["BANK6"], bs["BANK8"], bs["BANKA"]))
        except ValueError:
            conv = None
        if conv is not None:
            name = re.sub(r"[^A-Z0-9]", "", (a.name or "MGEAR").upper())[:8]
            print(f"Metal Gear (MSX2): conversion con la GameBios v2 ({name})")
            for r in rep:
                print("  " + r)
            game = dict(title=name, loader="VKILLER.COM", loader_as=f"{name}.COM", gb2=metalgear,
                        out=[f"{name}.DAT"], split=[131072], data=conv)
    if not game:
        conv, rep = konami16(rom)
        if conv is not None:
            name = re.sub(r"[^A-Z0-9]", "", (a.name or os.path.splitext(os.path.basename(a.rom))[0]).upper())[:8] or "JUEGO"
            print(f"ROM no conocida: conversion generica del motor de Konami de 16 KB ({name})")
            for r in rep:
                print("  " + r)
            print("  ATENCION: conversion automatica, sin probar: los detalles propios del juego\n"
                  "  (colores, sprites, lecturas de la VRAM) pueden necesitar arreglos a mano.")
            game = dict(title=name, loader="VALLEY.COM", loader_as=f"{name}.COM", fcb=name,
                        out=[f"{name}.DAT"], split=[16384], data=conv)
    if not game:
        known = "\n".join(f"  {g['title']}: md5 {m}" for m, g in GAMES.items())
        sys.exit(f"ROM no conocida (md5 {md5}). Conversiones disponibles:\n{known}\n"
                 "Prueba con --analyze para ver que habria que parchear.")
    if "data" in game:
        data = bytearray(game["data"])
    else:
        print(f"{game['title']}")
        data = bytearray(rom)
        patch = read_patch(os.path.join(PATCH_DIR, game["patch"]))
        for off, new in patch:
            data[off:off + len(new)] = new
        print(f"  {sum(len(n) for _, n in patch)} bytes cambiados en {len(patch)} sitios")

    os.makedirs(a.outdir, exist_ok=True)
    pos, written = 0, []
    for name, size in zip(game["out"], game["split"]):
        open(os.path.join(a.outdir, name), "wb").write(data[pos:pos + size])
        written.append(name); pos += size
    if a.games:
        loader = fat_file(open(a.games, "rb").read(), game["loader"])
        if loader is None:
            sys.exit(f"{a.games}: no tiene {game['loader']}")
        if "gb2" in game:                                  # cargador propio con la GameBios v2
            import gb2build
            g = game["gb2"]
            base, blob, entry, dst = gb2build.sprite_limit_blob(g.SPRITE_ATTR, g.SPRITE_LIMIT_LINES)
            assert entry == g.SPRITE_LIMIT
            # la GameBios lee la lista intermedia que prepara la rutina del limite
            gbios = gb2build.gamebios_sprites(gb2build.gamebios_from_vkiller(loader), dst, g.SPRITE_COLOR)
            loader, _, msg = gb2build.build(game["title"], g.Q1_BANKS, g.Q2_LOW, g.Q2_HIGH, gbios, extra=(base, blob))
            msg += (f"; sprites: lista {g.SPRITE_ATTR:04X}h con limite de 8 por linea en las lineas "
                    f"{g.SPRITE_LIMIT_LINES[0]}-{g.SPRITE_LIMIT_LINES[1]} (rutina {entry:04X}h) -> {dst:04X}h; colores {g.SPRITE_COLOR:04X}h")
            print("  cargador propio (tools/gb2) con la GameBios de VKILLER.COM: " + msg)
        elif "fcb" in game:                                # el cargador abre otro fichero
            i = loader.find(b"VALLEY  DAT")
            if i < 0:
                sys.exit(f"{game['loader']}: no se encuentra el nombre VALLEY  DAT")
            loader = loader[:i] + game["fcb"].ljust(8).encode() + b"DAT" + loader[i + 11:]
            loader, msg = valley_int_safe(loader)
            print("  " + msg)
            loader, msg = valley_sprite_list(loader)
            print("  " + msg)
            sig, k = VALLEY_SPRITE_RATE
            j = loader.find(sig)
            if j >= 0:
                loader = loader[:j + k] + bytes([SPRITE_EVERY]) + loader[j + k + 1:]
                print(f"  sprites del emulador: una de cada {SPRITE_EVERY} llamadas ({60 // SPRITE_EVERY} por segundo)")
        lname = game.get("loader_as", game["loader"])
        open(os.path.join(a.outdir, lname), "wb").write(loader)
        written.append(lname)
        game["loader"] = lname
    else:
        print(f"  (sin --games no hay cargador: copia {game['loader']} del disco msx-games del Aleste)")
    print("  -> " + ", ".join(os.path.join(a.outdir, w) for w in written))

    if a.dsk:
        if not a.games:
            sys.exit("--dsk necesita --games (el cargador)")
        if not a.system:
            sys.exit("--dsk necesita --system DISCO: sin el sector de arranque, BIOS.SYS, BDOS.SYS\n"
                     "y COMMAND.COM de un disco de MSX-DOS del 520EX, el disquete no arranca")
        with tempfile.TemporaryDirectory() as tmp:
            for w in written:
                shutil.copy(os.path.join(a.outdir, w), tmp)
            if a.autostart == "bat":                       # el juego arranca con AUTOEXEC.BAT
                with open(os.path.join(tmp, "AUTOEXEC.BAT"), "wb") as f:
                    f.write(os.path.splitext(game["loader"])[0].encode() + b"\r\n\x1a")
            elif a.autostart == "command":                 # MSX-DOS carga COMMAND.COM: es el cargador
                shutil.copy(os.path.join(tmp, game["loader"]), os.path.join(tmp, "COMMAND.COM"))
            cmd = [sys.executable, os.path.join(HERE, "make_msxdisk.py"), tmp, "-o", a.dsk, "--system", a.system]
            if a.two:
                cmd.append("--2drives")
            r = subprocess.run(cmd, capture_output=True, text=True)
            print(r.stdout.strip().splitlines()[-1] if r.stdout else r.stderr)
            if r.returncode:
                sys.exit(r.stderr)
        print({"command": "  arranca solo (el cargador hace de COMMAND.COM; el disco no da el A> de MSX-DOS)",
               "bat": "  arranca solo (AUTOEXEC.BAT)",
               "no": f"  en MSX-DOS: {os.path.splitext(game['loader'])[0]}"}[a.autostart])


if __name__ == "__main__":
    main()
