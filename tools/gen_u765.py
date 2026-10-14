#!/usr/bin/env python3
"""
gen_u765.py - Genera rtl/cpc/u765.sv (controlador de disco uPD765) con soporte
de imagenes en bruto (raw), a partir de rtl/cpc/orig/u765.sv.

El original (gyurco/Amstrad_MiST, u765/u765.sv, con la salida int_o anadida
para el core NewBrain) solo entiende imagenes DSK y EDSK: al montar mira el
primer byte ('M' = "MV - CPC", 'E' = "EXTENDED CPC DSK File") y si no es
ninguno rechaza la imagen. Los discos MSX-DOS del Aleste 520EX son imagenes en
bruto de 720 KB: solo los sectores, uno detras de otro.

Cambios (los mismos para las dos unidades):

1. Al montar, si no hay firma, la imagen se toma como raw. La geometria sale
   del tamano (bloques de 512 bytes, se ignora lo que sobre: msx-games.dsk
   trae 16 bytes de mas al final):
       1440 -> 80 pistas, 2 caras, 9 sectores  (720 KB, MSX-DOS 2DD)
        720 -> 80 pistas, 1 cara,  9 sectores  (360 KB, MSX 1DD)
       1280 -> 80 / 2 / 8,  640 -> 80 / 1 / 8,  1600 -> 80 / 2 / 10
        360 -> 40 / 1 / 9   (180 KB)
       otro -> 9 sectores, 2 caras si pasa de 720 bloques, 80 pistas
2. La cabecera de pista ("Track-Info") no se lee de la SD: se genera. Sectores
   de 512 bytes (N=2) numerados de 1 a N (formato MSX/PC), C = cilindro
   actual, H = cara.
3. La posicion de los datos de la pista es (pista * caras + cara) * sectores *
   512, sin los 256 bytes de cabecera del EDSK.
4. SENSE DRIVE STATUS da la senal de pista 0 si la unidad existe (available),
   tenga disco o no, como una disquetera real.

Las imagenes DSK/EDSK siguen exactamente igual que antes.

Uso:  python3 tools/gen_u765.py
"""
import pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC  = ROOT / "rtl/cpc/orig/u765.sv"
DST  = ROOT / "rtl/cpc/u765.sv"


def rep(text, old, new, what):
    n = text.count(old)
    if n != 1:
        sys.exit(f"ERROR ({what}): se esperaba 1 coincidencia y hay {n}:\n{old}")
    return text.replace(old, new)


