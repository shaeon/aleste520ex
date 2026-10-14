# Guía de uso del core Aleste 520EX para MiST (Poseidon)

Este core reproduce el **Aleste 520EX**, el ordenador ruso compatible con el
Amstrad CPC 6128 que además tiene un modo propio con más memoria, alta
resolución y **MSX-DOS**. Parte del proyecto Aleste LX de hww y añade lo que el
520EX necesita: modo CPC completo, disqueteras, reloj, cinta, MagicSound y el
modo Aleste con MSX-DOS.

---

## 1. Qué necesitas

- Una placa **Poseidon (EP4CGX150)** con el firmware de MiST.
- El fichero del core (`.rbf`) compilado a partir de este proyecto (ver el
  apartado 16).
- La **ROM del 520EX**, `AL512.BIN` (64 KB, la del set `al520ex` de MAME,
  CRC32 `e8c2a9a1`). **No se incluye** en el proyecto por derechos de autor.
- Una tarjeta SD con FAT32.

## 2. Preparar la tarjeta SD

En la **raíz** de la SD:

| Fichero | Para qué sirve | Obligatorio |
|---|---|---|
| `ALESTE.RBF` (o el nombre que des al core) | El core | Sí |
| `ALESTE.ROM` | ROM del sistema; se carga sola al arrancar el core | Sí |
| `ALESTE.HD0` | Disco que se monta solo en la unidad A: | No |
| `ALESTE.HD1` | Disco que se monta solo en la unidad B: | No |
| `ALESTE.HD2` | CMOS: configuración del SETUP del 520EX (512 bytes) | Recomendado |

**Cómo crear `ALESTE.ROM`:** une el arranque del core con la ROM del 520EX:

```
python3 tools/make_rom.py AL512.BIN -o ALESTE.ROM
```

**`ALESTE.HD2`:** ya viene en `sd/` (512 bytes a cero). Si quieres empezar de
cero, copia `sd/ALESTE.CMO` encima. El core irá guardando ahí la configuración.

Los nombres `ALESTE.HD0/HD1/HD2` son los que el firmware de MiST monta
automáticamente al cargar el core (si en la raíz no hay un `ALESTE.VHD`). Los
discos y el CMOS también se pueden montar a mano desde el menú.

## 3. Primer arranque

1. Carga el core desde el menú de MiST. El firmware carga `ALESTE.ROM` (el LED
   se enciende mientras carga).
2. Con la opción por defecto (*CPC boot: Aleste 520EX*) aparece el logotipo
   del 520EX («Aleste MC 520 EX»).
   - Si en A: hay un disco de MSX-DOS, lo carga y arranca **MSX-DOS**.
   - Si no hay disco, sale «BOOT ERROR. PRESS ANY KEY.»: pulsa una tecla o
     cambia de modo.
3. Para el **modo AMSTRAD** (BASIC 1.1 del CPC), elige *CPC boot: AMSTRAD
   (Shift)* y *Reset & apply model*.

La primera carga de MSX-DOS tarda unos 9 segundos (el 520EX dibuja el
logotipo por software mientras lee el disco). Con el CMOS montado, a partir
del segundo arranque MSX-DOS sale en un segundo.

## 4. El menú (OSD)

Se abre con **F12**.

| Opción | Qué hace |
|---|---|
| *Reload ROM* | Vuelve a cargar una ROM (`.ROM`) |
| *Load RAM image* | Carga una imagen de memoria (`.SCR`, `.BIN`) en el modo nativo del Aleste LX |
| *Run bus script* | Ejecuta un guion `.WBS` (pruebas del modo nativo) |
| *Load tape* | Carga una cinta `.CDT` o `.TZX` (modo AMSTRAD) |
| *Mount Drive A: / B:* | Monta un disco (`.DSK` o `.IMG`) |
| *Mount CMOS (setup)* | Monta el fichero de configuración (`.CMO`; o `ALESTE.HD2` automático) |
| *CPC boot* | Modo de arranque: *Aleste 520EX*, *AMSTRAD (Shift)*, *Aleste BIOS* |
| *Scanlines* | Líneas de barrido: Off, 25 %, 50 %, 75 % |
| *Audio* | *Mono* (todo por los dos lados) o *Stereo ABC* |
| *Disk speed* | *Original* (velocidad real) o *Fast* |
| *Floppy drives* | Número de disqueteras: 2 o 1 |
| *H centre / V centre* | Mueve la imagen en el monitor |
| *Mouse (CPC)* | Ratones Kempston, SYMBiFACE II y Multiplay (modo AMSTRAD) |
| *AMX mouse* | Ratón AMX por el joystick 1 (modo AMSTRAD) |
| *CPU speed* | 4 MHz (el 520EX), 8 MHz (su modo turbo) o 16 MHz. Acelera los juegos de MSX convertidos. **La cinta solo carga a 4 MHz**, y como en el 520EX real, con turbo algunos juegos de disco en modo AMSTRAD no cargan (se acortan las esperas del cabezal) |
| *Tape & audio* (submenú) | *Tape sound*, *Invert tape in*, *Test tone* |
| *Reset & apply model* | Reinicia y aplica el modo de *CPC boot* |

