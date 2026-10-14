# Aleste 520EX: referencia de hardware para las fases siguientes

Resumen de lo que hace falta para la compatibilidad con el Aleste 520EX
original (modo AMSTRAD y modo ALESTE/MSX-DOS). Fuentes:

- [hww/Aleste520EX/Documentation](https://github.com/hww/Aleste520EX/tree/master/Documentation):
  `programming.txt` / `programming-en.txt` (puertos), `schematic.txt`
  (descripcion de la placa, en ruso), `roms-content.txt` (volcado y funcion de
  las PROM), `BIOS Info/bios.txt` (variables de la BIOS FOTON).
  Los `.txt` estan en CP866: `iconv -f cp866 -t utf-8`.
- Esquemas: `sch_pcb/original-sch-gif` (originales) y
  `sch_pcb/aleste-520m-kicad` (520M en KiCad, sin el conversor de teclado).
- MAME, driver `al520ex` (`src/mame/amstrad/amstrad.cpp`, `amstrad_m.cpp`).
- `aleste-lx/docs/legacy_Info_io.md`, que ya recoge el mapa de E/S.

## ROMs

Las seis ROMs del juego `al520ex` de MAME. Las que se han encontrado
coinciden todas con MAME:

| Fichero | Tamano | CRC32 | Chip | Funcion |
|---|---|---|---|---|
| `AL512.BIN`   | 64 KB | `e8c2a9a1` | D31 27512 | ROM del sistema (4 paginas de 16 KB, ver abajo) |
| `RFCOLDAT.BIN`|  2 KB | `c6ace0e6` | D62 | Bus de datos de salida: colores AMSTRAD, recodificacion de paginas de ROM, VRAMACC |
| `RFVDKEY.BIN` |  2 KB | `cf2aa4b0` | D65 | Matriz del teclado (conversor), SYNC*, HY*, SINT* |
| `MAPPER.BIN`  | 256 B | `0daebd80` | D28 556RT4 | Configuraciones de RAM fijas del modo AMSTRAD |
| `ROMRAM.BIN`  | 256 B | `b3ea95d7` | D67 556RT4 | BUFER0/1, -ROMEN, -RAMEN (quien conduce el bus de datos) |
| `AF.BIN`      |  32 B | `c81fb524` | D69 155RE3 | FAPCh (PLL digital) del controlador de disco |

No se meten en el repositorio: se cargan desde la SD con el firmware MiST.

### AL512.BIN: paginas de ROM

| Pagina | Contenido | Donde se ve |
|---|---|---|
| 0 | AMSTRAD BIOS (firmware del CPC) | solo en 0000h |
| 1 | AMSTRAD BASIC | C000h |
| 2 | AMSTRAD DISC BIOS (AMSDOS) | C000h |
| 3 | Cargador MSX-DOS y ALESTE SETUP | C000h |

El puerto `DFxx` (seleccion de ROM alta) no va directo: D62 recodifica el
numero del CPC. Escribir 7 da la pagina 2, escribir 3 da la 3 y cualquier otro
valor da la 1 (BASIC). En 0000h solo puede aparecer la pagina 0. Al arrancar,
la BIOS del CPC recorre las ROM 0..15; al llegar a la 3, el SETUP mira las
teclas pulsadas (con SHIFT en el reset se queda en BASIC/AMSTRAD).
MAME pone la pagina 3 en la ranura 3 de ROM (`m_Amstrad_ROM_Table[3]`).

## Mapa de E/S

| Puerto | Decodifica | Funcion |
|---|---|---|
| `7Fxx` (A15=0) | multipuerto, como el Gate Array, con D7..D6 = funcion | ver abajo |
| `7Cxx..7Fxx` | mapper (con MAPMOD=1): registro = A9..A8 | pagina de 16 KB para cada cuarto del Z80. Se puede leer |
| `BCxx`/`BDxx` | MC6845 indice / dato | CRTC |
| `DFxx` | ROMPORT | pagina de ROM alta (recodificada, ver arriba) |
| `F4xx..F7xx` | 8255 | PA bus de AY/RTC/8253, PB, PC, control |
| `FA7E` | D0 = motor | disquetera |
| `FB7E`/`FB7F` | uPD765 (K1810VG72) estado / datos | |
| `FABF` | EXTEND PORT (solo escritura, solo la BIOS) | ver abajo |
| `EExx` | 8251 (K580VV51) | RS-232 / raton |

Multipuerto `7Fxx`, por D7..D6 del dato:

- `00`: D4 = 0 color / 1 borde, D3..D0 = numero de color (pen).
- `01`: color. Con MAPMOD=1, `RrGgBb` de 6 bits (64 colores, RGB222). En modo
  AMSTRAD, D4..D0 es el color hardware del CPC (0..31) que D62 traduce con la
  tabla en `RFCOLDAT[0x140..0x17F]`.
- `10`: D1..D0 modo de pantalla, D2 = 0 ROM / 1 RAM en 0000h, D3 = 0 ROM /
  1 RAM en C000h (igual que el RMR del CPC).
- `11`: configuracion de RAM del CPC (C0..C7), que en modo MSX se convierte
  en el mapper. Tabla en `MAPPER.BIN`.

EXTEND PORT `FABF` (copia en la BIOS: `EXTPORT` = `FDF5h`):

| Bit | Funcion |
|---|---|
| D0 | banco de VRAM 0/1 (64 KB) |
| D1 | MODE: 0 normal / 1 alta resolucion (el CRTC pasa de 1 a 2 MHz) |
| D2 | MAPMOD: 0 Amstrad / 1 mapper "Yamaha" (MSX) |
| D3 | pagina del mapper 0/1 (256 KB) |
| D4 | CS53: el 8253 (K580VI53) responde en el bus de la PPI |
| D5 | CSCT: 0 AY-3-8910 / 1 MC146818 (K512VI1) en el bus de la PPI |

Tras el reset D32, D55 y D56 se ponen a cero: arranca en configuracion AMSTRAD.

### PPI 8255

- PA: datos de AY, RTC y 8253 (los tres comparten el bus de la PPI).
- PB (lectura): PB0 VSYNC (en realidad HY* de la PROM D65, para que la
  duracion coincida con la del CPC), PB1 DISCINT (INT de la FDC; MAME solo lo
  pone con MAPMOD=1), PB6 BUSY de la impresora.
- PC (escritura): PC0..PC3 fila del teclado, PC4 strobe de impresora,
  PC6 BC1 y PC7 BDIR del AY.
- RTC: con CSCT=1, PC2..PC0 dan la funcion: 2 = AS (direccion), 4 = DS
  escritura, 5 = DS lectura. El dato va por PA, como el del AY.
- 8253: canal 0 = velocidad de recepcion y canal 1 = transmision del 8251
  (entrada de 4 MHz). El canal 2 cuenta HX con la puerta en CURSOR y su salida
  (-FUTURE, invertida) entra a los multiplexores de video: duplica los
  colores en los modos de 2 y 4 colores durante un numero de lineas.
  Para anularlo, canal 2 en modo 3 sin cargar. MAME no lo emula.

## Memoria

- Paginas de 16 KB. Mapper de 4 registros (uno por cuarto del Z80). El
  espacio de direcciones llega a 2 MB, pero el mapper de la placa original
  trabaja dentro de 512 KB (32 paginas; D3 del EXTEND PORT elige la mitad).
- Paginas 0-3: pantallas (VRAM). Paginas 4-7: sistema. Paginas 8-9: BIOS y
  BDOS de MSX (configuracion de MSX-DOS).
- En modo AMSTRAD el mapper esta bloqueado y `MAPPER.BIN` da las
  configuraciones fijas (192 KB, la tabla "original"; hay una variante
  modificada para 256 KB en `roms-content.txt`).
- Con una pagina de VRAM (0-3) mapeada, D62 activa VRAMACC y, si HIGHTY=1, la
  CPU ve A11 y A14 intercambiados (para escribir imagenes de alta resolucion).

## Video

- MC6845 con reloj de 1 MHz (normal) o 2 MHz (alta resolucion). Reloj de
  pixel 16 MHz en modo AMSTRAD y 13,333 MHz en modo ALESTE.
- Modos (por D1..D0 del multipuerto, `programming-en.txt` 3.3/3.4):

| Modo | Normal (AMSTRAD) | Alta resolucion (MODE=1) |
|---|---|---|
| 0 | 160x200, 16 colores | 640x200, 2 colores |
| 1 | 320x200, 4 colores | 320x200, 4 colores |
| 2 | 640x200, 2 colores | 640x200, 4 colores, 32 KB |
| 3 | - | 320x200, 16 colores, 32 KB |

- Bits por pixel: 4 colores = D7/D3, D6/D2, D5/D1, D4/D0; 16 colores =
  D7,D3,D5,D1 y D6,D2,D4,D0 (como el CPC).
- 32 KB: lineas pares en A+0..A+16383 y lineas impares en A+16384.. (tablas en
  `programming-en.txt`).
- Paleta: 16 entradas de 6 bits (RGB222). En modo AMSTRAD los 32 colores
  hardware salen de `RFCOLDAT[0x140..]` (MAME los usa tal cual).
- Valores del CRTC de la BIOS: R0=3F (6B en alta), R1=28 (50), R2=2E (52),
  R3=8E, R4=1F, R5=06, R6=19, R7=1B, R9=07, R12=30.

## Interrupciones

`-INT` cada 52 lineas empezando en la 18 (6 por cuadro), y si el
reconocimiento llega mas de 26 lineas tarde, la siguiente se retrasa 26
lineas. Es el comportamiento del Gate Array del CPC (sin esto CP/M no
funcionaba, dice la documentacion).

## Teclado

La placa original tiene un conversor: recorre la matriz fisica durante el
borrado horizontal con las tablas de `RFVDKEY.BIN` (0000-0057h columnas,
0200-0257h filas) y la vuelca a una RAM con la forma de la matriz del CPC,
una vez por cuadro. Para el core basta con generar directamente la matriz del
CPC desde el PS/2. La matriz (`programming-en.txt`):

| Fila | D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0 |
|---|---|---|---|---|---|---|---|---|
| 0 | f. | ENTER | f3 | f6 | f9 | ABAJO | DERECHA | ARRIBA |
| 1 | f0 | f2 | f1 | f5 | f8 | f7 | ALT (COPY) | IZQUIERDA |
| 2 | CTRL | \ | SHIFT | f4 | ] | RETURN | [ | BS (CLR) |
| 3 | . | / | : | ; | P | @ | - | ^ / £ |
| 4 | , | M | K | L | I | O | 9 | 0 |
| 5 | ESPACIO | N | J | H | Y | U | 7 | 8 |
| 6 | V | B | F | G | T | R | 5 | 6 |
| 7 | X | C | D | S | W | E | 3 | 4 |
| 8 | Z | CAPS | A | TAB | Q | ESC | 2 | 1 |
| 9 | DEL | R/L | J.F1 | J.F2 | J.R | J.L | J.D | J.U |
| 10 | Ъ | INS | HELP | F5/F10 | F4/F9 | F3/F8 | F2/F7 | F1/F6 |

Fila 10: F1 en el bit 0 (lo lee asi el SETUP del BOOTMENU, `LD D,10 / BIT 0,E ;F1`, y asi la define MAME). La tabla del manual de programacion tiene esta fila al reves; se corrigio en `rtl/cpc/kbd_520ex.sv`.

f0..f9 y f. son las teclas del bloque numerico (las f del CPC). La fila 10 es
propia del Aleste; el resto es la del CPC.

## MagicSound (placa externa)

Se selecciona con E/S y A5=A10=0; A9..A8 eligen el bloque:

| A9 A8 | Dispositivo |
|---|---|
| 00 | 8237 (DMA), A3..A0 registro, TC genera NMI |
| 01 | 8254 x2 (timers; no cuentan hasta la primera escritura al mapper de MS) |
| 10 | volumen, A1..A0 canal, D5..D0 |
| 11 | mapper de MS, A1..A0 canal, D4..D0 pagina de la memoria del Aleste |

El Aleste LX ya tiene su version (`aleste-lx/src/components/sound/ms2`).

## Correcciones y datos de CPCWiki

Copia completa en `doc/referencias/cpcwiki/`. Lo que cambia o amplia lo anterior:

- **Frecuencia de cuadro.** El 520EX no tiene una frecuencia fija: la marca
  el CRTC, como en el CPC. En modo AMSTRAD la BIOS programa 312 lineas
  (50 Hz) y la PPI dice 50 Hz (PB4 = LK4 = 1, "igual que en el CPC"). En el
  modo propio (MSX-DOS) la tabla del manual (R4=1F, R5=06) da 32*8+6 = 262
  lineas de 64 us: unos 59,6 Hz, como un MSX de 60 Hz.
- **Puerto B de la PPI:** PB5 (/EXP) a masa; PB3-PB2 con resistencia a +5 V;
  PB1 = INT de la FDC, **activa a 1** (CPCWiki la llama /DISCINT, pero el
  BOOTMENU espera el fin de una busqueda hasta que PB1 vale 1: `BIT 1,A ;
  DISKINT` / `JR Z,WSTP1`). Corregido en `aleste_core.sv`.
- **Interrupciones:** en el 520EX no se pueden borrar con RMR D4 (en el CPC
  si): ese bit es el LED RUS (y D5 el LED CAPS). Corregido en
  `aleste_core.sv`.
- **Gate Array:** se decodifica solo con A15 (cualquier E/S con A15=0).
- **EXTPORT (FABF):** CPCWiki da otro reparto que el comentario de la BIOS
  y MAME (tabla de arriba): D5-D4 = a quien va el puerto A de la PPI
  (0 PSG, 2 RTC, 3 8253), D3 = imagen a negro, D2 = MAPMOD, D1 = alta
  resolucion, D0 = decodificacion de la direccion de video. Hay que
  resolverlo con el esquema antes de la fase 3d.
- **Relojes:** CPU a 4 MHz en modo CPC (cristal de 16 MHz) y 3,2 MHz en modo
  Aleste (cristal de 13,333 MHz).
- **AY-3-8910 con los dos puertos:** el B (registro 15) es el dato de la
  impresora de 8 bits; el strobe es PC4 de la PPI.
- **Teclado:** fila 9 bit 6 = R/L (en el CPC, FIRE3 del joystick); fila 10:
  F1-F5 en los bits 7-3, HELP, INS y Ъ en los bits 2-0.

## Revision de la carpeta Documentation de hww

- BIOS Info: bios-grp(-en).txt es la biblioteca grafica de la FOTON BIOS
  (pixeles, lineas, rectangulos, copia de bloques con modos REPLACE/AND/OR/XOR/
  transparente, recorte). Declara campos para sprites (_SDBPTR, _SPRBUF) pero no
  tiene rutinas de sprites: no sirve para acelerar el emulador del VDP del MSX.
- programming.txt (ruso): el mismo contenido que programming-en.txt, mas
  extenso. Las unicas interrupciones que describe son las del reloj MC146818.
- startup.txt (montaje del kit):
  - El turbo era un circuito de dos chips (TM2, LA3) que habia que pedir a
    Patisonic, con un Z80H o TMPZ84C00AP-8; un interruptor, no un bit de
    software. Con turbo, algunos juegos de disco en modo AMSTRAD no cargan (se
    acortan las esperas del posicionamiento del cabezal). Igual que la opcion
    CPU speed del core.
  - Interruptor de cara de disco para el modo AMSTRAD: -SIDE a masa para usar
    la segunda cara del disco de 3,5" (como dar la vuelta a un disco de 3" del
    CPC 6128). En MSX-DOS debe estar abierto. (No implementado: posible
    opcion del OSD.)
