#!/usr/bin/env python3
"""
aleste_wbs.py - Genera guiones de bus (.WBS) para el Aleste LX en placas MiST.

Un .WBS es una lista de escrituras de 8 bits en el bus Wishbone del Aleste LX,
cada una en 4 bytes: direccion de 24 bits (alta primero) y dato. Se carga
desde el OSD con "Run bus script" (indice 2 de data_io) y hace lo mismo que
las escrituras que mandaban por UART los scripts Python del Aleste LX: poner
un modo de video, programar la paleta, rellenar memoria...

Las operaciones se aplican en el orden en que se escriben:

  --preset NOMBRE      modo de video de aleste-lx/scripts/python/presets/
                       graphics_presets.py (usa el PresetLoader original)
  --write DIR=VAL      una escritura suelta, en hexadecimal (FF0120=01)
  --load DIR:FICHERO   el contenido de un fichero a partir de DIR
  --bars DIR           16 barras verticales de 16000 bytes a partir de DIR
                       (se ven igual con direccionamiento CPC o lineal)
  --palette NOMBRE     paleta de 16 colores en modo de 12 bits: "test"
                       (16 colores bien distintos) o "grey" (gris)
                       La RAM de la paleta no tiene valor inicial: sin esto
                       la imagen sale negra aunque el modo y la memoria
                       esten bien (los presets 16k4b y otros no la cargan).
  --list               lista los presets y sale

Ejemplos:
  aleste_wbs.py -o BARS.WBS --preset 16k4b --palette test --bars 0
  aleste_wbs.py -o MODO1.WBS --preset cpc_mode1
  aleste_wbs.py -o FOTO.WBS --preset 16k4b --load 0:foto.bin

Direcciones utiles (modo nativo, ver aleste-lx/docs/lx_bus.md):
  FF0120/FF0121  CRTC: indice / dato
  FF0100/FF0101  paleta: indice / dato
  000000-FEFFFF  memoria (SDRAM)
"""
import argparse, pathlib, sys, types

ROOT = pathlib.Path(__file__).resolve().parent.parent
PY   = ROOT / "aleste-lx/scripts/python"

# Valores del CRTC tras el reset (mc6845mod, STANDARD="cpc"): los presets
# hacen escrituras con mascara que leen el valor actual.
CRTC_RESET = {0x00: 63, 0x01: 40, 0x02: 46, 0x03: 0x8E, 0x04: 38, 0x05: 0,
              0x06: 25, 0x07: 30, 0x08: 0, 0x09: 7, 0x12: 0, 0x13: 0, 0x14: 0, 0x15: 0}


class Recorder:
    """Hace de FPGAMemory para el PresetLoader original: en vez de mandar las
    escrituras por UART las apunta, y contesta las lecturas desde una copia
    de los registros indexados (CRTC y paleta)."""
    INDEXED = {0xFF0120: CRTC_RESET, 0xFF0100: {}}

    def __init__(self):
        self.ops = []
        self.index = {base: 0 for base in self.INDEXED}
        self.shadow = {base: dict(regs) for base, regs in self.INDEXED.items()}
        self.mem = {}

    def write_memory(self, address, data, progress_callback=None):
        for i, b in enumerate(bytes(data)):
            a = address + i
            self.ops.append((a, b))
            if a in self.INDEXED:
                self.index[a] = b
            elif a - 1 in self.INDEXED:
                self.shadow[a - 1][self.index[a - 1]] = b
            else:
                self.mem[a] = b
        return True

    def read_memory(self, address, size=1, progress_callback=None):
        out = []
        for a in range(address, address + size):
            if a - 1 in self.INDEXED:
                out.append(self.shadow[a - 1].get(self.index[a - 1], 0))
            else:
                out.append(self.mem.get(a, 0))
        return bytes(out)

    def close(self):
        pass


def load_presets():
    # El PresetLoader importa el transporte serie; aqui no hace falta.
    for name in ("serial", "serial.tools", "serial.tools.list_ports"):
        sys.modules.setdefault(name, types.ModuleType(name))
    sys.path.insert(0, str(PY))
    from core.preset_loader import PresetLoader
    from presets.graphics_presets import GRAPHICS_PRESETS
    return PresetLoader, GRAPHICS_PRESETS


# Paletas de 16 entradas, R4G4B4
PALETTES = {
    "test": [0x000, 0x00A, 0x0A0, 0x0AA, 0xA00, 0xA0A, 0xA50, 0xAAA,
             0x555, 0x55F, 0x5F5, 0x5FF, 0xF55, 0xF5F, 0xFF5, 0xFFF],
    "grey": [(i << 8) | (i << 4) | i for i in range(16)],
}

def palette_ops(rec, name, border=0x000):
    if name not in PALETTES:
        sys.exit(f"paleta desconocida: {name} ({', '.join(PALETTES)})")
    rec.write_memory(0xFF0105, bytes([0x00]))            # control: modo 12 bits, sin autoincremento
    for i, c in enumerate(PALETTES[name]):
        rec.write_memory(0xFF0100, bytes([i]))           # indice
        rec.write_memory(0xFF0101, bytes([c & 0xFF]))    # G, B (se guarda)
        rec.write_memory(0xFF0102, bytes([c >> 8]))      # R (escribe la entrada)
    rec.write_memory(0xFF0103, bytes([border & 0xFF]))   # borde
    rec.write_memory(0xFF0104, bytes([border >> 8]))


def bars():
    # 160 bytes por linea en el peor caso; cada byte con los dos nibbles
    # iguales, asi el orden de pixeles dentro del byte no importa.
    data = bytearray(16000)
    for i in range(len(data)):
        col = (i % 80) * 16 // 80
        data[i] = (col << 4) | col
    return bytes(data)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--output", help="fichero .WBS de salida")
    ap.add_argument("--list", action="store_true")
    args, op_list = ap.parse_known_args()

    if args.list:
        _, presets = load_presets()
        for name, p in presets.items():
            print(f"{name:12} {p['name']}")
        return
    if not args.output or not op_list:
        ap.error("hace falta -o y al menos una operacion")

    rec = Recorder()
    ops = list(op_list)
    while ops:
        op = ops.pop(0)
        arg = ops.pop(0) if ops else None
        if arg is None:
            sys.exit(f"falta el argumento de {op}")
        if op == "--preset":
            PresetLoader, presets = load_presets()
            if arg not in presets:
                sys.exit(f"preset desconocido: {arg} (ver --list)")
            if not PresetLoader(fpga=rec).apply_preset(arg, verbose=False):
                sys.exit(f"fallo aplicando {arg}")
        elif op == "--write":
            a, v = arg.split("=")
            rec.write_memory(int(a, 16), bytes([int(v, 16)]))
        elif op == "--load":
            a, f = arg.split(":", 1)
            rec.write_memory(int(a, 16), pathlib.Path(f).read_bytes())
        elif op == "--palette":
            palette_ops(rec, arg)
        elif op == "--bars":
            rec.write_memory(int(arg, 16), bars())
        else:
            sys.exit(f"operacion desconocida: {op}")

    out = bytearray()
    for a, b in rec.ops:
        out += bytes([(a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF, b])
    pathlib.Path(args.output).write_bytes(out)
    print(f"{args.output}: {len(rec.ops)} escrituras, {len(out)} bytes")


if __name__ == "__main__":
    main()
