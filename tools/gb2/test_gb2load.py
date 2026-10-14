#!/usr/bin/env python3
"""
test_gb2load.py - Ejecuta el cargador de la GameBios v2 en un emulador de Z80
(paquete z80) con el mapper del Aleste (64 paginas de 16 KB, OUT a 7Cxx-7Fxx)
y la BDOS de MSX-DOS simulados, y comprueba la memoria al llegar al juego.

    python3 tools/gb2/test_gb2load.py METALGEAR.ROM VKILLER.COM
"""
import os, sys
import z80
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gb2build as gb

rom = open(sys.argv[1], "rb").read()
gamebios = gb.gamebios_from_vkiller(open(sys.argv[2], "rb").read())
Q1, Q2L, Q2H = [1, 4, 7, 10, 13], [2, 5, 8, 11, 14], [3, 6, 9, 12, 15]
com, bs, rep = gb.build("JUEGO", Q1, Q2L, Q2H, gamebios)
print("cargador:", len(com), "bytes;", rep)

pages = [bytearray(16384) for _ in range(64)]
mapping = [4, 5, 6, 7]                   # paginas de MSX-DOS al empezar
m = z80.Z80Machine()

def load_quarter(q):
    m.set_memory_block(q * 0x4000, bytes(pages[mapping[q]]))

def save_quarter(q):
    pages[mapping[q]][:] = bytes(m.memory[q * 0x4000:(q + 1) * 0x4000])

def on_out(addr, value):
    port = addr >> 8
    if 0x7C <= port <= 0x7F and value & 0xC0 == 0xC0:
        q = port - 0x7C
        for qq in range(4):            # una pagina puede estar en dos cuartos: guardar todo
            save_quarter(qq)
        mapping[q] = value & 0x3F
        load_quarter(q)
m.set_output_callback(on_out)

mem = bytearray(65536)
mem[0x100:0x100 + len(com)] = com
mem[0x0006:0x0008] = (0xD000).to_bytes(2, "little")      # cima del TPA
mem[0x0005] = 0xC9
m.set_memory_block(0, bytes(mem))
for q in range(4): save_quarter(q)
m.pc = 0x100; m.sp = 0xD000
init = rom[2] | rom[3] << 8
m.set_breakpoint(0x0005)
m.set_breakpoint(init)
dma, pos, outtext, steps = 0x80, 0, "", 0
while True:
    m.ticks_to_stop = 2_000_000
    m.run()
    if m.pc == 0x0005:                                     # BDOS
        c = m.c
        if c == 0x09:
            p = m.de
            while m.memory[p] != ord("$"): outtext += chr(m.memory[p]); p += 1
        elif c == 0x0F: m.a = 0
        elif c == 0x1A: dma = m.de
        elif c == 0x14:
            data = rom[pos:pos + 128]; pos += 128
            m.set_memory_block(dma, data.ljust(128, b"\x1A")); m.a = 0 if data else 1
        ret = m.memory[m.sp] | m.memory[(m.sp + 1) & 0xFFFF] << 8
        m.sp = (m.sp + 2) & 0xFFFF; m.pc = ret
        m.step_over_breakpoint()
        continue
    if m.pc == init or steps > 200:
        break
    steps += 1
    if m.pc == 0x0000:
        print("ERROR: el cargador ha vuelto a 0000h:", outtext); sys.exit(1)

for q in range(4): save_quarter(q)
print("mensajes:", outtext.strip().replace("\r\n", " | "))
print(f"PC = {m.pc:04X} (inicio del juego {init:04X}h); mapper: " + " ".join(f"{p:02X}h" for p in mapping))
ok = True
P = gb.FIRST_PAGE
bank = lambda b: rom[b * 0x2000:(b + 1) * 0x2000]
for n in Q1:
    good = pages[P][:0x2000] == bank(0) and pages[P][0x2000:] == bank(n)
    ok &= good; P += 1
    if not good: print(f"  MAL: pagina {P - 1:02X}h (banco 0 + {n})")
for mm in Q2L:
    for k in Q2H:
        good = pages[P][:0x2000] == bank(mm) and pages[P][0x2000:] == bank(k)
        ok &= good; P += 1
        if not good: print(f"  MAL: pagina {P - 1:02X}h (bancos {mm} + {k})")
print(f"  30 paginas compuestas con sus bancos: {'BIEN' if ok else 'MAL'}")
g = pages[0x0F]
gbimg, t3e, t3f, t2f = gamebios
checks = {"GameBios": g[:len(gbimg)] == gbimg, "tabla 3E00h": g[0x3E00:0x3F00] == t3e,
          "tabla 3F00h": g[0x3F00:0x4000] == t3f, "tabla 2F00h": g[0x2F00:0x3000] == t2f,
          "inversa 3D00h": all(g[0x3D00 + t3f[i]] == i for i in range(256) if list(t3f).count(t3f[i]) == 1),
          "rutina de bancos en 0E00h": g[0x0E00:0x0E04] == bytes([0xF5, 0xC5, 0xE5, 0xE6]),
          "RAM del juego a cero": not any(pages[0x3F][0x1000:0x3380]),
          "ganchos FD9Ah-FFC9h a RET": all(x == 0xC9 for x in pages[0x3F][0x3D9A:0x3FCA]),
          "mapper final (GameBios, banco 0+1, bancos 2+3, RAM)": mapping == [0x0F, gb.FIRST_PAGE, gb.FIRST_PAGE + 5, 0x3F]}
for k, v in checks.items():
    print(f"  {k}: {'BIEN' if v else 'MAL'}"); ok &= v
print("RESULTADO:", "OK" if ok else "FALLOS")
