#!/usr/bin/env python3
"""
check_quartus.py - Busca en fuentes (System)Verilog construcciones que
yosys y Verilator aceptan pero Quartus Lite rechaza:

  - uso de un identificador antes de su declaracion (error 10161)
  - 'localparam' dentro de la lista #(...) de un modulo (error 10170)
  - variable (logic/reg/bit) declarada con valor inicial no constante
    (error 10748)
  - punto y coma doble ';;' (elemento vacio, error 10170)

Es una comprobacion aproximada (no es un analizador completo), pensada para
revisar ficheros del Aleste LX antes de llevarlos a Quartus.

Uso: python3 tools/check_quartus.py fichero.sv [...]
"""
import re, sys

KEYWORDS = set("""module endmodule input output inout logic wire reg bit int integer
genvar parameter localparam assign always always_ff always_comb always_latch initial
begin end if else case casez casex endcase default for while posedge negedge or and
not typedef enum struct packed function endfunction task endtask return automatic
generate endgenerate signed unsigned void byte shortint longint real string unique
priority""".split())

DECL = re.compile(r"\b(logic|wire|reg|bit|int|integer|genvar|input|output|inout|parameter|localparam)\b")


def strip(text):
    text = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r'"(\\.|[^"\\])*"', '""', text)
    return text


def line_of(text, pos):
    return text.count("\n", 0, pos) + 1


def declared_names(stmt):
    """Nombres declarados en una sentencia de declaracion (sin el ';')."""
    s = re.sub(r"\[[^\]]*\]", " ", stmt)                    # quitar rangos
    s = DECL.sub(" ", s)
    s = re.sub(r"\b(signed|unsigned|var|automatic|static|const)\b", " ", s)
    s = re.sub(r"\b\w+_t\b", " ", s)                        # tipos typedef *_t
    names = []
    depth = 0
    cur = ""
    for ch in s:                                            # partir por comas fuera de () {}
        if ch in "({":
            depth += 1
        elif ch in ")}":
            depth -= 1
        if ch == "," and depth == 0:
            names.append(cur); cur = ""
        else:
            cur += ch
    names.append(cur)
    out = []
    for n in names:
        n = n.split("=")[0].strip()
        m = re.match(r"([A-Za-z_]\w*)", n)
        if m:
            out.append(m.group(1))
    return out


def check(path):
    raw = open(path, encoding="utf-8", errors="replace").read()
    text = strip(raw)
    problems = []
    for mod in re.finditer(r"\bmodule\s+(\w+)(.*?)\bendmodule\b", text, flags=re.S):
        body = mod.group(2)
        base = mod.start(2)
        # lista de parametros #( ... )
        hdr = re.match(r"\s*#\s*\((.*?)\)\s*\(", body, flags=re.S)
        if hdr:
            for lp in re.finditer(r"\blocalparam\b", hdr.group(1)):
                problems.append((line_of(text, base + hdr.start(1) + lp.start()),
                                 "localparam dentro de #(...)"))
        # fin de la cabecera (lista de puertos)
        m_end = re.search(r"\)\s*;", body)
        hdr_end = m_end.end() if m_end else 0
        decl_pos = {}
        enum_vals = {}
        # declaraciones de la cabecera: todo lo que haya en ella
        for d in re.finditer(r"\b(input|output|inout|parameter|localparam)\b([^;,)]*)", body[:hdr_end]):
            for n in declared_names(d.group(0)):
                decl_pos.setdefault(n, 0)
        # estilo Verilog-1995: puertos solo por nombre en la cabecera y
        # declarados despues; los nombres de la cabecera cuentan como declarados
        ports = re.match(r"\s*(?:#\s*\(.*?\)\s*)?\((.*?)\)\s*;", body, flags=re.S)
        if ports and not re.search(r"\b(input|output|inout)\b", ports.group(1)):
            for n in re.findall(r"[A-Za-z_]\w*", ports.group(1)):
                decl_pos.setdefault(n, 0)
        # enums de typedef
        for t in re.finditer(r"typedef\s+enum[^{]*\{(.*?)\}\s*(\w+)\s*;", body, flags=re.S):
            for v in re.findall(r"([A-Za-z_]\w*)\s*(?:=|,|$)", t.group(1)):
                decl_pos.setdefault(v, t.start())
            decl_pos.setdefault(t.group(2), t.start())
        # declaraciones del cuerpo (sentencias que empiezan por un tipo)
        for st in re.finditer(r"(?:(?<=;)|(?<=\bbegin)|(?<=\bend)|(?<=\)))\s*((?:logic|wire|reg|bit|int|integer|genvar|localparam|parameter)\b[^;]*);",
                              body[hdr_end:], flags=re.S):
            stmt = st.group(1)
            pos = hdr_end + st.start(1)
            for n in declared_names(stmt):
                decl_pos.setdefault(n, pos)
            # valor inicial no constante en variables
            if re.match(r"(logic|reg|bit)\b", stmt) and "=" in stmt:
                for part in re.split(r",(?![^\[\(\{]*[\]\)\}])", stmt):
                    if "=" in part:
                        init = part.split("=", 1)[1]
                        init = re.sub(r"\d*'[sS]?[bBoOdDhH][0-9a-fA-FxXzZ_?]+|'[01xXzZ]", "0", init)
                        ids = [i for i in re.findall(r"\b[A-Za-z_]\w*\b", init)
                               if i not in KEYWORDS and not re.match(r"^[A-Z0-9_]+$", i)]
                        ids = [i for i in ids if not re.match(r"^\d", i)]
                        if ids:
                            problems.append((line_of(text, base + pos),
                                             f"variable con valor inicial no constante: {part.strip()[:60]}"))
        # ';;' fuera de la cabecera de un for(...): elemento vacio, Quartus lo rechaza
        no_for = re.sub(r"\bfor\s*\((?:[^()]|\([^()]*\))*\)", lambda m: re.sub(r"[^\n]", " ", m.group(0)), body)
        for sc in re.finditer(r";[ \t]*;", no_for):
            problems.append((line_of(text, base + sc.start()), "punto y coma doble ';;'"))
        # usos antes de la declaracion. Solo en SystemVerilog: en ficheros .v
        # (VERILOG_FILE) Quartus lo acepta; p. ej. rtl/cpc/UM6845R.v, que el
        # core Amstrad de MiST compila tal cual para la misma Poseidon.
        for name, dpos in (decl_pos.items() if path.endswith(".sv") else []):
            if dpos == 0:
                continue
            for u in re.finditer(r"(?<![\.\w`$'])" + re.escape(name) + r"\b", body[:dpos]):
                problems.append((line_of(text, base + u.start()),
                                 f"'{name}' se usa antes de declararse (linea {line_of(text, base + dpos)})"))
                break
    return sorted(set(problems))


if __name__ == "__main__":
    bad = 0
    for f in sys.argv[1:]:
        for ln, msg in check(f):
            print(f"{f}:{ln}: {msg}")
            bad += 1
    sys.exit(1 if bad else 0)
