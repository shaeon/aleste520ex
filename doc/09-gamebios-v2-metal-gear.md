# La GameBios del Aleste 520EX

CPCWiki la llama "GameBIOS with VDP emulator": lo que usaba la gente del
Aleste para pasar juegos de MSX/MSX2. **No es un fichero aparte**: va dentro de
cada cargador .COM, como una pagina 0 de MSX de sustitucion (en 0000h al
ejecutar el juego), con la BIOS de MSX emulada y servicios propios.

| version | cargador | emula | sprites |
|---|---|---|---|
| v1 (1994) | VALLEY.COM (King's Valley) | MSX1, SCREEN 2 (patrones) | lista en RAM propia de King's Valley (E0B0h) |
| v2 (1995) | VKILLER.COM (Vampire Killer) | MSX2 (V9938), **SCREEN 5** (mapa de bits) | de la tabla de atributos, modo 2 del MSX2 |
| v2 (1997) | LEO.COM (King's Valley 2, MSX2) | igual | igual |

`gamebios/gamebios_v2_leo.asm`: desensamblado comentado de la v2 de 1997 (3.656 bytes,
47 rutinas con nombre). `gamebios/trace_dis.py`: el desensamblador (seguimiento del
flujo desde las entradas; necesita LEO.COM, de Soft/kingvalley2.rar de
github.com/hww/Aleste520EX).

## Como funciona la v2

- **Pantalla**: SCREEN 5 del MSX2 (256 pixeles, 16 colores, 2 pixeles por
  byte) sobre la pantalla de 16 colores del Aleste. WRTVRM guarda cada byte
  en una copia de la VRAM (64 KB, paginas D0h-D3h) y, si la direccion es menor
  que 8000h, lo escribe tambien en la pantalla, traducido con la tabla de
  3F00h (orden de los bits de cada pixel: MSX -> Aleste D7,D3,D5,D1 /
  D6,D2,D4,D0) y con la direccion de la linea de la tabla de 3E00h. Cada byte
  de VRAM es una escritura directa: rapido.
- **Desplazamiento vertical** (R23 del V9938): se traduce a la direccion de
  inicio del CRTC del Aleste (R12/R13): por hardware. De ahi que FireBird
  (desplazamiento vertical) "fuera muy bien", segun la wiki.
- **Comandos del V9938** (copias y rellenos de rectangulos, lineas): no se
  emula el motor de comandos; cada juego tenia sus rutinas que lo programaban
  (R#32-R#46) y se sustituian enteras por un JP a un servicio:

| servicio | funcion (por la rutina que sustituye en Vampire Killer) |
|---|---|
| 0200h | escribir la paleta (registro 16) |
| 0204h | LINE (comando 70h), una variante |
| 0208h | LINE, otra variante |
| 020Ch | HMMV: rellenar un rectangulo |
| 0210h | HMMM: copiar un rectangulo de VRAM a VRAM |
| 0214h | HMMC: copiar un rectangulo de la CPU a la VRAM |
| 0218h | por identificar (registros desde R#32) |
| 021Ch | dibujar un bloque de 8x8 (con HMMM) |
| 0220h | por identificar (Vampire Killer lo llama desde otras paginas) |

  Los parametros los recibe en los registros que usaba cada rutina del juego
  (convenio de Konami en Vampire Killer y King's Valley 2): un juego de otra
  casa necesitaria comprobar el convenio.
- **BIOS de MSX emulada**: WRTVDP (reparto por registro: R1, R5, R6, R7, R8,
  R14, R16, R23; el resto se ignora), RDVRM, WRTVRM, SETRD/SETWRT, FILVRM,
  LDIRMV, LDIRVM, CHGMOD (prepara el SCREEN 5), CHGCLR, WRTPSG, RDPSG, SNSMAT,
  RSLREG. Vacias: slots, DISSCR/ENASCR, CLRSPR, INIGRP, GICINI, GTSTCK/GTTRIG,
  RDVDP.
- **RST nuevos**: 00h (leer el banco), 08h + byte (cambiar de banco del mapper
  de Konami, por parejas de 8 KB), 10h (OTIR al VDP), 18h (OUT al VDP), 20h
  (DCOMPR), 38h (interrupcion: 300 Hz / 5 = 60 Hz, llama a H.TIMI y explora el
  teclado); 0003h: sprites.
- **Sprites**: por software, solo se redibujan los que cambian.

## Que juegos pueden ir con cada version

- **v2**: juegos de MSX2 en **SCREEN 5** que usen la BIOS o el puerto de datos
  del VDP, y comandos del V9938 en rutinas sustituibles por los servicios
  (Vampire Killer, King's Valley 2; segun la wiki tambien FireBird y Metal
  Gear). La wiki dice que necesitan el turbo (8 MHz) para ir a buena
  velocidad: en el core, *CPU speed*.
- **v1**: juegos de MSX1 en **SCREEN 2** (patrones), con la lista de sprites
  en E0B0h como el motor de Konami de 1985 (King's Valley; Yie Ar Kung-Fu con
  la conversion automatica de tools/msxrom2aleste.py). La v2 no sirve para
  estos: dibuja un mapa de bits, no patrones.

## Metal Gear (MSX2) y la GameBios v2

ROM: Metal Gear (Konami RC-750, 1987), traduccion al espanol (openMSX:
Translated, sha1 aa881a29...), 128 KB, mapper de Konami (escrituras en
6000h, 8000h, A000h), **SCREEN 5** (CHGMOD con A=5): el modo de la v2.

Comparte la biblioteca de rutinas del V9938 de Vampire Killer: seis rutinas
identicas (salvo las direcciones de las llamadas), en el mismo orden y con la
misma separacion:
| servicio | Vampire Killer | Metal Gear |
|---|---|---|
| 0200h paleta | 481Bh | 4E66h |
| 0204h LINE | 487Ch | 4EFCh |
| 0208h LINE | 48AFh | 4F2Fh |
| 020Ch HMMV | 4911h | 4F91h |
| 0210h HMMM | 494Dh | 4FCDh |
| 0218h | 49E2h | 5011h |
HMMC y el bloque de 8x8 no estan en Metal Gear.

El cargador VKILLER.COM no se puede reutilizar tal cual: copia un arranque
propio de Vampire Killer (296 bytes en 7560h) y rellena 7D90h-7F8Fh con RET,
zonas que en el original de Vampire Killer tampoco estaban libres: la
conversion reorganizo el codigo. En Metal Gear, al sustituir las seis rutinas
por saltos a la GameBios quedan unos 350 bytes seguidos (4E66h-5050h).

Falta por hacer para convertirlo: cargador propio para la v2 (GameBios de
VKILLER.COM o LEO.COM, tablas y arranque), escrituras al mapper -> RST 08h +
banco, accesos directos al VDP, las dos esperas RDVDP y el gancho de
interrupcion, y la llamada a los sprites (0003h).

### Metal Gear: el cargador y los bancos (primer analisis)

El cargador de Vampire Killer (VKILLER.COM) es especifico del juego:
- pagina 0Fh: GameBios (03F5h, 0DC2h bytes) + tablas en 3E00h, 3F00h, 2F00h y
  una inversa de 3F00h en 3D00h (al ejecutar: pagina 0 de MSX);
- pagina 18h: pagina 0 parcheada del juego, 7D90h-7F8Fh a RET y un arranque
  propio (296 bytes) en 7560h;
- el resto de la ROM en trozos de 8 KB en un orden propio: monta paginas de
  16 KB con las parejas de bancos que el juego pone a la vez (la GameBios
  cambia cuartos de 16 KB: RST 08h -> pagina D8h + n; el mapper de Konami,
  bancos de 8 KB en 6000h, 8000h y A000h).
- al arrancar: cuarto 3 = pagina 3Fh (RAM del juego y variables del MSX; la
  pone CHGMOD), ganchos en FD9Ah/FD9Fh.

Metal Gear: las 13 escrituras al mapper estan en la pagina 0, en unas pocas
rutinas centrales, con el estado en F0F1h/F0F2h/F0F3h (bancos de 6000h, 8000h,
A000h). Combinaciones: triples consecutivos (4/5/6), parejas n/n+1 en
6000h/8000h (cruzan la frontera de 16 KB: 6000h-7FFFh comparte cuarto con el
banco 0 fijo) y A000h por su cuenta (banco 15, la musica, en cada
interrupcion: 092Ch). Hacen falta paginas compuestas: cuarto de 4000h = banco 0
+ banco de 6000h (hasta 15); cuarto de 8000h = banco de 8000h + banco de A000h
(segun las combinaciones que use el juego). Copiar 8 KB por cambio (~43 ms a
4 MHz) no sirve: la musica cambia de banco en cada interrupcion.

### Metal Gear: inventario de bancos (punto 1)

Escrituras al mapper: solo las 13 de las rutinas centrales de la pagina 0
(las demas coincidencias de LD rr,6000h/8000h son punteros para leer datos, y
las de los bancos altos, datos). Variables: F0F1h/F0F2h/F0F3h (bancos de
6000h/8000h/A000h) y F0F6h (banco que se restaura en A000h).

| rutina | efecto |
|---|---|
| 424Eh / 426Ah / 4270h / 4276h | triples 4/5/6, 7/8/9, 10/11/12, 13/14/15 |
| 4920h / 4925h | A000h = 12 / 15, y F0F6h igual |
| 4198h | A000h = F0F6h (si no es 0) |
| 41ACh (interrupcion), 4284h | 6000h/8000h = 4/5 temporalmente, llamada, restaura |
| (banco 1) 02ECEh | F0F6h = 6 |

| ventana | bancos |
|---|---|
| 6000h | 1 (al arrancar), 4, 7, 10, 13 |
| 8000h | 2 (al arrancar), 5, 8, 11, 14 |
| A000h | 3 (al arrancar), 6, 9, 12, 15 |

Paginas compuestas de 16 KB: cuarto de 4000h = banco 0 + {1,4,7,10,13}
(5); cuarto de 8000h = {2,5,8,11,14} x {3,6,9,12,15} (25, todas por
seguridad). 30 paginas (480 KB); con la GameBios en marcha quedan unas 48
libres en el mapper del core (64 paginas).

Parche: cada LD (6000h/8000h/A000h),A (3 bytes) -> CALL (3 bytes) a una
rutina de bancos nueva en la pagina de la GameBios: guarda los bancos
actuales, busca la pagina compuesta en una tabla y la pone en el cuarto del
Aleste, conservando registros e indicadores (la escritura original no los
toca).

### Metal Gear: cargador propio (punto 2)

`tools/gb2/`: cargador generico de la GameBios v2 y rutina de bancos, probados
con Metal Gear en un emulador de Z80 con el mapper y la BDOS simulados (ver
tools/gb2/README.md). Siguiente: el parche del juego (13 escrituras al mapper
-> CALL a la rutina de bancos; seis rutinas del V9938 -> servicios de la
GameBios; sincronizacion e interrupcion; sprites).

### Metal Gear: parche del juego (punto 3)

`tools/gb2/metalgear.py` (cada cambio comprueba antes los bytes originales):
- 13 escrituras al mapper -> CALL BANK6/BANK8/BANKA (0E00h/0E19h/0E23h);
- seis rutinas del V9938 -> JP a los servicios 0200h-0218h (en el mismo byte
  que la conversion de Vampire Killer); espera del VDP (4ED2h) -> RET;
- biblioteca de video de la pagina 0: copia VRAM->RAM (4D3Eh) -> LDIRMV,
  RAM->VRAM (4D59h) -> LDIRVM, fijar direccion de escritura/lectura (4D93h,
  4DB2h) -> JP 0171h (NSTWRT) / 016Eh (NSETRD); OTIR -> RST 10h y
  OUT (C),A -> RST 18h (4D66h, 4D7Ch, 4D8Fh, 4DEBh, 4DF2h, 53CCh, 53D4h, y los
  dos OTIR del banco 15);
- interrupcion (H.TIMI -> 41ACh): tras la musica cuenta un cuadro en 0F60h
  (pagina de la GameBios) en lugar de llamar a la logica; el EI / JR $ del
  arranque (4245h) salta a un bucle principal (4F00h, hueco de la rutina LINE
  sustituida): espera cuadro, C005h = 1, CALL 6672h (logica), C005h = 0,
  CALL 0003h (sprites).

Inventario de accesos al VDP: fuera de la biblioteca de la pagina 0 solo los
dos OTIR del banco 15; el resto de coincidencias son datos.

`msxrom2aleste.py` reconoce Metal Gear por la receta (todos los bytes
originales coinciden) y genera MGEAR.DAT (ROM parcheada) + MGEAR.COM (cargador
propio con la GameBios del VKILLER.COM del disco msx-games).

`tools/gb2/run_game.py`: ejecuta el juego convertido en un emulador de Z80
(mapper del Aleste con lectura, BDOS para el cargador, interrupcion a 300 Hz)
y saca una captura de la pantalla del MSX desde la copia de la VRAM. Metal
Gear llega al logotipo de Konami (img/mgear_konami_emulador.png, paleta fija de
la captura): CHGMOD 5, borrados con HMMV, paleta, graficos a la segunda pagina
de la VRAM con LDIRVM y copias con HMMM; la logica y los sprites por cuadro.
Al arrancar la GameBios trabaja mucho con las interrupciones desactivadas
(176 de ~900 interrupciones en los 3 primeros segundos): con el turbo ira
mejor, como dice CPCWiki.

### Metal Gear: primera prueba en la placa (sin Snake)

Arranca (lento), la musica suena, pero no sale el personaje. Causa: la rutina
de sprites de la GameBios v2 no usa las tablas de la VRAM que indica el juego.
Las rutinas de R5/R6 calculan direcciones (0404h-0408h) que nadie lee; el
dibujo usa una lista fija en la RAM del juego, D600h-D67Fh (la de Vampire
Killer: LD IX,D67Ch / LD IY,387Ch, 32 sprites de 4 bytes), con su copia en
3800h-387Fh de la pagina de la GameBios. Como la v1 con King's Valley (E0B0h).
Lo que va a F800h o mas arriba (patrones de sprites) se guarda en 3000h-37FFh.

Metal Gear (registros por WRTVDP): R5 = EFh / E7h y R11 = 01h (atributos en
F600h o F200h, colores 200h antes), R6 = 1Fh (patrones en F800h). Construye
los sprites en el banco 15 (B8C1h-B910h): alterna dos juegos de tablas
(F600h/F400h y F200h/F000h, cambiando R5) y copia con OTIR los colores desde
tablas de la ROM y los atributos desde una lista en RAM (EA00h en adelante)
con un desplazamiento rotativo (C00Fh) para repartir el parpadeo.
Pendiente: llevar los sprites de Metal Gear a la lista que lee la GameBios
(D600h), o cambiar la direccion fija de la GameBios, viendo antes el formato
que espera (atributos y colores).

### King's Valley II y LEO.COM: la GameBios se adaptaba a cada juego

La ROM King's Valley II RC-760 (sha1 cfd872d0..., openMSX: KonamiSCC) es la
version MSX1 con SCC: no es la de LEO. LEO es la conversion de la version MSX2
(su tabla del VDP es de modo MSX2): los bancos de codigo de la MSX1 (0-3, 7,
8, 14, 15) no estan en LEO; solo coinciden bancos de datos (4, 5, 6, 10, 11,
12, 13), recolocados (10->4, 11->5, 12->6, 5->10, 6->11, 4->12, 13->15).

La lista de sprites que lee la GameBios v2 es la lista en RAM de cada juego:
- VKILLER.COM: D600h (LD IX,D67Ch / D600h; copia en 3800h). Vampire Killer
  original ya usa D600h como su lista de sprites (la llena de E0h, escribe ahi
  cada sprite).
- LEO.COM: E800h (la de King's Valley II), con tratamiento extra de algunos
  sprites (0AFCh, 0B1Dh y un grupo en E810h).
Para Metal Gear hay que hacer lo mismo: que la GameBios lea su lista (EA00h en
adelante, a confirmar formato y colores).

### King's Valley II MSX2 (RC-761) y la conversion LEO: los sprites

La ROM MSX2 (sha1 22704b82..., openMSX KonamiSCC) es la de LEO, con los
bancos reordenados (original -> LEO: 0->0, 1->9, 2->7, 3->8, 4->C, 5->A, 6->B,
7->1, 8->2, 9->3, 10->4, 11->5, 12->6, 13->F, 14->D, 15->E). Unos 2.450 bytes
cambiados en 211 sitios (bancos 0, 1, 2, 4, 6, 12, 13).

Sprites: el motor de Konami de MSX2 guarda los sprites en RAM (atributos,
4 bytes por sprite; colores, 16 bytes por sprite) y una rutina los sube a la
VRAM con rotacion (ADD A,68h / AND 78h). La conversion:
- anula esa rutina (King's Valley II 57FDh -> RET);
- el borrado inicial de las tablas de sprites de la VRAM (4ECDh) pasa a
  llenar de E0h la lista en RAM;
- la GameBios lee la lista en RAM del juego: VKILLER.COM atributos D600h y
  colores D400h; LEO.COM atributos E800h y colores D200h.

Metal Gear tiene el mismo motor (atributos EA00h, colores E800h): mismo
tratamiento (tools/gb2/metalgear.py: B8DEh del banco 15 -> RET; 4E2Ch -> lista
EA00h a E0h) y gb2build.gamebios_sprites() cambia las direcciones en la copia
de la GameBios de VKILLER.COM (0452h, 0475h, 050Dh, 0510h, 0AC8h; 0B2Eh,
0BEEh).

### Metal Gear en la placa: se juega (con detalles) y el desensamblado de Manuel Pazos

Prueba en la placa: sale Snake y empieza la partida. Pendiente: algun sprite
suelto en zonas pequenas; las barras rojas de la radio salen mal; a ratos un
sprite vuelve "transparente" a Snake.

Desensamblado comentado de Metal Gear (Manuel Pazos, 2018):
github.com/GuillianSeed/MetalGear (version japonesa e inglesa; la nuestra es
la traduccion al espanol, mismo codigo). Lo que aclara:
- logic/hudspritemask.asm: truco del limite de 8 sprites por linea. Pone 16
  sprites invisibles (Y = C0h y D0h, X = FFh) para que no se vean los sprites
  del ascensor sobre el marcador. La GameBios no tiene ese limite: dibuja lo
  que el juego da por oculto (los sprites sueltos).
- logic/updatesprites.asm: lista en RAM SprAttRAM (EA00h) y SpritesColors
  (E800h); doble juego de tablas (F600h/F400h, F200h/F000h); rotacion para
  repartir el parpadeo; "los sprites van por parejas para tener 3 colores por
  linea" (mezcla de colores CC del MSX2): candidato para Snake "transparente".
- Banks0123.asm DrawRadioLeds: los LED de la radio son copias HMMM de 8x8
  (VDP_Copy_Byte: BC = tamano, H/L = origen, D/E = destino, A = paginas
  origen/destino xxxxDDOO; los LED, de la pagina 1 a la 0).
run_game.py --snap: capturas periodicas. En 90 s de emulacion: logotipo,
titulo (6-18 s), demostracion con el marcador (24 s en adelante;
mgear_emulador_90s.png). No llega a la radio.

### Metal Gear: limite de 8 sprites por linea

tools/gb2/gb2spr.asm (0F70h, en la pagina de la GameBios), llamada desde el
bucle principal antes de los sprites (CALL 0003h): copia la lista del juego
(EA00h) a una intermedia (1200h) que es la que lee la GameBios. Por orden de
prioridad, como el VDP: un sprite que cae en una linea del tramo 192-211 (el
marcador, donde Metal Gear usa el truco) que ya tiene 8 sprites se oculta
entero (la GameBios no recorta sprites por lineas: un sprite del ascensor
desaparece entero al tocar el marcador, en vez de cortarse); Y = D8h termina
la lista. Descarte rapido de los sprites que no tocan el tramo. Coste: ~8.600
ciclos por cuadro (~2 ms a 4 MHz); ~41.000 con las 16 mascaras del ascensor.
Probada en el emulador de Z80 (mascaras, sprites en la zona de juego, fin de
lista, 10 sprites en una linea -> 8) y con el juego (llega a la demostracion,
la lista intermedia conserva los sprites de la zona de juego).

### Metal Gear: barras de la radio y Snake "borrado" (fotos de la placa)

Radio: cada LED nuevo salia mas abajo y a la izquierda (una columna de LED
fuera del transmisor). DrawRadioLeds llama dos veces a VDP_Copy_Byte (HMMM) y
entre medias suma 8 a E y luego a D: cuenta con que la rutina no cambie BC, DE
ni HL (la original solo los envia al VDP). Los servicios de la GameBios no los
conservan. Ahora cada rutina sustituida es un envoltorio: PUSH BC/DE/HL, CALL
al servicio, POP, RET (10 bytes, en el hueco de la rutina). El bucle principal
pasa a 4F06h (tras el envoltorio de la LINE de 4EFCh).

Snake con parte del cuerpo borrado: la rutina de sprites de la GameBios usa
solo los 4 bits bajos del color (AND 15 en 0B91h, 0B9Ah, 0C3Ch, 0C44h) e
ignora el bit CC (40h), la mezcla de colores de las parejas de sprites del
MSX2: pinta el segundo sprite de la pareja encima del primero. Pendiente.

### Metal Gear: marcador morado y cuelgue (foto en la sala de los tanques)

Marcador con fondo morado: con R8 = 02h (TP = 0) el color 0 del MSX2 es
transparente y muestra el fondo (R7 = 0, negro); su valor en la paleta no se
ve. Algunas salas lo definen y la GameBios lo aplicaba al color 0 del Aleste.
El envoltorio de la paleta (4E66h) ignora el color 0 (OR A / RET Z).
Cuelgue en esa sala: sin diagnosticar (Metal Gear no usa interrupciones de
linea; las rutinas de video originales no devuelven nada en BC/DE/HL).
