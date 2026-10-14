# Cartuchos de MSX en el Aleste 520EX: el emulador de los cargadores

Analisis de VKILLER.COM (disco msx-games del Aleste; desensamblado en la
documentacion de hww, "VDP Emulator"), base para `tools/msxrom2aleste.py`.

## Mapa del cargador

1. Carga VKILLER.1 / VKILLER.2 con la BIOS de MSX-DOS del Aleste (CALL 001Ch
   con IX = funcion e IY, la llamada entre paginas de la FOTON BIOS).
2. Pone la pagina 0Fh del mapper en 4000h y copia ahi el bloque de 03F5h
   (0DC2h bytes): **una pagina 0 de MSX de sustitucion** (abajo).
3. Copia tablas a 7E00h, 7F00h, 6F00h y 7560h, y rellena 7D90h-7F8Fh con RET.
4. Mapper final: 4000h pagina 17h, 8000h pagina 1Bh, C000h pagina 18h;
   FA7E = 0 (motor de la disquetera parado); salta a F675h.

## La pagina 0 de sustitucion (en 0000h al ejecutar el juego)

| Direccion | En un MSX | Aqui |
|---|---|---|
| 0003h | - | JP 0AB8h: esperar al cuadro (King's Valley: CALL 0003h en su bucle) |
| 0008h RST 08h | SYNCHR | JP 0300h: cambio de banco del mapper; el byte siguiente dice cual (FDh 6000h, FEh 8000h) |
| 0010h RST 10h | CHRGTR | JP 05FAh: OTIR al VDP |
| 0018h RST 18h | OUTDO | JP 05EDh: OUT de un dato al VDP |
| 0020h RST 20h | DCOMPR | JP 0224h: por identificar |
| 0038h RST 38h | interrupcion | JP 022Ah: interrupcion del Aleste en lugar de la del VDP |
| 0047h WRTVDP, 004Ah RDVRM, 004Dh WRTVRM, 0050h/0053h SETRD/SETWRT, 0056h FILVRM, 0059h LDIRMV, 005Ch LDIRVM, 005Fh CHGMOD, 0062h CHGCLR | BIOS | emulados (VDP por software) |
| 0093h WRTPSG, 0096h RDPSG | BIOS | emulados (AY del Aleste) |
| 0141h SNSMAT | BIOS | emulado (teclado del Aleste) |
| 0138h RSLREG | BIOS | devuelve FCh |
| RDSLT, WRSLT, CALSLT, ENASLT, DISSCR, ENASCR, CLRSPR, INIGRP, GICINI, GTSTCK, GTTRIG, WSLREG, **RDVDP** | BIOS | vacios (RET) |

RDVDP vacio explica los cambios a mano de King's Valley: su bucle esperaba la
interrupcion leyendo el estado del VDP.

VALLEY.COM y LEO.COM llevan otras variantes del emulador (no la misma tabla):
cada conversion se hizo con un emulador ajustado a su juego.

## Para un parcheador generico

- Mecanico: OUT (C),A y OTIR al VDP -> RST 18h / RST 10h (+ 00); escrituras
  al mapper de Konami -> RST 08h + banco; llamadas a la BIOS: se quedan.
- A mano (o con reglas por juego): esperas al VDP (RDVDP, IN (99h)), el gancho
  de interrupcion (H.TIMI, FD9Fh), detalles de temporizacion y sprites.

## Detalle de los servicios (punto 1 del plan)

- RST 20h (0224h) es DCOMPR (compara HL con DE), el de la BIOS de MSX.
- RST 00h (0316h) + byte: lee la pagina puesta en un cuarto del mapper
  (IN 7Cxx-7Fxx, OR F8h): para el codigo que consulta el banco actual.
- RST 08h (0300h) + byte: cambio de banco. El byte elige el cuarto del Aleste
  (B AND 3: FDh -> 4000h, FEh -> 8000h); el banco n del juego es la pagina
  D8h + n (las paginas 18h-1Fh tienen la ROM en trozos de 16 KB). **El mapper de
  Konami cambia bancos de 8 KB: solo sirve si el juego los cambia por parejas
  alineadas** (Vampire Killer: 0Eh en 8000h y 0Fh en A000h).
- Interrupcion (RST 38h, 022Ah): el Aleste interrumpe a 300 Hz; cada 5 llama
  a H.TIMI (FD9Fh) y explora el teclado (027Ah): **60 Hz, como un MSX japones**.
- SNSMAT (02F2h): fila de la matriz de teclado del MSX en 026Eh (la mantiene
  la interrupcion con el teclado del Aleste).
- WRTPSG (032Bh): al AY del Aleste por la PPI; los periodos de tono (R0-R5) se
  dividen entre 2 (AY del MSX a 1,79 MHz, el del Aleste a 1 MHz). RDPSG: R0-R13
  del AY; **R14/R15 (joystick) devuelven FFh: sin joystick, solo teclado**.
- VRAM: SETWRT/SETRD guardan la direccion (0667h). WRTVRM (0588h) guarda en
  una copia de la VRAM de 64 KB en las paginas D0h-D3h (ventana en 4000h) y
  actualiza la pantalla del Aleste; F800h en adelante va a 3000h. OUT (RST 18h),
  OTIR (RST 10h), LDIRVM, FILVRM y LDIRMV son bucles sobre WRTVRM/RDVRM.
- WRTVDP (03B4h): R1 0421h (modo, pantalla, sprites), R5 0411h y R6 0409h
  (tablas de sprites), R7 06A2h (fondo), R8 0437h, R14 0493h, R16 049Ch (MSX2),
  R23 04A1h (desplazamiento vertical del MSX2). **R0, R2, R3, R4 se ignoran: las
  tablas de nombres, colores y patrones van en las direcciones estandar de
  SCREEN 2/4.**
- CHGMOD (04C3h): pone el 520EX en alta resolucion con paleta (FABF = 7),
  programa los 16 registros del CRTC con una tabla propia (0548h), pone la
  pantalla en la pagina 3Fh (C000h), inicializa paleta y sprites, y enciende
  (FABF = 0Fh). Dibuja la pantalla del MSX en un modo grafico del Aleste.
- Espera de cuadro (0003h -> 0AB8h): sprites por software, uno de cada tres
  cuadros (compara la tabla de atributos D600h con la copia anterior).

## Que juegos pueden ir con este emulador

1. SCREEN 2 (o el 4 del MSX2) con las tablas en sus direcciones estandar.
2. Acceso al VDP por la BIOS o con OUT/OTIR al puerto de datos. Las escrituras
   al puerto de control (99h: direccion o registro, en parejas) hay que
   convertirlas en llamadas a SETWRT/WRTVDP: en Vampire Killer se reescribio
   el codigo a mano.
3. Sin esperas al estado del VDP (IN (99h), RDVDP): hay que cambiarlas por la
   espera de cuadro (CALL 0003h) o por el gancho H.TIMI.
4. Mapper de Konami cambiado por parejas alineadas, o ROM de 16/32 KB sin mapper.
5. Sonido por la BIOS (WRTPSG) o por OUT a A0h/A1h convertido en llamadas.
6. Control por teclado (sin joystick); sprites a 20 Hz.

## Punto 2: conversion generica del motor de Konami de 16 KB

El cargador de King's Valley (VALLEY.COM) no tiene nada propio del juego: abre
VALLEY.DAT (bloque de control en 02B6h), lee 16 KB, monta su emulador (MSX1,
SCREEN 2) en la pagina 0Bh con sus tablas en 2F00h-3410h de esa pagina (no en
la ROM), pone el juego en la pagina 0Ch y arranca con un trozo en F000h que
pone el emulador en 0000h y salta a (4002h). Sirve para cualquier cartucho de
16 KB cambiando el nombre del fichero.

Konami usaba el mismo motor en sus juegos de 1985: el gancho de interrupcion de
Yie Ar Kung-Fu (4043h) es el de King's Valley (401Ah) byte a byte salvo las
direcciones. Reglas genericas (`konami16` en `tools/msxrom2aleste.py`):
1. Gancho de interrupcion (36 bytes: CALL RDVDP, DI, CALL sonido, indicador,
   CALL logica x2, ..., RET): la interrupcion llama solo al sonido; la logica
   va a un bucle principal con CALL 0003h (espera de cuadro).
2. EI / JR $ del arranque -> JR al bucle (King's Valley uso un JP de 3 bytes,
   que piso el principio de 409Ch y obligo a desviar una llamada).
3. D9 ED 79 D9 (EXX / OUT (C),A / EXX) -> D9 00 DF D9. Solo con ese patron: un
   OUT (C) suelto puede ser un dato (Yie Ar 50C8h, en una tabla de punteros).
Validado: aplicadas a King's Valley, dan los mismos bytes que la conversion del
Aleste en el gancho y en los tres OUT; el resto (25 bytes) son arreglos propios
de King's Valley (colores, una lectura de la VRAM, sprites).

Yie Ar Kung-Fu (16 KB, GoodMSX, sha1 a3090a15...): gancho 4043h (sonido
7C5Ch), bucle 4049h, JR en 4041h, OUT en 443Ah y 4444h. Sin probar en la placa.

### Primera prueba de Yie Ar Kung-Fu y correcciones

Arrancaba, la demo funcionaba y sonaba, pero no respondia al espacio y los
luchadores salian a trozos. Causa: en el emulador de VALLEY.COM, 0003h **no
espera al cuadro**: cuenta llamadas y una de cada 5 dibuja los sprites desde la
lista de la RAM (E0B0h, 32 sprites: la convencion del motor de Konami). Con el
bucle principal sin sincronizar, la logica corria muchas veces por cuadro.
(El teclado estaba bien: SNSMAT traduce las 11 filas del Aleste con una tabla en
2F00h, espacio -> fila 8 bit 0; RDPSG(14), el joystick, devuelve FFh.)

Reglas corregidas:
1. Gancho: DI / CALL sonido / LD A,1 / LD (indicador),A / EI / RET.
   Bucle: EI / espera indicador / indicador = 0 / CALL logica x2 / CALL 0003h /
   JR bucle. La logica corre una vez por interrupcion (60 Hz), como el original
   (el indicador es el del juego: E005h en King's Valley, E006h en Yie Ar).
2. La copia de la lista de sprites E0B0h -> VRAM 3B00h se anula con RET (el
   emulador la lee de la RAM): en King's Valley coincide con el arreglo del
   Aleste (4B75h); en Yie Ar, 594Eh.
3. En la copia del cargador, los sprites se dibujan una de cada 2 llamadas
   (30 por segundo) en lugar de una de cada 5.
Pendiente: el titulo de Yie Ar sale recortado y algunos textos con colores
mezclados (tabla de colores de SCREEN 2 en el emulador).

### Segunda prueba de Yie Ar Kung-Fu

Ya responde al espacio, pero va lento (la fase 1 tarda en cargar, la partida
va despacio), los sprites siguen rotos y los colores del titulo mal. Lo lento es
el emulador por software del VDP a 4 MHz (cada byte de VRAM pasa por el; los
luchadores son muchos sprites superpuestos): de ahi el modo turbo del core.
Los colores: los dos juegos configuran el VDP igual (R2=0E, R3=7F, R4=07,
R5=76, R6=03), asi que no es eso; hipotesis: el emulador dibuja cada caracter
al escribir su nombre, y si el juego escribe despues patrones o colores, no se
redibuja. Pendiente de comprobar.

### Tercera prueba: se paraliza con la musica sonando

Con el turbo el luchador iba mas rapido al principio y luego se paraba; la
musica (interrupcion) seguia. Medido con un emulador de Z80 (Python): cada
redibujado de sprites del emulador de VALLEY.COM cuesta ~190.000 ciclos sin
sprites (recorre siempre las 32 entradas) y ~550.000 con 16: 47-140 ms a 4 MHz,
cuando un cuadro dura 16,7 ms. Con el bucle "logica, sprites, esperar cuadro"
la logica iba al ritmo de los sprites (5-10 veces mas lenta).

Bucle nuevo (36 bytes, los del gancho original):
- interrupcion: DI / CALL sonido / LD HL,contador / INC (HL) / EI / RET;
- bucle: espera contador > 0 / DEC (HL) / CALL logica x2 / si quedan cuadros,
  otra vuelta (la logica se pone al dia) / si no, CALL 0003h (sprites) / vuelta.
El juego va a 60 Hz y los sprites se actualizan con el tiempo libre (mas a
saltos, mas a menudo con el turbo). El emulador dibuja en cada llamada.

Tambien confirmado: WRTVRM del emulador solo redibuja al escribir la tabla de
nombres (3800h-3AFFh); los cambios de patrones o colores no repintan las
casillas ya puestas (el titulo de Yie Ar). La pantalla de fase genera
patrones en espejo leyendo y escribiendo 2.880 bytes de VRAM (4C38h).

### Medida corregida del coste de los sprites

La primera medida era de una sola llamada (con la copia interna vacia). Con
llamadas seguidas (emulador de Z80 en Python, el emulador de VALLEY.COM con la
lista de sprites del motor de Konami):
| situacion | ciclos por llamada |
|---|---|
| primera llamada | 187.000 - 544.000 |
| sprites quietos | ~6.000 |
| 8 sprites moviendose | ~226.000 |
| 16 sprites moviendose | ~451.000 |
El emulador compara cada sprite con su posicion anterior y solo redibuja los
que cambian: ~28.000 ciclos por sprite que se mueve (borrar, restaurar el
fondo, pintar): 7 ms a 4 MHz, ~2,8 ms a 16 MHz. Con dos luchadores de varios
sprites moviendose, los sprites no dan para 60 Hz: el bucle que pone la logica
al dia (la version actual) es lo que mantiene el juego a su velocidad.

## Manual de programacion del Aleste (programming-en.txt)

Confirma: AY a 1 MHz (de ahi dividir los periodos del MSX entre 2); pantallas
de 320x200 en 16 colores, 2 pixeles por byte (D7,D3,D5,D1 / D6,D2,D4,D0),
160 bytes por linea, 32 KB; mapper en MSX-DOS: paginas 0-3 pantallas, 4-7
sistema, 8-9 BIOS de MSX y de disco; paleta MSX de 64 colores (2 bits por
canal). No hay sprites ni copia de bloques por hardware ni otra interrupcion
programable que sirva para 60 Hz: el VDP del MSX solo se puede emular por
software, y lo que se puede mejorar es ese software (el coste por sprite que
se mueve).

## La GameBios (CPCWiki: "VDP Emulator aka GameBIOS")

No es un fichero aparte: va dentro de cada cargador .COM de los juegos
convertidos, como una pagina 0 de MSX de sustitucion. En Soft/ de hww:
kingvalley1.rar (VALLEY.COM + VALLEY.DAT), vampirekiller.rar (VKILLER.COM +
VKILLER.1/.2) y kingvalley2.rar (LEO.COM + LEO = King's Valley 2, 128 KB,
version MSX2: tabla del VDP con R0=04h, SCREEN 4).

| version | cargador (pagina 0 en memoria) | para | sprites |
|---|---|---|---|
| v1 (1994) | VALLEY.COM (06D8h) | MSX1, SCREEN 2 | lista en RAM propia de King's Valley (E0B0h) |
| v2 (1995) | VKILLER.COM (03F5h) | MSX2 (V9938), SCREEN 5 (mapa de bits) | tabla de atributos de la VRAM |
| v2 (1997) | LEO.COM (03CEh) | MSX2 (V9938), SCREEN 5 (mapa de bits) | igual que 1995; rutinas de VRAM 1 byte desplazadas |

Entradas comunes (la "traduccion de llamadas"): RST 00h lee la pagina de un
cuarto, RST 08h + byte cambia de banco, RST 10h OTIR al VDP, RST 18h OUT al
VDP, RST 20h DCOMPR, RST 38h interrupcion (60 Hz), 0003h sprites; BIOS de MSX
emulada: WRTVDP, RDVRM, WRTVRM, SETRD/SETWRT, FILVRM, LDIRMV, LDIRVM, CHGMOD,
(v2) CHGCLR, WRTPSG, RDPSG, SNSMAT, RSLREG; vacias: slots, DISSCR/ENASCR,
CLRSPR, INIGRP, GICINI, GTSTCK/GTTRIG, RDVDP. La v2 anade entradas de la BIOS
del MSX2 (0177h NWRVRM -> WRTVRM, y otras en 016Dh-017Dh).

La wiki dice que los juegos iban bien con el Aleste a 8 MHz (turbo) y cita
FireBird (de desplazamiento vertical) y Metal Gear, que no estan en Soft/.

Correccion: la v2 emula el SCREEN 5 (mapa de bits), no el SCREEN 4. Detalle completo y desensamblado comentado en doc/gamebios/.

### Cuarta prueba: buena velocidad, pero sin luchador; AUTOEXEC

El bucle solo dibujaba los sprites cuando la logica se habia puesto al dia del
todo: si la logica tarda algo mas de un cuadro, nunca. Ahora llama a 0003h
despues de cada paso de logica y el emulador redibuja una de cada 3 llamadas
(20 por segundo): los sprites salen siempre y la logica no espera. (Los
luchadores son sprites: 4CBEh copia los patrones de sprites 1A00h -> 1910h en
espejo.) Los ladrillos estropeados se explican igual: el emulador restaura el
fondo que guardo bajo cada sprite, y si pasa mucho entre dibujados el fondo ha
cambiado.

AUTOEXEC.BAT daba "YIEAR?" al arrancar (y funcionaba a mano). En lugar de
averiguar como lo procesa COMMAND.COM 2.2A (se reubica en memoria alta), el
cargador va ahora como COMMAND.COM: MSX-DOS lo carga al arrancar y el juego
empieza. --autostart bat / no para lo de antes.

### Quinta prueba: la musica se ralentiza al pelear

La rutina de sprites de la GameBios v1 dibuja cada sprite con DI (0554h,
05A3h): ~28.000 ciclos, ~7 ms a 4 MHz, mas de dos periodos de la interrupcion
del Aleste (3,3 ms). Las interrupciones que llegan se juntan en una: se pierden
y la musica (y el contador de cuadros) se ralentizan. El DI protegia de que el
gancho del juego se ejecutara con la pantalla en 4000h/8000h (donde esta la
ROM). Cambio en la copia del cargador que genera msxrom2aleste:
- rutina nueva al final de VALLEY.COM (0728h al ejecutar): lee las paginas de
  4000h y 8000h (el mapper se puede leer: C0h + pagina, el mismo formato que se
  escribe), pone las del juego (C5h, C6h), llama a 0177h (gancho y teclado) y
  las restaura;
- la interrupcion (0171h) la llama en lugar de 0177h;
- los dos DI de los sprites pasan a NOP: se dibuja con interrupciones.

### Sexta prueba: piezas sueltas, paredes negras, suelo que "se cae"

Fotos: los pantalones de Wang junto al marcador, paredes que se vuelven negras,
el suelo que se borra. Yie Ar termina su lista de sprites con Y = D0h (505Dh,
508Fh), como manda el VDP: lo de detras son datos viejos. El emulador de King's
Valley no respetaba esa marca y los dibujaba (y borraba) por la pantalla.
Rutina nueva en la copia del cargador (074Eh al ejecutar): antes de cada
redibujado copia la lista (E0B0h) a una intermedia (0780h) con esa entrada y
las siguientes ocultas (Y = E0h); el emulador lee la intermedia (LD IX en
04FCh, 0509h, 0516h). Probada en un emulador de Z80.

Comprobado de paso: el dibujado de casillas escribe en la pantalla (C0h/C1h) y
en la copia del fondo (C2h/C3h), y RST 18h es una llamada a WRTVRM: la copia
del fondo no se queda atrasada.
Pendiente: los colores del titulo (el emulador solo redibuja al escribir
nombres); el coste de los sprites al pelear.