def main():
    t = SRC.read_text(encoding="utf-8")

    # --- 0. tinfo_data: de la RAM o generado
    t = rep(t, "reg    [7:0] buff_data_in, buff_data_out, tinfo_data;",
            "reg    [7:0] buff_data_in, buff_data_out;\n"
            "wire   [7:0] tinfo_data;                 // RAM de Track-Info o cabecera generada (raw)\n"
            "reg    [7:0] tinfo_ram_q, tinfo_synth;\n"
            "reg          image_raw[2];  // imagen en bruto, sin cabecera (aleste-lx-mist)\n"
            "reg    [3:0] image_spt[2];  // raw: sectores por pista",
            "tinfo_data")
    t = rep(t, "\t.q_b(tinfo_data)\n);", "\t.q_b(tinfo_ram_q)\n);", "tinfo q_b")

    # --- 0b. SECTOR_SIZE: variable con valor inicial calculado dentro de la
    # funcion. Quartus lo acepta, pero Verilator da un error interno: se separa
    # la declaracion de la asignacion (mismo resultado).
    t = rep(t, "reg [15:0] logical_size = (16'h80 << (n[3] ? 4'h8 : n[2:0]));",
            "reg [15:0] logical_size;\n\tlogical_size = (16'h80 << (n[3] ? 4'h8 : n[2:0]));", "SECTOR_SIZE")

    # --- 1. estado por unidad

    # --- 2. montaje: firma o raw
    old = """\t\t\t\t\t\tif (buff_data_in == "E")
\t\t\t\t\t\t\timage_edsk[i_current_drive] <= 1;
\t\t\t\t\t\telse if (buff_data_in == "M")
\t\t\t\t\t\t\timage_edsk[i_current_drive] <= 0;
\t\t\t\t\t\telse begin
\t\t\t\t\t\t\timage_ready[i_current_drive] <= 0;
\t\t\t\t\t\t\timage_scan_state[i_current_drive] <= 0;
\t\t\t\t\t\t\ti_scan_lock <= 0;
\t\t\t\t\t\tend"""
    new = """\t\t\t\t\t\timage_raw[i_current_drive] <= 0;
\t\t\t\t\t\tif (buff_data_in == "E")
\t\t\t\t\t\t\timage_edsk[i_current_drive] <= 1;
\t\t\t\t\t\telse if (buff_data_in == "M")
\t\t\t\t\t\t\timage_edsk[i_current_drive] <= 0;
\t\t\t\t\t\telse begin
\t\t\t\t\t\t\t// Sin firma: imagen en bruto. Geometria por el tamano.
\t\t\t\t\t\t\timage_raw[i_current_drive] <= 1;
\t\t\t\t\t\t\timage_edsk[i_current_drive] <= 1;   // longitudes de la cabecera generada
\t\t\t\t\t\t\tcase (image_size[i_current_drive][31:9])
\t\t\t\t\t\t\t\t23'd1440: begin image_tracks[i_current_drive] <= 8'd80; image_sides[i_current_drive] <= 1; image_spt[i_current_drive] <= 4'd9;  end
\t\t\t\t\t\t\t\t23'd720:  begin image_tracks[i_current_drive] <= 8'd80; image_sides[i_current_drive] <= 0; image_spt[i_current_drive] <= 4'd9;  end
\t\t\t\t\t\t\t\t23'd1280: begin image_tracks[i_current_drive] <= 8'd80; image_sides[i_current_drive] <= 1; image_spt[i_current_drive] <= 4'd8;  end
\t\t\t\t\t\t\t\t23'd640:  begin image_tracks[i_current_drive] <= 8'd80; image_sides[i_current_drive] <= 0; image_spt[i_current_drive] <= 4'd8;  end
\t\t\t\t\t\t\t\t23'd1600: begin image_tracks[i_current_drive] <= 8'd80; image_sides[i_current_drive] <= 1; image_spt[i_current_drive] <= 4'd10; end
\t\t\t\t\t\t\t\t23'd360:  begin image_tracks[i_current_drive] <= 8'd40; image_sides[i_current_drive] <= 0; image_spt[i_current_drive] <= 4'd9;  end
\t\t\t\t\t\t\t\tdefault:  begin image_tracks[i_current_drive] <= 8'd80; image_spt[i_current_drive] <= 4'd9;
\t\t\t\t\t\t\t\t                image_sides[i_current_drive] <= (image_size[i_current_drive][31:9] > 23'd720); end
\t\t\t\t\t\t\tendcase
\t\t\t\t\t\t\timage_ready[i_current_drive] <= 1;
\t\t\t\t\t\t\timage_trackinfo_dirty[i_current_drive] <= 1;
\t\t\t\t\t\t\timage_scan_state[i_current_drive] <= 0;
\t\t\t\t\t\t\ti_scan_lock <= 0;
\t\t\t\t\t\tend"""
    t = rep(t, old, new, "montaje")

    # --- 3. carga de Track-Info: en raw no se lee de la SD
    old = """\t\t\t\tif (image_ready[i_current_drive] && image_track_offsets_in) begin
\t\t\t\t\tsd_rd_tinfo[i_current_drive] <= 1;
\t\t\t\t\tseek_state[i_current_drive] <= 5;
\t\t\t\tend else begin"""
    new = """\t\t\t\tif (image_ready[i_current_drive] && image_raw[i_current_drive] && pcn[i_current_drive] < image_tracks[i_current_drive]) begin
\t\t\t\t\tseek_state[i_current_drive] <= 5;         // raw: cabecera generada, sin leer la SD
\t\t\t\tend else if (image_ready[i_current_drive] && !image_raw[i_current_drive] && image_track_offsets_in) begin
\t\t\t\t\tsd_rd_tinfo[i_current_drive] <= 1;
\t\t\t\t\tseek_state[i_current_drive] <= 5;
\t\t\t\tend else begin"""
    t = rep(t, old, new, "seek 4")

    # --- 4. posicion de los datos de la pista
    old = """\t\t\t\tsector_offset[sector_search_ds0][sector_search_hds] <=
\t\t\t\t\t{image_track_offsets_in + ((i_current_track_sectors[sector_search_ds0][sector_search_hds] > 29) ? 2'd2 : 2'd1), 8'd0};"""
    new = """\t\t\t\tsector_offset[sector_search_ds0][sector_search_hds] <= image_raw[sector_search_ds0] ?
\t\t\t\t\t// raw: (pista * caras + cara) * sectores * 512
\t\t\t\t\t(({23'd0, pcn[sector_search_ds0], 1'b0} >> !image_sides[sector_search_ds0]) + {31'd0, sector_search_hds & image_sides[sector_search_ds0]})
\t\t\t\t\t\t* {28'd0, image_spt[sector_search_ds0]} * 32'd512 :
\t\t\t\t\t{image_track_offsets_in + ((i_current_track_sectors[sector_search_ds0][sector_search_hds] > 29) ? 2'd2 : 2'd1), 8'd0};"""
    t = rep(t, old, new, "sector_offset")

    # --- 5. cabecera de pista generada (registrada: misma latencia que la RAM).
    # Va dentro del bloque principal, que es donde estan pcn y el resto.
    old = "\tint_o <= int_state[0] | int_state[1];\n"
    new = old + """
\t// Cabecera de pista generada para imagenes raw (aleste-lx-mist). Formato
\t// del Track-Info de EDSK: 0x14 N, 0x15 sectores, 0x16 GAP3, 0x17 relleno,
\t// 0x18 + 8*k: C H R N ST1 ST2 longitud (2 bytes).
\tcase (tinfo_addr[7:0])
\t\t8'h10: tinfo_synth <= pcn[tinfo_ds0];
\t\t8'h11: tinfo_synth <= {7'd0, tinfo_hds};
\t\t8'h14: tinfo_synth <= 8'd2;
\t\t8'h15: tinfo_synth <= {4'd0, image_spt[tinfo_ds0]};
\t\t8'h16: tinfo_synth <= 8'h54;
\t\t8'h17: tinfo_synth <= 8'hE5;
\t\tdefault:
\t\t\tif (tinfo_addr[7:0] >= 8'h18 && ((tinfo_addr[7:0] - 8'h18) >> 3) < {4'd0, image_spt[tinfo_ds0]})
\t\t\t\tcase (tinfo_addr[2:0])
\t\t\t\t\t3'd0: tinfo_synth <= pcn[tinfo_ds0];                              // C
\t\t\t\t\t3'd1: tinfo_synth <= {7'd0, tinfo_hds};                           // H
\t\t\t\t\t3'd2: tinfo_synth <= ((tinfo_addr[7:0] - 8'h18) >> 3) + 8'd1;     // R: 1..N
\t\t\t\t\t3'd3: tinfo_synth <= 8'd2;                                        // N: 512 bytes
\t\t\t\t\t3'd7: tinfo_synth <= 8'h02;                                       // longitud 0x0200
\t\t\t\t\tdefault: tinfo_synth <= 8'h00;                                   // ST1, ST2, longitud baja
\t\t\t\tendcase
\t\t\telse tinfo_synth <= 8'h00;
\tendcase
"""
    t = rep(t, old, new, "synth")
    t = rep(t, "//track offset buffer\n",
            "assign tinfo_data = image_raw[tinfo_ds0] ? tinfo_synth : tinfo_ram_q;\n\n//track offset buffer\n",
            "tinfo mux")

    # --- 6. SENSE DRIVE STATUS: la senal de pista 0 depende de que la unidad
    # exista (available), no de que tenga disco: en una disquetera real el
    # cabezal llega a la pista 0 aunque este vacia. La BDOS de MSX-DOS del 520EX
    # cuenta las unidades al arrancar recalibrando y mirando este bit; con la
    # unidad B sin disco en ese momento la daba por inexistente y hacia de B:
    # una unidad fantasma de A: ("Insert diskette for drive B:").
    t = rep(t, "\t\t\t\t\t\t\timage_ready[ds0] & !pcn[ds0],       //track 0",
            "\t\t\t\t\t\t\tavailable[ds0] & !pcn[ds0],         //track 0 (unidad presente, con o sin disco)",
            "ST3 track 0")

    header = ("//----------------------------------------------------------------------------\n"
              "// FICHERO GENERADO por tools/gen_u765.py desde rtl/cpc/orig/u765.sv.\n"
              "// Anade imagenes de disco en bruto (raw, sin cabecera; p. ej. MSX-DOS de\n"
              "// 720 KB) a las DSK/EDSK del original. Ver la cabecera del script.\n"
              "//----------------------------------------------------------------------------\n")
    DST.write_text(header + t, encoding="utf-8")
    print(f"Generado {DST.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