El firmware de MiST no cierra el menú al elegir *Reset & apply model*: el core
se reinicia, pero hay que cerrar el OSD con F12.

## 5. Modos de arranque

Elige el modo en *CPC boot* y aplica con *Reset & apply model*, o usa la tecla
RES (apartado 7) manteniendo la tecla correspondiente.

| Opción | Equivale en el 520EX a | Resultado |
|---|---|---|
| *Aleste 520EX* | Pulsar RES | Logotipo y MSX-DOS desde el disco |
| *AMSTRAD (Shift)* | SHIFT + RES | Modo CPC: BASIC 1.1 y AMSDOS |
| *Aleste BIOS* | BS + RES | **SETUP** del 520EX |

Desde BASIC también se vuelve al modo Aleste con el comando `|MSX`.

## 6. El teclado

El teclado del PC sigue la disposición del CPC en la fila de símbolos, como
en los cores de CPC de MiST.

| Tecla del PC | Tecla del 520EX |
|---|---|
| F1 – F5 | F1 – F5 |
| F6 – F10 | SHIFT + F1 – F5 |
| F11 | HELP |
| Insert | INS |
| Fin (End) | Ъ |
| Supr (Delete) | BS (CLR) |
| Retroceso | DEL |
| ` (a la izquierda del 1) o AltGr | R/L (cambio ruso/latino) |
| Alt | COPY |
| Teclado numérico | f0 – f9, f. y ENTER |
| = | ^ |
| [ | @ |
| ] | [ |
| \ | ] |
| ' | ; |
| ; | : |
| **Bloq Despl (Scroll Lock)** | **RES** (reset por hardware) |
| F12 | Abre el OSD (no llega al core) |

El **joystick 1** de MiST va a la fila del joystick del CPC.

## 7. Reiniciar: la tecla RES

El 520EX tiene una tecla **RES** de reset por hardware. Aquí es **Bloq Despl**:
mientras la tienes pulsada el ordenador está en reset, y al soltarla arranca
leyendo las teclas que mantengas pulsadas.

| Combinación | Resultado |
|---|---|
| Bloq Despl | Reinicio (con el modo de *CPC boot*) |
| SHIFT + Bloq Despl | Modo AMSTRAD |
| Supr + Bloq Despl | SETUP del 520EX |
| Esc + Bloq Despl | Recarga MSX-DOS del disco |

**`RESET.COM`** (en el disco de MSX-DOS) borra la copia de MSX-DOS de la
memoria y para la CPU: el LED parpadea despacio. Pulsa **Bloq Despl** y
MSX-DOS se recarga del disco.

## 8. El SETUP del 520EX y el CMOS

El SETUP (*CPC boot: Aleste BIOS*, o Supr + Bloq Despl) configura idioma,
fecha y hora, unidad de arranque, disco RAM, pantalla, colores, teclado,
ratón, impresora y puerto serie. **F1** guarda y sale; **ESC** sale sin
guardar.

La configuración vive en la memoria del reloj (MC146818). En el 520EX la
mantiene una pila; aquí se guarda en el fichero CMOS (`ALESTE.HD2` o el `.CMO`
que montes): al montarlo se carga, y cada vez que algo cambia el core lo
guarda en la SD a los 2 segundos. Además del SETUP, ahí quedan las sumas de
comprobación de MSX-DOS, que permiten arrancarlo sin volver a leerlo del
disco.

## 9. Disquetes y MSX-DOS

**Formatos:** `.DSK` (DSK y EDSK del CPC) y **raw** (imágenes MSX-DOS de 720 KB
como `alestedos-dev.dsk`; se reconocen por el tamaño). Para convertir una
imagen raw a EDSK: `python3 tools/raw2edsk.py disco.dsk -o disco_edsk.dsk`.

**Dos disqueteras:** con *Floppy drives: 2*, A: y B: son unidades
independientes. En modo AMSTRAD funcionan siempre (`|A`, `|B`, `CAT`). En
MSX-DOS depende del disco de arranque:

- `alestedos-dev.dsk` trae una BDOS para **una sola** disquetera: B: es una
  unidad «fantasma» que pide cambiar el disco («Insert diskette for drive B:»).
- `msx-games.dsk` ya trae la versión para dos.
- Para activar la segunda unidad en un disco de MSX-DOS:
  `python3 tools/bdos_2drives.py disco.dsk -o disco_2drv.dsk`.

**Crear disquetes con tus ficheros de MSX:** `tools/make_msxdisk.py` hace una
imagen de 720 KB con el contenido de una carpeta.

```
python3 tools/make_msxdisk.py carpeta/ -o JUEGOS.DSK
python3 tools/make_msxdisk.py carpeta/ -o JUEGOS.DSK --system alestedos-dev.dsk --2drives
```

- Sin `--system` es un disco de datos (para la unidad B:, o para A: una vez
  arrancado MSX-DOS).
- Con `--system DISCO` copia de un disco de sistema el arranque y `BIOS.SYS`,
  `BDOS.SYS`, `MSXDOS.SYS` y `COMMAND.COM`: el disco arranca MSX-DOS en el
  520EX. `--2drives` activa además la segunda disquetera.
- `--edsk` genera también la versión EDSK; `--size 360` hace un disco de una
  cara.
- Los nombres se pasan a 8.3 (`Mi programa.bas` → `MIPROGRA.BAS`; si dos
  coinciden, `NOMBRE~1`). MSX-DOS 1 no tiene subcarpetas: se avisa y se saltan.
- Con un disco que ya existe (como `wrdsk`/`rddsk` de fMSX):
  `--list DISCO` lista los ficheros; `--add DISCO FICHEROS|CARPETAS` los mete
  en el espacio libre (si ya hay uno con el mismo nombre, lo sustituye; si no
  cabe, el disco no se toca); `--extract DISCO [-d CARPETA] [NOMBRES]` los saca
  con la fecha del disco. Por ejemplo, para meter `TIME.COM` en tu disco de
  MSX-DOS: `python3 tools/make_msxdisk.py --add ALESTDOS.DSK TIME.COM`.

**Disquetes para el modo AMSTRAD:** `tools/make_amsdisk.py` hace imagenes del
formato DATA del AMSDOS (40 pistas, 178 KB) con el contenido de una carpeta:

```
python3 tools/make_amsdisk.py carpeta/ -o JUEGOS.DSK --split
```

Conserva la cabecera AMSDOS de los ficheros. Con `--split` reparte en varios
discos (JUEGOS1.DSK, JUEGOS2.DSK...) manteniendo juntos los ficheros de cada
programa: lee las cadenas de los cargadores BASIC (`RUN"!KT.BIN"`) para saber
que carga cada uno, y copia en cada disco las bibliotecas que usan varios
programas (como Laser BASIC).

**Cartuchos de MSX:** el 520EX no tiene VDP ni MSX-BASIC; algunos cartuchos se
adaptaron a mano (disco `msx-games` del Aleste). `tools/msxrom2aleste.py` aplica
esas conversiones a tu ROM y crea el disquete:

```
python3 tools/msxrom2aleste.py KINGSVALLEY.ROM --games msx-games.dsk \
        --dsk VALLEY.DSK --system alestedos-dev.dsk --2drives
