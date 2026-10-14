"""
metalgear.py - Conversion de Metal Gear (MSX2, Konami RC-750, 1987) al Aleste
520EX con la GameBios v2 (doc/09-gamebios-v2-metal-gear.md).

Cada cambio comprueba antes los bytes originales: una version distinta del
juego no se parchea a ciegas. Probado con la traduccion al espanol (openMSX:
sha1 aa881a29...).
"""

# Bancos del mapper de Konami que usa el juego (inventario: doc/gamebios)
Q1_BANKS = [1, 4, 7, 10, 13]            # 6000h (con el banco 0 fijo en 4000h)
Q2_LOW = [2, 5, 8, 11, 14]              # 8000h
Q2_HIGH = [3, 6, 9, 12, 15]             # A000h

SPRITE_ATTR = 0xEA00                    # lista de sprites en RAM: atributos (32 x 4 bytes)
SPRITE_COLOR = 0xE800                   # y colores (32 x 16 bytes, uno por linea)
SPRITE_LIMIT_LINES = (192, 211)         # truco del limite de 8 sprites: lineas del marcador
SPRITE_LIMIT = 0x0F70                   # rutina del limite (tools/gb2/gb2spr.asm), antes de los sprites
FRAME_COUNTER = 0x0F60                  # en la pagina de la GameBios (siempre puesta)
MAIN_LOOP = 0x4F06                      # hueco de la rutina LINE sustituida (4EFCh), tras su envoltorio


def jp(a):
    return bytes([0xC3, a & 0xFF, a >> 8])


def call(a):
    return bytes([0xCD, a & 0xFF, a >> 8])


def main_loop(at):
    """Bucle principal: un paso de logica por cuadro pendiente, como la interrupcion original."""
    c = FRAME_COUNTER
    code = bytearray()
    code += b"\xFB"                                         # EI
    loop = at + len(code)
    code += bytes([0x21, c & 0xFF, c >> 8])                 # loop: LD HL,contador
    code += b"\x7E\xB7\x28\xFC"                             # w: LD A,(HL) / OR A / JR Z,w
    code += b"\x35"                                         # DEC (HL)
    code += b"\x3E\x01\x32\x05\xC0"                         # LD A,1 / LD (C005h),A  (logica en marcha)
    code += call(0x6672)                                    # la logica del juego
    code += b"\xAF\x32\x05\xC0"                             # XOR A / LD (C005h),A
    code += call(SPRITE_LIMIT)                              # lista intermedia con el limite de 8 por linea
    code += call(0x0003)                                    # sprites de la GameBios
    code += jp(loop)
    return bytes(code)


