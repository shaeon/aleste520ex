#!/usr/bin/env python3
"""
make_cdt.py - Fabrica una cinta CDT (TZX del Amstrad CPC) con un fichero.

Usa el formato de grabacion del firmware del CPC (CAS WRITE): el fichero se
parte en bloques de hasta 2 KB y cada bloque son dos registros, cabecera y
datos. Cada registro es un bloque TZX turbo (11h):
    guia: unos  |  bit de sincronismo (0)  |  byte de sincronismo (2Ch cabecera,
    16h datos)  |  segmentos de 256 bytes, cada uno con su CRC (CCITT, valor
    inicial FFFFh, invertido, byte alto primero)  |  cola: 4 bytes FFh
Cabecera (64 bytes, rellena a 256): nombre (16), numero de bloque, ultimo bloque
(FFh), tipo, longitud del bloque, direccion de carga, primer bloque (FFh),
longitud total, direccion de entrada.

El firmware mide la velocidad en la guia, asi que se puede grabar mas deprisa
que la velocidad normal (--fast: guia y bits cortos, para simulacion).

Uso:
  python3 tools/make_cdt.py --basic "10 PRINT ..." salida.cdt   (programa BASIC)
  python3 tools/make_cdt.py --bin fichero.bin --load 4000 --exec 4000 salida.cdt
"""
import argparse, struct

TOKENS = {"PRINT": 0xBF, "GOTO": 0xA0, "CLS": 0x8A, "FOR": 0x9E, "NEXT": 0xB0, "TO": 0xEC}


def crc16(data):
    crc = 0xFFFF
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc ^ 0xFFFF


def tokenize_basic(src):
    """Tokenizador minimo: lineas 'NUM INSTRUCCION ...' con unas pocas palabras clave."""
    out = b""
    for line in src.split("\\n"):
        line = line.strip()
        if not line:
            continue
        num, _, body = line.partition(" ")
        tok, i, in_str = b"", 0, False
        while i < len(body):
            if body[i] == '"':
                in_str = not in_str
            if not in_str:
                for k, v in TOKENS.items():
                    if body.upper().startswith(k, i):
                        tok += bytes([v]); i += len(k); break
                else:
                    tok += body[i].encode("latin1"); i += 1
                continue
            tok += body[i].encode("latin1"); i += 1
        rec = struct.pack("<H", int(num)) + tok + b"\0"
        out += struct.pack("<H", len(rec) + 2) + rec
    return out + b"\0\0"


def record(sync, payload, zero, one, pilot_pulses, pause_ms):
    """Un registro del CPC como bloque TZX turbo (11h)."""
    data = bytes([sync])
    for i in range(0, len(payload), 256):
        seg = payload[i:i + 256].ljust(256, b"\0")
        data += seg + struct.pack(">H", crc16(seg))
    data += b"\xFF" * 4
    return (b"\x11" + struct.pack("<HHHHHH", one, zero, zero, zero, one, pilot_pulses)
            + bytes([8]) + struct.pack("<H", pause_ms) + struct.pack("<I", len(data))[:3] + data)


def main():
    ap = argparse.ArgumentParser(description="Cinta CDT del Amstrad CPC")
    ap.add_argument("--basic", help="programa BASIC, lineas separadas por \\n")
    ap.add_argument("--bin", help="fichero binario")
    ap.add_argument("--load", default="4000", help="direccion de carga (hex, binarios)")
    ap.add_argument("--exec", default="0", help="direccion de entrada (hex, binarios)")
    ap.add_argument("--name", default="TEST")
    ap.add_argument("--fast", action="store_true", help="guia y bits cortos (simulacion)")
    ap.add_argument("--lead-ms", type=int, default=0,
                    help="pausa al principio de la cinta (ms): el firmware espera ~2 s a que\n                         el motor coja velocidad antes de leer; las cintas reales lo cubren\n                         con una guia larga, una cinta --fast necesita esta pausa")
    ap.add_argument("out")
    a = ap.parse_args()
    if a.basic:
        body, ftype, load, entry = tokenize_basic(a.basic), 0, 0x0170, 0
    else:
        body, ftype, load, entry = open(a.bin, "rb").read(), 2, int(a.load, 16), int(a.exec, 16)
    zero, one, pilot = (500, 1000, 1024) if a.fast else (1167, 2333, 4096)   # T de 3,5 MHz
    tzx = b"ZXTape!\x1A" + bytes([1, 20])
    if a.lead_ms:
        tzx += b"\x20" + struct.pack("<H", a.lead_ms)   # bloque TZX de pausa
    blocks = [body[i:i + 2048] for i in range(0, len(body), 2048)] or [b""]
    for n, blk in enumerate(blocks):
        hdr = (a.name.upper().encode("latin1")[:16].ljust(16, b"\0")
               + bytes([n + 1, 0xFF if n == len(blocks) - 1 else 0, ftype])
               + struct.pack("<HH", len(blk), load + 2048 * n)
               + bytes([0xFF if n == 0 else 0]) + struct.pack("<HH", len(body), entry))
        tzx += record(0x2C, hdr.ljust(64, b"\0"), zero, one, pilot, 10)
        tzx += record(0x16, blk, zero, one, pilot, 300 if n == len(blocks) - 1 else 10)
    open(a.out, "wb").write(tzx)
    print(f"{a.out}: {len(body)} bytes en {len(blocks)} bloque(s), {len(tzx)} bytes de cinta")


if __name__ == "__main__":
    main()