```

Reconoce la ROM por su MD5: King's Valley (RC-727) y Vampire Killer (RC-744,
**cartucho europeo**; si tienes otra version, la herramienta te dice cual hace
falta). Si no la conoce y es un cartucho de 16 KB con el motor de Konami de 1985
(Yie Ar Kung-Fu y similares), intenta una **conversion automatica** (sin
garantias: puede necesitar arreglos a mano). El cargador lo toma del disco
`msx-games`. `--dsk` exige `--system`
(sin sistema el disquete no arranca). El juego arranca solo: por defecto el
cargador hace de `COMMAND.COM` (el disco no da el `A>` de MSX-DOS);
`--autostart bat` usa un `AUTOEXEC.BAT` y `--autostart no`, ninguno. Con `--analyze` lista los accesos al hardware del
MSX de una ROM no conocida.

**Ojo con las descargas de GitHub:** «Guardar enlace como…» en la web de
GitHub descarga la página HTML y no el disco. Usa el botón *Download* (o
*Raw*). Un «disco» que empieza por `<!DOCTYPE html>` da «BOOT ERROR».

## 10. Cinta (modo AMSTRAD)

1. Arranca en modo AMSTRAD.
2. En el OSD, *Load tape* y elige un fichero `.CDT` (o `.TZX`).
3. En BASIC: `|TAPE`, luego `RUN"` y pulsa una tecla en «Press PLAY then any
   key». El motor lo controla el propio ordenador.

