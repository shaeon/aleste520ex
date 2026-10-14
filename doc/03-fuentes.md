# Fuentes de documentacion del Aleste 520EX

| Fuente | Que tiene | Que usamos |
|---|---|---|
| [hww/Aleste520EX](https://github.com/hww/Aleste520EX) | Documentacion (CP866), esquemas originales (GIF, PCAD) y del 520M (KiCad), ROMs, software, discos, MagicSound | Referencia principal: `doc/02-hardware-aleste520ex.md` |
| [LasDesu/Aleste-520EX](https://github.com/LasDesu/Aleste-520EX) | Autor del 520M: esquemas KiCad, mismos documentos (en UTF-8) y ROMs, y dos PAL | `doc/referencias/lasdesu/*.PLD` |
| [CPCWiki](https://www.cpcwiki.eu/index.php/Aleste_520EX) | Puertos, diferencias con el CPC, PROMs, fuente del BOOTMENU, diferencias de BIOS | `doc/referencias/cpcwiki/` |
| MAME, driver `al520ex` | Emulacion parcial (sin 8253 ni MagicSound) | Juego de ROMs de referencia |

## Lo que hay en cada una

**LasDesu.** Los documentos de `doc/` son los mismos que los de hww (solo
cambia la codificacion). Las ROMs son identicas a las de MAME. Los esquemas
KiCad son los del 520M (no identicos byte a byte a la copia de hww). Lo nuevo
son dos PAL que sustituyen a PROMs en el 520M:

- `PALROM.PLD` (GAL22V10) hace el trabajo de la PROM D62 (`RFCOLDAT`):
  tabla de colores del modo CPC (la "original no uniforme", que coincide con
  `RFCOLDAT[0x140..]`, y una alternativa "uniforme pero mas oscura"),
  VRAMACC (acceso de la CPU a las paginas de video) y la recodificacion de
  la pagina de ROM alta. Confirma lo que ya esta en el core.
- `FDATASEP.PLD` (GAL16V8) es el separador de datos de la disquetera (lo que
  hace la PROM `AF`). No hace falta: la disquetera se emulara a nivel de
  sector, no de bit.

**hww, fuera de `Documentation`:**

- `ROM/Aleste_ROM_Jaime.zip` (unidad espanola, CRC32 `52a1f2de`): otra
  revision de la ROM baja (cambia la zona de las rutinas de cinta), BASIC
  identico, BOOTMENU casi identico (2 bytes), pero **la segunda mitad de
  AMSDOS (A000-BFFF) esta a FF**: volcado incompleto, la disquetera no iria.
  Usamos la de MAME (`e8c2a9a1`).
- `ROM/roms.rar`: el mismo juego que MAME (lo que se puede extraer coincide).
- `Soft/Disks/`: `alestedos-dev.dsk` y `mag-player.dsk` son imagenes en bruto
  de 720 KB (FAT12, 9 sectores, 2 caras, sin cabecera EDSK) de MSX-DOS con el
  `BIOS.SYS`/`BDOS.SYS` del Aleste; la segunda trae el reproductor de
  MagicSound y modulos STM. `msx-games.dsk` lleva una cabecera de 16 bytes.
  Para la fase 3c: el controlador de disco tiene que aceptar imagenes en bruto
  de 720 KB, no solo EDSK.
- `MagicSound/`: esquema, PCB y `mag.txt` (fuente del driver). Para cuando
  se conecte el `ms2` del Aleste LX.
- `Documentation/Turbo*`: modo turbo (CPU a 8 MHz).

No se copian al repositorio ni las ROMs ni el software (no son nuestros).
