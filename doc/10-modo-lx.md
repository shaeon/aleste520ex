# Modo Aleste LX

El Aleste LX de hww (aleste-lx-fpga-sv) se quedó a medias: la parte compatible
(Z80, MMU, CRTC, paleta, SDRAM) funciona, pero el PIC, la DMA, la Magic Sound 2
y el acelerador gráfico estaban sueltos, solo con pruebas unitarias, y la BIOS
(aleste-xi-bios) no llegaba a arrancar en hardware real. Este modo lo completa
en las placas con sitio (MiSTer), con la macro `ALESTE_LX`.

## Uso

1. Compilar la BIOS: `lx/build.sh` (necesita z88dk; sin instalarlo,
   `docker run --rm -v "$PWD":/src -w /src/lx z88dk/z88dk sh build.sh`).
   Deja `lx/build/LX.ROM` (64 KB) y una copia en `sd/LX.ROM`.
2. Montar el ALESTE.ROM con la BIOS LX detrás de AL512.BIN:

       python3 tools/make_rom.py AL512.BIN --lx sd/LX.ROM
       copy /b BOOT520.BIN + AL512.BIN + LX.ROM ALESTE.ROM   (sin Python)

   El cargador deja la imagen LX en 410000-41FFFF. Con el ALESTE.ROM de
   siempre (sin LX) el 520EX funciona igual.
3. En el OSD: **CPC boot → Aleste LX** y reset.

En modo LX la CPU arranca en modo nativo y ve en C00000-C0FFFF (slot 3,
bancos 0-3, donde la BIOS LX espera estar) la imagen de 410000. El arranque
del 520EX en C00000 no se toca. El modo se recoge en cada reset de la CPU.

## La BIOS

`lx/aleste-xi-bios` es el repositorio de hww sin tocar; los arreglos van en
`lx/patches/` y `lx/build.sh` los aplica sobre una copia:

- enlazado: las rutinas de la biblioteca quedaban en 0000h, encima del crt0,
  y DRV_DATA (621 bytes desde FF00h) se salía de los 64 KB;
- puertos: el CRTC está en 20h/21h de la página MMIO 2 (FF0120) y el slot del
  supervisor en FAh, como en el FPGA y en el emulador de hww;
- los drivers de CRTC y paleta eligen su página MMIO y conservan los
  registros que destruían;
- paso de parámetros de `vbuf_clear` y `vbuf_draw_char`, cálculo del carácter
  en la fuente, modo 16k1b (640x200, 1 bit) con el vídeo en C40000.

Arranca, pone el modo 640x200 y escribe "ALESTE LX BIOS - MiSTer". El parche
`0002-perifericos-lx.patch` añade una comprobación de los periféricos del
modo LX (PIC, TIMER, MS2 y DMA: OK o --), un pitido de 150 ms por la Magic
Sound 2 y un contador de segundos desde el arranque con el temporizador.

## Mapa de E/S nativo

Puerto `F1h` = página MMIO; los puertos `00h-7Fh` acceden a
FF0000 + página × 128 + puerto. Las direcciones de DMA son físicas (24 bits).

| Página | Dirección | Dispositivo | Fichero |
|---|---|---|---|
| 0 | FF0000-FF001F | PIC | rtl/lx/lx_sys.sv |
| 0 | FF0040-FF005F | Temporizador del sistema | rtl/lx/lx_sys.sv |
| 2 | FF0100-FF011F | Paleta | (vídeo del LX) |
| 2 | FF0120-FF013F | CRTC | (vídeo del LX) |
| 6 | FF0300-FF037F | DMA / blitter | rtl/lx/lx_dma.sv |
| 7 | FF0380-FF03FF | Magic Sound 2 | rtl/lx/lx_ms2.sv |

### PIC (página 0, 00-08)

Registros como en `wb_z80_pic.sv` de hww, en IM 1 (la CPU va a 0038h):

| Puerto | | |
|---|---|---|
| 00/01 | RW | máscara (1 = habilitada) |
| 02 | RW | vector base para IM 2 |
| 03/04 | R | pendientes y habilitadas |
| 05/06 | R | pendientes |
| 07/08 | W | 1 = borra el pendiente |