**Con un magnetófono de verdad** (Poseidon, SiDi y Calypso, por la entrada de
audio de la placa; la MiST no tiene): conecta la salida del magnetófono a la
entrada de audio, haz lo mismo que en el paso 3 y pulsa PLAY en el
magnetófono. Mientras se reproduce un fichero CDT/TZX manda el fichero; si no,
la entrada de audio. Si no carga, prueba *Invert tape in* y el volumen del
magnetófono.

En *Tape & audio*:
- *Tape sound*: oír la cinta por los altavoces (el fichero o, con el motor en
  marcha, la entrada de audio).
- *Invert tape in*: invierte la señal, para cintas que no cargan.
- *Test tone*: un tono de 1 kHz para comprobar el audio.

El modo MSX del 520EX no tiene cinta (ni su BIOS ni MSX-DOS la usan), así que
no hay carga de ficheros `.CAS`.

`tools/make_cdt.py` crea cintas de prueba con un programa BASIC o binario:
`python3 tools/make_cdt.py --basic '10 PRINT "HOLA"' PRUEBA.CDT`.

## 11. Sonido

- **AY-3-8910**, como en el CPC.
- **MagicSound**, la tarjeta de muestras de 4 canales de Patisonic. Funciona
  con el reproductor de módulos `MAG.COM` (disco `mag-player.dsk`): en
  MSX-DOS, `mag axelf`.
- *Audio*: en *Mono* los canales van por los dos lados; en *Stereo ABC* los
  canales del AY se reparten y los de la MagicSound van A+D a la izquierda y
  B+C a la derecha.

## 12. Fecha y hora

- El reloj del 520EX se pone en hora en el **SETUP** (campos *Current date* y
  *Current time*).
- Si la placa tiene reloj, el core toma la hora de MiST al arrancar.
- Sin reloj en la placa, la hora se pierde al apagar (la configuración no:
  va en el CMOS).
- En MSX-DOS, `DATE` muestra la fecha; para la hora, **`TIME.COM`** (en
  `msx/` y en el disco `ALESTDOS_TIME.DSK`): `TIME` la muestra, `TIME hh:mm`
  o `TIME hh:mm:ss` la cambia.

## 13. Ratón

El 520EX lleva el ratón en el **puerto serie** (un ratón serie del tipo Mouse
Systems), y lo atiende la BIOS de MSX-DOS. En el core, el ratón USB/PS/2
conectado a la MiST hace de ese ratón serie.

1. Entra en el SETUP (*CPC boot: Aleste BIOS*, o Supr + Bloq Despl).
2. Pon **Mouse** en activado y guarda con **F1** (con el CMOS montado, se
   recuerda).
3. Arranca MSX-DOS: los programas que usan el ratón de la BIOS (por ejemplo
   `NC`) ya lo ven.

El ratón solo envía datos cuando el software ha activado el puerto serie.

**Ratón en modo AMSTRAD.** Los programas de CPC no conocen el puerto serie del
520EX: usan los ratones del mundo CPC, que el core emula a la vez con el mismo
ratón de la MiST (como los cores Amstrad de MiST y MiSTer):

| Ratón | Programas | Opción del OSD |
|---|---|---|
| Kempston (`FBEE`, `FBEF`, `FAEF`) | programas que lo admiten | *Mouse (CPC): Enabled* |
| SYMBiFACE II (`FD10`) | SymbOS y otros modernos | *Mouse (CPC): Enabled* |
| Multiplay (`F990`-`F997`) | SymbOS, juegos | *Mouse (CPC): Enabled* |
| AMX (por el joystick 1) | AMX Art, OCP Art Studio y otros clásicos | *AMX mouse: Joystick 1* |

