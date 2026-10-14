#!/usr/bin/env python3
"""
run_game.py - Ejecuta un juego convertido con la GameBios v2 en un emulador de
Z80 (paquete z80): mapper del Aleste (64 paginas), BDOS simulada para el
cargador e interrupcion a 300 Hz (RST 38h cada 13.333 ciclos a 4 MHz, como la
del Aleste). Al final saca una captura de la pantalla del MSX (SCREEN 5) desde
la copia de la VRAM de la GameBios (paginas 10h-13h), deshaciendo la
reordenacion de bits con la tabla inversa de 3D00h.

    python3 tools/gb2/run_game.py MGEAR.COM MGEAR.DAT --seconds 3 --png pantalla.png
"""
import argparse, collections, os, sys
import z80

ap = argparse.ArgumentParser()
ap.add_argument("com"); ap.add_argument("dat")
ap.add_argument("--seconds", type=float, default=3.0)
ap.add_argument("--png")
ap.add_argument("--snap", type=float, default=0, help="captura cada N segundos (pantalla_NN.png junto a --png)")
ap.add_argument("--trace", action="store_true", help="contar las llamadas a la GameBios")
ap.add_argument("--log", action="append", default=[], help="registrar todas las llamadas a esta entrada (p. ej. WRTVDP)")
a = ap.parse_args()
com = open(a.com, "rb").read(); dat = open(a.dat, "rb").read()

pages = [bytearray(16384) for _ in range(64)]
mapping = [4, 5, 6, 7]
m = z80.Z80Machine()

def snapshot(path):
    from PIL import Image
    vram = b"".join(bytes(pages[p]) for p in (0x10, 0x11, 0x12, 0x13))
    inv = pages[0x0F][0x3D00:0x3E00]
    pal = [(0, 0, 0), (0, 0, 0), (36, 219, 36), (109, 255, 109), (36, 36, 255), (73, 109, 255), (182, 36, 36), (73, 219, 255),
           (255, 36, 36), (255, 109, 109), (219, 219, 36), (219, 219, 146), (36, 146, 36), (219, 73, 182), (182, 182, 182), (255, 255, 255)]
    im = Image.new("RGB", (256, 212))
    for y in range(212):
        for x in range(128):
            b = inv[vram[y * 128 + x]]
            im.putpixel((2 * x, y), pal[b >> 4]); im.putpixel((2 * x + 1, y), pal[b & 15])
    im.resize((512, 424), Image.NEAREST).save(path)

def save_all():
    for q in range(4):
        pages[mapping[q]][:] = bytes(m.memory[q * 0x4000:(q + 1) * 0x4000])

def on_out(addr, value):
    port = addr >> 8
    if 0x7C <= port <= 0x7F and value & 0xC0 == 0xC0:
        q = port - 0x7C
        save_all()
        mapping[q] = value & 0x3F
        m.set_memory_block(q * 0x4000, bytes(pages[mapping[q]]))
    else:
        outs[port] += 1
outs = collections.Counter()
m.set_output_callback(on_out)

def on_in(addr):
    port = addr >> 8
    if 0x7C <= port <= 0x7F:                    # el mapper del 520EX se puede leer: C0h + pagina
        return 0xC0 | mapping[port - 0x7C]
    return 0xFF
m.set_input_callback(on_in)

mem = bytearray(65536); mem[0x100:0x100 + len(com)] = com
mem[0x0006:0x0008] = (0xD000).to_bytes(2, "little"); mem[0x0005] = 0xC9
m.set_memory_block(0, bytes(mem)); save_all()
m.pc = 0x100; m.sp = 0xD000
m.set_breakpoint(0x0005)
dma, pos = 0x80, 0
TICKS_INT = 13333
ENTRIES = {0x0047: "WRTVDP", 0x004A: "RDVRM", 0x004D: "WRTVRM", 0x0050: "SETRD", 0x0053: "SETWRT", 0x0056: "FILVRM",
           0x0059: "LDIRMV", 0x005C: "LDIRVM", 0x005F: "CHGMOD", 0x0062: "CHGCLR", 0x0093: "WRTPSG", 0x016B: "BIGFIL",
           0x016E: "NSETRD", 0x0171: "NSTWRT", 0x0010: "RST10", 0x0018: "RST18", 0x0003: "FRAME",
           0x0200: "SVC_PALETA", 0x0204: "SVC_LINE_A", 0x0208: "SVC_LINE_B", 0x020C: "SVC_HMMV", 0x0210: "SVC_HMMM", 0x0218: "SVC_0218"}
