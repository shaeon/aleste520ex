# Desensamblador con seguimiento de flujo para la GameBios v2 (pagina 0 de LEO.COM)
import re, sys
from z80dis import z80
com = open("LEO.COM", "rb").read()
BASE_FILE, SIZE = 0x3CE - 0x100, 0xE48
img = com[BASE_FILE:BASE_FILE + SIZE]
ENTRY = {0x0000: "RST00", 0x0003: "FRAME", 0x0008: "RST08", 0x0010: "RST10", 0x0018: "RST18", 0x0020: "RST20",
         0x0038: "RST38", 0x0047: "WRTVDP", 0x004A: "RDVRM", 0x004D: "WRTVRM", 0x0050: "SETRD", 0x0053: "SETWRT",
         0x0056: "FILVRM", 0x0059: "LDIRMV", 0x005C: "LDIRVM", 0x005F: "CHGMOD", 0x0062: "CHGCLR", 0x0093: "WRTPSG",
         0x0096: "RDPSG", 0x0138: "RSLREG", 0x0141: "SNSMAT", 0x016D: "B016D", 0x0170: "B0170", 0x0177: "NRDVRM", 0x017D: "NWRVRM"}
VDPREG = {}
for r in range(24):
    t = img[0x3D3 + 2 * r] | img[0x3D4 + 2 * r] << 8
    if t != 0x03D2: VDPREG[t] = f"VDP_R{r}"
ENTRY.update(VDPREG); ENTRY[0x03CE] = "WRTVDP_RET"; ENTRY[0x03D2] = "VDP_IGNORE"
SVC = {0x066A: "SVC_PALETTE", 0x06D3: "SVC_LINE_A", 0x0710: "SVC_LINE_B", 0x0740: "SVC_HMMV", 0x07B4: "SVC_HMMM",
       0x0858: "SVC_HMMC", 0x0876: "SVC_0218", 0x07CD: "SVC_TILE8", 0x088F: "SVC_0220"}
ENTRY.update(SVC)
for e in range(0x200, 0x224, 4): ENTRY[e] = f"GB_{e:04X}"
# destinos de los JP de la tabla de entradas: nombre "do_"
for a, n in list(ENTRY.items()):
    if a < 0x180 and img[a] == 0xC3:
        t = img[a+1] | img[a+2] << 8
        if t not in ENTRY: ENTRY[t] = "do_" + n
NAMES = {0x0626: "VRAM_UNMAP", 0x064C: "VRAM_MAP", 0x0B6F: "SPR_DRAW_ALL", 0x027A: "KBD_SCAN"}
for a, n in NAMES.items(): ENTRY.setdefault(a, n)
code, labels, todo = {}, {}, list(ENTRY)
for a, n in ENTRY.items(): labels[a] = n
def target(t):
    m = re.search(r"(?:JP|JR|CALL|DJNZ)\s+(?:[a-z]+,)?0x([0-9a-f]+)\b", t)
    return int(m.group(1), 16) if m else None
while todo:
    a = todo.pop()
    while 0 <= a < SIZE and a not in code:
        dec = z80.decode(img[a:a+4], a); L = max(1, dec.len); t = z80.disasm(dec)
        code[a] = (L, t)
        tg = target(t)
        if tg is not None and tg < SIZE:
            labels.setdefault(tg, f"L{tg:04X}"); todo.append(tg)
        if re.match(r"(JP|JR)\s+0x|RET$|JP \(|RETI|RETN", t) and not re.match(r"(JP|JR)\s+[a-z]+,", t):
            break
        a += L
covered = sum(L for L, _ in code.values())
print(f"codigo alcanzado: {covered} de {SIZE} bytes; etiquetas {len(labels)}", file=sys.stderr)
out, a = [], 0
while a < SIZE:
    if a in labels: out.append(f"{labels[a]}:")
    if a in code:
        L, t = code[a]
        t = re.sub(r"0x([0-9a-f]+)", lambda m: labels.get(int(m.group(1), 16), f"{int(m.group(1),16):04X}h") if int(m.group(1), 16) in labels and re.search(r"(JP|JR|CALL|DJNZ)", t) else f"{int(m.group(1),16):0{2 if len(m.group(1))<=2 else 4}X}h", t)
        out.append(f"    {t:34}; {a:04X}  {img[a:a+L].hex(' ')}")
        a += L
    else:
        j = a
        while j < SIZE and j not in code and j not in labels and j - a < 16 and not (0x3D3 <= a < 0x403 and j - a >= 2): j += 1
        chunk = img[a:j]
        out.append(f"    DB {', '.join(f'{x:02X}h' for x in chunk):60}; {a:04X}  {''.join(chr(x) if 32 <= x < 127 else '.' for x in chunk)}")
        a = j
open("gamebios_v2_leo_bruto.asm", "w").write("\n".join(out) + "\n")