Las líneas se capturan por flanco de subida; INT se mantiene mientras haya
alguna pendiente y habilitada, así que el manejador tiene que borrarla.

| Línea | Fuente |
|---|---|
| 0 | STORAGE: disquetera |
| 1 | DMA_COM: fin de la DMA |
| 2 | GPU: VBlank del vídeo nativo |
| 3 | AUDIO: Magic Sound 2 |
| 4 | LEGACY: interrupción del Gate Array (300 Hz) |
| 6 | SYSTIMER: temporizador |

### Temporizador (página 0, 40-46)

| Puerto | | |
|---|---|---|
| 40 | RW | bit 0 marcha, bit 1 periódico |
| 41/42 | RW | periodo en µs (0 = 65536) |
| 43/44 | R | cuenta que queda (leer 43 congela 44) |
| 45/46 | R | contador libre de milisegundos |

### Magic Sound 2 (página 7)

Reescrita a partir de la de hww (allí el control pisaba los volúmenes, el paso
se salía del bloque del canal y el mezclador usaba el canal 0 para los cuatro).
Cuatro canales de muestras con signo (8 o 16 bits) leídas por DMA a 48 kHz.

| Puerto | | |
|---|---|---|
| 00 | RW | bit 0 habilita |
| 01/02 | RW | volumen global izquierdo / derecho |
| 03 | R | [3:0] fin de muestra, [7:4] sonando; W 1 = borra el fin |
| 04 | RW | bit 0 IRQ de fin de muestra, bit 1 IRQ del temporizador |
| 05 | R | bit 0 fin, bit 1 temporizador; W 1 = borra |
| 10/11 | RW | periodo del temporizador en muestras (160 = 300 Hz, 960 = 50 Hz) |
| 20-2F … 50-5F | | canales 0-3 |

Canal (+0 a +F): `+0` CTRL (bit 0 suena, 1 bucle, 2 16 bits, 3 IRQ al
terminar), `+1..+3` START, `+4..+6` END (no incluido), `+7..+9` LOOP,
`+A`/`+B` volumen izquierdo/derecho, `+C..+E` paso 8.16 (010000h = 48 kHz),
`+F` estado. El byte alto (+3, +6, +9, +E) aplica el valor.

### DMA / blitter (página 6)

Copia y relleno de rectángulos, byte a byte.

| Puerto | | |
|---|---|---|
| 00 | W | bit 0 arranca, bits 2-1 modo (0 copia, 1 relleno, 2 copia con transparente), bit 3 IRQ al terminar; R bit 0 ocupado |
| 01 | R | bit 0 fin pendiente; W 1 = borra |
| 02-04 | | origen |
| 05-07 | | destino |
| 08/09 | | ancho en bytes |
| 0A/0B | | alto en líneas |
| 0C/0D | | paso de línea del origen (con signo) |
| 0E/0F | | paso de línea del destino |
| 10 | | byte de relleno o color transparente |

## Pruebas

`sim/tb_lx.sv` (`make lx ROM=...`) carga un ALESTE.ROM con la imagen LX, traza
E/S y bus, mide el audio de la MS2, enseña memoria (`+peek=HEX +peekn=N`) y
vuelca un cuadro. ROMs de prueba en `lx/test/` (pasmo):

| ROM | Resultado en simulación |
|---|---|
| BIOS LX | texto, los cuatro periféricos OK y el pitido (unos 900 cambios de signo en 150 ms) |
| pictest | 59 interrupciones del temporizador en 60 ms, 4 VBlank |
| ms2test | onda cuadrada a 187,5 Hz, ±4064, 7 fines de muestra y 11 ticks de 300 Hz en 40 ms |
| dmatest | relleno 8x3, copia 4x2 y copia con transparente correctos, 4 IRQ |

## Pendiente

- Drivers de la BIOS para PIC, temporizador, MS2 y DMA.
- IPC (FF0020): en MiSTer el "MCU" podría ser el ARM por hps_io.
- Acelerador gráfico con conversión de formatos de píxel (el blitter cubre
  la copia de rectángulos).
