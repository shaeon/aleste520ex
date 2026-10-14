#!/usr/bin/env python3
"""Cinta TZX sintetica con todos los tipos de bloque que maneja tzxplayer."""
import random, struct, sys
random.seed(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
def w(n): return struct.pack("<H", n)
def d3(n): return struct.pack("<I", n)[:3]
def data(n): return bytes(random.randrange(256) for _ in range(n))
b = b"ZXTape!\x1A" + bytes([1, 20])
b += b"\x30" + bytes([5]) + b"HOLA!"                                  # texto
b += b"\x10" + w(2) + w(6) + bytes([0]) + data(5)                     # normal (cabecera), pausa 2 ms
b += b"\x11" + w(40) + w(15) + w(17) + w(20) + w(41) + w(30) + bytes([5]) + w(1) + d3(4) + data(4)   # turbo, 5 bits finales
b += b"\x12" + w(33) + w(9)                                           # tono
b += b"\x13" + bytes([3]) + w(25) + w(60) + w(12)                     # pulsos
b += b"\x14" + w(22) + w(44) + bytes([8]) + w(1) + d3(6) + data(6)    # datos puros
b += b"\x15" + w(11) + w(1) + bytes([3]) + d3(5) + data(5)            # directo, 3 bits finales
b += b"\x24" + w(3)                                                   # bucle x3
b += b"\x12" + w(18) + w(4)
b += b"\x25"
b += b"\x32" + w(7) + bytes([1, 0, 4]) + b"ABCD"                      # info de archivo
b += b"\x33" + bytes([2]) + bytes([0, 1, 2, 3, 4, 5])                 # hardware
b += b"\x35" + b"CUSTOM INFO     " + struct.pack("<I", 3) + b"xyz"     # info propia
b += b"\x31" + bytes([2, 3]) + b"msg"                                 # mensaje
b += b"\x21" + bytes([2]) + b"GR" + b"\x22"                           # grupo
b += b"\x5A" + b"XTape!\x1A" + bytes([1, 20])[:0] + bytes(2)          # union (9 bytes)
b += b"\x20" + w(1)                                                   # pausa 1 ms
b += b"\x2A" + bytes(4)                                               # stop 48k
b += b"\x10" + w(1) + w(4) + bytes([0xFF]) + data(3)                  # normal (datos)
b += b"\x20" + w(0)                                                   # pausa 0 = parar
open(sys.argv[1], "wb").write(b)
print(len(b), "bytes")