El AMX convierte el movimiento en pulsaciones del joystick 1: actívalo solo
con programas que lo usen.

## 14. Vídeo

- La salida va por VGA a **31 kHz** (doblador de líneas de MiST). Para un
  monitor de **15 kHz** (SCART, CRT) pon `scandoubler_disable=1` en el
  `mist.ini`.
- Resoluciones del 520EX: las del CPC y las de alta resolución del modo Aleste
  (640×200 a 4 colores y 320×200 a 16 colores).
- La imagen sale centrada según el estándar en 15 kHz (PAL) y en 31 kHz
  (576p), igual en todos los modos. Si un monitor VGA la corta, es el ajuste
  que tiene guardado: restablece la geometría del monitor para ese modo y haz
  el **ajuste automático en modo AMSTRAD**, donde el borde azul ocupa toda la
  imagen y el monitor detecta bien los bordes. En alta resolución el fondo es
  negro y el ajuste automático puede equivocarse.
- *H centre* y *V centre* mueven la imagen si aún hace falta.

## 15. El LED

| LED | Significado |
|---|---|
| Encendido | Cargando un fichero (ROM, cinta…) |
| Parpadeo lento | La CPU está parada (`HALT`), por ejemplo tras `RESET.COM` |
| Parpadeo rápido | Error al cargar un fichero |

## 16. Compilar el core

Proyectos de Quartus (guardados con **Quartus Prime 22.1 Lite**):

| Placa | Proyecto | FPGA | Audio |
|---|---|---|---|
| Poseidon | `poseidon/aleste_poseidon.qpf` | EP4CGX150 | I2S |
| MiST | `mist/aleste_mist.qpf` | EP3C25 (Cyclone III) | sigma-delta (jack de la placa) |
| SiDi | `sidi/aleste_sidi.qpf` | EP4CE22 | sigma-delta (jack de la placa) |
| Calypso | `calypso/aleste_calypso.qpf` | 10CL025 (Cyclone 10 LP) | I2S |

Abre el proyecto y compila; el `.rbf` sale en `output_files/` de cada carpeta.
La SiDi tiene una FPGA mucho más pequeña (22.000 elementos lógicos frente a
150.000): si el core no cabe, el informe del fitter lo dirá.
La Calypso tiene 25.000 elementos lógicos y una SDRAM de 8 MB (las otras, 32 MB):
el core recoloca su memoria dentro de esos 8 MB. La cinta sigue admitiendo
hasta 4 MB. El LED 0 de la placa es el de actividad.

Las herramientas de `tools/` son de Python 3. Las simulaciones (`sim/`) usan
Verilator; ver `README.md` y `doc/` para los detalles técnicos de cada fase.

## 17. Problemas frecuentes

| Problema | Solución |
|---|---|
| Al cargar el core no arranca | Comprueba que `ALESTE.ROM` está en la raíz y se creó con `make_rom.py` |
| «BOOT ERROR. PRESS ANY KEY.» | No hay disco de MSX-DOS en A:, o el fichero no es un disco (ver apartado 9) |
| Una tecla se queda pulsada al abrir el OSD | No debería pasar; si pasa, pulsa y suelta esa tecla |
| B: en MSX-DOS muestra lo mismo que A: | Disco con BDOS de una unidad: usa `bdos_2drives.py` |
| La imagen sale cortada o descentrada | Ajuste automático del monitor, o *H centre* / *V centre* |
| La configuración del SETUP se pierde | Monta el CMOS (`ALESTE.HD2` en la raíz) |
| No suena la cinta en los altavoces | *Tape & audio* → *Tape sound: Enabled* |
| La cinta no carga | Prueba *Invert tape in: On*; usa `|TAPE` antes de `RUN"` |

## 18. Créditos

- **Aleste LX** (base del core): hww — https://github.com/hww/aleste-lx-fpga-sv
- Documentación, ROM y software del 520EX: hww — https://github.com/hww/Aleste520EX
- CPCWiki, MAME (`al520ex`) y Caprice32-Aleste como referencias.
- **u765**, **UM6845R** y el reproductor de cintas **tzxplayer**: del core
  Amstrad de MiST (gyurco, Sorgelig).
- **mist-modules**: https://github.com/teiram/mist-modules
- 520EX original: Patisonic, Omsk.