- roms-content.txt: volcados de las PROM de la placa (RFVDKEY...).
- TurboModeComments.txt / TurboCircuit*.pdf: el circuito y las esperas de
  memoria del turbo.

## Comprobacion contra CPCWiki "Aleste 520EX - I/O Ports" (copia del 1-10-2026)

| Punto de la wiki | Core | Nota |
|---|---|---|
| Mapper 7Cxx-7Fxx (A15=0, A9-A8 pagina), lectura y escritura | igual | lectura = C0h OR pagina (la BIOS FOTON la usa) |
| Multiport 7Fxx (A15=0), registros 0-3 por D7-D6 | igual | |
| CRTC BCxx-BFxx | igual | |
| ROM superior DFxx: 00 BASIC, 03 BOOTMENU, 07 AMSDOS, resto BASIC | igual | recodificacion de la PROM D62 |
| 8251 EExx/EFxx | igual (decodificacion mas estrecha) | raton serie |
| PPI F4-F7xx | igual | |
| Motor FA7E, FDC FB7E/FB7F | igual | |
| EXTPORT FABF: D0 video, D1 alta resolucion, D2 MAPMOD, D3 pantalla en negro | igual | el core exige A5=1 (FADx es la MagicSound) |
| EXTPORT D5-D4 como campo: 0 PSG, 1 reservado, 2 reloj, 3 8253 | **distinto, el core sigue a la BIOS** | la BIOS de MSX-DOS (02B8h) escribe el 8253 con un pulso en D4 solo (FABC-FABF, A1-A0 = registro) y usa D5 solo para el reloj (SET 5): el core hace eso |
| 8253 en FABC-FABF (A1-A0) | igual | solo se guardan los registros |
| Puerto B: D7 cinta, D6 impresora lista (0), D5 /EXP=0, D4 50 Hz, D3-D2 = 1, D1 DISCINT, D0 VSYNC | igual | DISCINT activo a 1: lo confirma el BOOTMENU (BIT 1,A / JR Z) y el manual ("1 - FDC end of operation") |
| Puerto C: D4 = strobe de impresora (no motor de cinta) | **distinto a proposito** | el core usa PC4 como motor para que la cinta CDT arranque y pare sola, como en un CPC (el firmware lo maneja asi); no hay impresora |
| Fila 10: F1-F5 en los bits 7-3, HELP/INS/Ъ en 2-0 | **distinto, el core sigue al firmware** | el SETUP del BOOTMENU lee F1 en el bit 0 (LD D,10 / BIT 0,E ;F1) y MAME define la fila igual; la wiki copia la tabla del manual, que tiene esa fila al reves |
| R/L en la fila 9, bit 6 (FIRE3); sin FIRE3 en el joystick | igual | el joystick de MiST no llega al bit 6 |
