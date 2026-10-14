# SD card files / Ficheros para la tarjeta SD

Copy these files to the root of the SD card. / Copia estos ficheros a la raíz
de la tarjeta SD.

| File / Fichero | Use / Uso |
|---|---|
| `ALESTE.ROM` | System ROM, loaded automatically by the MiST firmware (index 0): a 16 KB native boot block + the original 520EX ROM `AL512.BIN` (64 KB). Rebuild it with `tools/make_rom.py`. / ROM del sistema, la carga sola el firmware de MiST (índice 0): arranque nativo de 16 KB + la ROM original del 520EX `AL512.BIN` (64 KB). Se regenera con `tools/make_rom.py`. |
| `ALESTE.HD2` | CMOS (BIOS SETUP settings), mounted automatically as image 2. The core writes it back when SETUP changes the settings. / CMOS (ajustes del SETUP de la BIOS), se monta solo como imagen 2. El core lo guarda cuando el SETUP cambia los ajustes. |
| `dsk/ALESTDOS_TIME.dsk` | MSX-DOS boot disk of the 520EX with `TIME.COM` (sets the clock) and the BDOS patched for two drives. It is in a subfolder so that it is **not** mounted automatically: mount it from the OSD, or copy it to the root as `ALESTE.HD0` (drive A:) to mount it at power-on. / Disco de arranque de MSX-DOS del 520EX con `TIME.COM` (pone la hora) y la BDOS parcheada para dos disqueteras. Está en una subcarpeta para que **no** se monte solo: móntalo desde el OSD, o cópialo a la raíz como `ALESTE.HD0` (unidad A:) para que se monte al encender. |
| `ALESTE.CMO` | Blank CMOS image (512 zero bytes), a template: copy it as `ALESTE.HD2` to start again from scratch, or mount it from the OSD. / Imagen de CMOS en blanco (512 bytes a cero), una plantilla: cópiala como `ALESTE.HD2` para empezar de cero, o móntala desde el OSD. |
| `BOOT520.BIN` | The 16 KB native boot block alone (`tools/make_rom.py --boot-only`). / Solo el arranque nativo de 16 KB. |
| `DIAG.ROM` | Diagnostic ROM (source in `tools/diag/`). / ROM de diagnóstico (fuente en `tools/diag/`). |
| `BARS.WBS`, `GRIS.WBS` | Bus scripts for the video tests (OSD "Run bus script"). / Guiones de bus para las pruebas de vídeo (OSD "Run bus script"). |

`AL512.BIN` comes from the Aleste 520EX material published by hww
(github.com/hww/Aleste520EX). / `AL512.BIN` procede del material del Aleste
520EX publicado por hww (github.com/hww/Aleste520EX).