calls, firsts = collections.Counter(), []
total, pcs, ints, frames = 0, collections.Counter(), 0, 0
started = False
limit = int(a.seconds * 4_000_000)
while total < limit + 50_000_000:
    m.ticks_to_stop = TICKS_INT
    before = m.ticks_to_stop
    m.run()
    if m.pc == 0x0005 and not started:                   # BDOS del cargador
        c = m.c
        if c == 0x0F: m.a = 0
        elif c == 0x1A: dma = m.de
        elif c == 0x14:
            d = dat[pos:pos + 128]; pos += 128
            m.set_memory_block(dma, d.ljust(128, b"\x1A")); m.a = 0 if d else 1
        ret = m.memory[m.sp] | m.memory[(m.sp + 1) & 0xFFFF] << 8
        m.sp = (m.sp + 2) & 0xFFFF; m.pc = ret; m.step_over_breakpoint()
        continue
    if started and m.pc in ENTRIES and a.trace:
        n = ENTRIES[m.pc]; calls[n] += 1
        if n in a.log: print(f"  {total / 4e6:6.2f} s {n}(A={m.a:02X} BC={m.bc:04X} DE={m.de:04X} HL={m.hl:04X})")
        if calls[n] <= 3: firsts.append(f"{n}(A={m.a:02X} BC={m.bc:04X} DE={m.de:04X} HL={m.hl:04X})")
        m.step_over_breakpoint(); continue
    if not started and mapping[0] == 0x0F:
        started = True; total = 0
        m.clear_breakpoint(0x0005)
        if a.trace:
            for e in ENTRIES: m.set_breakpoint(e)
        print(f"juego en marcha (PC {m.pc:04X})")
    if not started:
        continue
    total += TICKS_INT
    pcs[m.pc >> 12] += 1
    # teclado: la GameBios explora con SNSMAT sobre su matriz; aqui no se simula (sin teclas)
    if m.iff1:                                          # interrupcion del Aleste
        sp = (m.sp - 2) & 0xFFFF
        m.set_memory_block(sp, bytes([m.pc & 0xFF, m.pc >> 8]))
        m.sp = sp; m.pc = 0x0038; m.iff1 = 0; m.iff2 = 0
        if m.halted: m.halted = False
        ints += 1
    if a.snap and a.png and total // int(a.snap * 4e6) != (total - TICKS_INT) // int(a.snap * 4e6):
        save_all(); snapshot(a.png.replace(".png", f"_{int(total / 4e6):03d}.png")); print(f"  captura a los {total / 4e6:.0f} s", flush=True)
    if total >= limit:
        break

save_all()
if a.trace:
    print("llamadas a la GameBios:", ", ".join(f"{k}:{v}" for k, v in calls.most_common()))
    print("primeras:", "; ".join(firsts[:40]))
print(f"{total / 4e6:.1f} s simulados, {ints} interrupciones atendidas, PC final {m.pc:04X}, mapper " +
      " ".join(f"{p:02X}h" for p in mapping))
print("PC por zonas de 4 KB (muestras):", ", ".join(f"{k:X}xxx:{v}" for k, v in sorted(pcs.items())))
cnt = pages[0x0F][0x0F60]
print(f"contador de cuadros pendientes: {cnt}; OUT a otros puertos: " + ", ".join(f"{p:02X}xx:{n}" for p, n in sorted(outs.items())))
vram = b"".join(bytes(pages[p]) for p in (0x10, 0x11, 0x12, 0x13))
ram = pages[0x3F]
sp = [bytes(ram[0x2A00 + 4 * i:0x2A00 + 4 * i + 4]) for i in range(32)]
vis = [e for e in sp if e[0] not in (0xE0, 0xD0, 0xD8)]
print(f"lista de sprites EA00h: {len(vis)} visibles de 32; primeros: " + " ".join(e.hex() for e in sp[:6]))
g0 = pages[0x0F]
li = [bytes(g0[0x1200 + 4 * i:0x1204 + 4 * i]) for i in range(32)]
print(f"rutina del limite en 0F70h: {g0[0x0F70:0x0F74].hex(' ')}; lista intermedia 1200h: "
      f"{sum(1 for e in li if e[0] not in (0xE0, 0xD8))} visibles; primeras: " + " ".join(e.hex() for e in li[:4]))
print(f"copia de la VRAM: {sum(1 for x in vram[:0x6A00] if x)} bytes no nulos en la pantalla (0000h-69FFh)")
if a.png:
    from PIL import Image
    inv = pages[0x0F][0x3D00:0x3E00]
    pal = [(0, 0, 0), (0, 0, 0), (36, 219, 36), (109, 255, 109), (36, 36, 255), (73, 109, 255), (182, 36, 36), (73, 219, 255),
           (255, 36, 36), (255, 109, 109), (219, 219, 36), (219, 219, 146), (36, 146, 36), (219, 73, 182), (182, 182, 182), (255, 255, 255)]
    im = Image.new("RGB", (256, 212))
    for y in range(212):
        for x in range(128):
            b = inv[vram[y * 128 + x]]
            im.putpixel((2 * x, y), pal[b >> 4]); im.putpixel((2 * x + 1, y), pal[b & 15])
    im.resize((512, 424), Image.NEAREST).save(a.png)
    print("captura:", a.png)