def patches(bank_entries):
    """Lista de (offset en la ROM, bytes originales, bytes nuevos, descripcion)."""
    B6, B8, BA = bank_entries
    P = []
    win = {b"\x32\x00\x60": B6, b"\x32\x00\x80": B8, b"\x32\x00\xA0": BA}
    # 1. Escrituras al mapper -> CALL a la rutina de bancos
    for off, orig in ((0x01A3, b"\x32\x00\xA0"), (0x01B2, b"\x32\x00\x60"), (0x01B6, b"\x32\x00\x80"),
                      (0x01BF, b"\x32\x00\x60"), (0x01C5, b"\x32\x00\x80"), (0x0256, b"\x32\x00\x60"),
                      (0x025C, b"\x32\x00\x80"), (0x0262, b"\x32\x00\xA0"), (0x028F, b"\x32\x00\x60"),
                      (0x0299, b"\x32\x00\x80"), (0x02A5, b"\x32\x00\x60"), (0x02A9, b"\x32\x00\x80"),
                      (0x092C, b"\x32\x00\xA0")):
        P.append((off, orig, call(win[orig]), f"banco: LD ({orig[2]:02X}00h),A -> CALL {win[orig]:04X}h"))
    # 2. Comandos del V9938 -> servicios de la GameBios; espera del VDP -> RET
    for addr, svc, name in ((0x4E66, 0x0200, "paleta"), (0x4EFC, 0x0204, "LINE"), (0x4F2F, 0x0208, "LINE"),
                            (0x4F91, 0x020C, "HMMV"), (0x4FCD, 0x0210, "HMMM"), (0x5011, 0x0218, "copia")):
        # Las rutinas originales no cambian BC, DE ni HL (solo los envian al VDP), y
        # las llamadas cuentan con ello (DrawRadioLeds suma 8 a E y D entre copias);
        # los servicios de la GameBios no los conservan: envoltorio que los guarda.
        # Paleta: en el MSX2, con R8 = 02h (TP = 0) el color 0 es transparente y se ve
        # el fondo (R7, negro): su valor en la paleta no se muestra. La GameBios si lo
        # aplicaria al color 0 del Aleste (el marcador salia morado): se ignora.
        pre = b"\xB7\xC8" if svc == 0x0200 else b""                    # OR A / RET Z
        P.append((addr - 0x4000, None, pre + b"\xC5\xD5\xE5" + call(svc) + b"\xE1\xD1\xC1\xC9",
                  f"{name}: CALL {svc:04X}h conservando BC, DE y HL" + (" (sin el color 0)" if pre else "")))
    P.append((0x4ED2 - 0x4000, b"\x3E\x02\xCD", b"\xC9", "espera del VDP: RET"))
    # 3. Biblioteca de video
    P.append((0x4D3E - 0x4000, b"\xCD\xB2\x4D\xCD\x51\x4D\x08",
              b"\xE5\xCD\x59\x00\xE1\xAF\x47\xC9", "copia VRAM -> RAM: LDIRMV"))       # PUSH HL / CALL 0059h / POP HL / XOR A / LD B,A / RET
    P.append((0x4D59 - 0x4000, b"\xEB\xCD\x93\x4D\xCD\x51\x4D",
              b"\xD5\xCD\x5C\x00\xD1\xAF\x47\xC9", "copia RAM -> VRAM: LDIRVM"))       # PUSH DE / CALL 005Ch / POP DE / XOR A / LD B,A / RET
    P.append((0x4D93 - 0x4000, b"\xC5\x3A\x07\x00\x3C", jp(0x0171), "direccion de escritura: JP 0171h (NSTWRT)"))
    P.append((0x4DB2 - 0x4000, b"\xC5\x3A\x07\x00\x3C", jp(0x016E), "direccion de lectura: JP 016Eh (NSETRD)"))
    for addr, kind in ((0x4D66, "OTIR"), (0x4D7C, "OUT"), (0x4D8F, "OUT"), (0x4DEB, "OTIR"), (0x4DF2, "OUT"),
                       (0x53CC, "OTIR"), (0x53D4, "OUT")):
        orig = b"\xED\xB3" if kind == "OTIR" else b"\xED\x79"
        P.append((addr - 0x4000, orig, b"\xD7\x00" if kind == "OTIR" else b"\xDF\x00",
                  f"{kind} al VDP en {addr:04X}h: {'RST 10h' if kind == 'OTIR' else 'RST 18h'}"))
    for off in (0x1F8FD, 0x1F90E):                                          # banco 15 (en A000h)
        P.append((off, b"\xED\xB3", b"\xD7\x00", f"OTIR al VDP en el banco 15 ({off:05X}): RST 10h"))
    # 4. Sprites (como la conversion de King's Valley II, LEO): la GameBios dibuja
    #    desde la lista en RAM (EA00h/E800h): la rutina que la subia a la VRAM con
    #    rotacion (banco 15, B8DEh) se anula, y el borrado inicial de las tablas de
    #    sprites de la VRAM (4E2Ch) pasa a ocultar la lista en RAM (Y = E0h).
    P.append((0x1F8DE, b"\x21\x0F\xC0\x7E\xC6\x68\xE6\x78", b"\xC9", "subida de sprites a la VRAM (banco 15, B8DEh): RET"))
    a = SPRITE_ATTR
    P.append((0x4E2C - 0x4000, b"\x21\x00\xF6\x3E\xE0\x01\x80\x00\xCD\x6C\x4D",
              bytes([0x21, a & 0xFF, a >> 8, 0x11, (a + 1) & 0xFF, a >> 8, 0x01, 0x7F, 0x00, 0x36, 0xE0, 0xED, 0xB0, 0xC9]),
              f"borrado de las tablas de sprites -> lista en RAM {a:04X}h a E0h"))
    # 5. Interrupcion: tras la musica, contar un cuadro; bucle principal
    c = FRAME_COUNTER
    P.append((0x41C8 - 0x4000, b"\x21\x05\xC0\xCB\x46\xC2\xD9",
              bytes([0x21, c & 0xFF, c >> 8, 0x34]) + jp(0x41D9), "interrupcion: cuenta un cuadro (logica al bucle principal)"))
    P.append((0x4245 - 0x4000, b"\xFB\x18\xFE", jp(MAIN_LOOP), f"EI / JR $ -> JP {MAIN_LOOP:04X}h (bucle principal)"))
    P.append((MAIN_LOOP - 0x4000, None, main_loop(MAIN_LOOP), "bucle principal: logica (6672h) por cuadro y sprites (0003h)"))
    return P


def convert(rom, bank_entries):
    """Devuelve (ROM parcheada, informe) o lanza ValueError si algun sitio no es el esperado."""
    if len(rom) != 131072 or rom[:2] != b"AB" or rom[2:4] != b"\xF3\x41":
        raise ValueError("no parece Metal Gear de MSX2 (128 KB, inicio 41F3h)")
    out = bytearray(rom)
    rep = []
    for off, orig, new, desc in patches(bank_entries):
        if orig is not None and bytes(out[off:off + len(orig)]) != orig:
            raise ValueError(f"{desc}: en {off:05X} no estan los bytes esperados")
        out[off:off + len(new)] = new
        rep.append(desc)
    return bytes(out), rep
