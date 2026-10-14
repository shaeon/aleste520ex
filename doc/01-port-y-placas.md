# Aleste LX para placas MiST (Poseidon, MiST, SiDi, Calypso)

**Guía de uso:** [doc/00-guia-de-uso.md](00-guia-de-uso.md) (preparar la SD, menú, teclado, modos, discos, cinta, sonido y problemas frecuentes).

Port del [Aleste LX](https://github.com/hww/aleste-lx-fpga-sv) (rama `dev`),
la reimplementacion en FPGA del Aleste 520EX que hace hww para ECP5, a las
placas de la familia MiST. Se desarrolla primero en la **Poseidon**
(Cyclone IV GX EP4CGX150).

El Aleste LX esta en desarrollo y todavia no es un ordenador completo (no hay
PPI, AY ni teclado conectados en su top). Este port va por fases:

| Fase | Estado | Contenido |
|---|---|---|
| 1 | hecha | Video + SDRAM + carga desde la SD, sin CPU |
| 2 | hecha | Z80 y MMU nativa, arranque de una ROM desde la SD (ROM de diagnostico) |
| 3a | hecha | Modo CPC del 520EX: arranca su ROM hasta BASIC, video con la temporizacion real (50 Hz, 15/31 kHz, `doc/video.md`) |
| 3b | hecha | Teclado PS/2 del 520EX y sonido AY por I2S |
| 3c | hecha | Disquetera: DSK/EDSK y raw (MSX-DOS 720 KB), unidades A y B; conversor raw2edsk.py (`doc/06-fase3-modo-amstrad.md`) |
| 3d | **esta** | Modo propio del 520EX: BOOTMENU, mapper MSX, FABF, reloj, alta resolucion; arranca MSX-DOS (`doc/07-fase3d-modo-msxdos.md`) |

## Organizacion

Igual que [NewBrain](https://github.com/shaeon/newbrain): un top comun con
macros por placa y una carpeta por placa.

```
aleste-lx/          submodulo: Aleste LX (rama dev), sin modificar
common/mist-modules submodulo: user_io, data_io, osd...
rtl/                top MiST, nucleo, cargador, barrido VGA y copias
                    parcheadas (generadas) de diez ficheros del Aleste LX
poseidon/           proyecto Quartus, PLL y .sdc de la Poseidon
sim/                banco de pruebas Verilator con modelo de SDRAM
tools/              gen_rtl.py y gen_u765.py (parches), aleste_wbs.py (guiones
                    de bus), raw2edsk.py (discos raw a EDSK), bdos_2drives.py
                    (segunda disquetera en MSX-DOS), make_msxdisk.py (disquete
                    de MSX-DOS a partir de una carpeta), make_rom.py,
                    make_rom.py (ALESTE.ROM del modo CPC),
                    check_quartus.py (construcciones que Quartus rechaza)
sd/                 ficheros de prueba para la SD
rom/                ROM de diagnostico de la fase 2 (pasmo)
doc/                notas de cada fase y referencia del 520EX
```

## Compilar

```
git clone --recursive <este repositorio>
cd poseidon
quartus_sh --flow compile aleste_poseidon
```

La fase 1 compila en Quartus y cumple tiempos. Ver `doc/04-fase1-video.md` y `doc/05-fase2-z80-mmu-nativa.md`.

## Uso

Copiar a la SD `aleste_poseidon.rbf` y un `ALESTE.ROM`:

- Modo CPC del 520EX: `copy /b sd\BOOT520.BIN + AL512.BIN ALESTE.ROM` (la ROM
  del 520EX no se incluye; ver `doc/06-fase3-modo-amstrad.md`). Arranca en BASIC.
- Diagnostico de la fase 2: `sd/DIAG.ROM` renombrada a `ALESTE.ROM`.

En el OSD:

- **Reload ROM** (`.ROM`, indice 0): a `0xC00000`. El firmware carga solo
  `ALESTE.ROM` al iniciar el core. La CPU espera a que termine la carga.
- **Load RAM image** (`.SCR`, `.BIN`, indice 1): a `0x000000`.
- **Run bus script** (`.WBS`, indice 2): escrituras al bus (CRTC, paleta,
  memoria). `sd/BARS.WBS` pone el modo 160x200x16 y dibuja 16 barras.
- **Reset**: CPU y video (la ROM sigue en memoria).

Para hacer guiones: `tools/aleste_wbs.py --help` (usa los presets de video del
Aleste LX).

## Actualizar el Aleste LX

```
git submodule update --remote aleste-lx
python3 tools/gen_rtl.py      # falla si un parche ya no encaja
cd sim && make
```

## Licencias

El Aleste LX es de H2W (MIT en `main`, Apache 2.0 en `dev`). `mist-modules`
es GPL. `rtl/cpc/UM6845R.v` es de Sorgelig (Amstrad_MiST/MiSTer), GPL v2.
Las ROMs del Aleste 520EX no se incluyen.

## Ficheros que se cargan o montan solos

En la raiz de la SD, con el nombre del core:

| Fichero | Que es |
|---|---|
| `ALESTE.ROM` | ROM del sistema (`tools/make_rom.py`) |
| `ALESTE.HD0` | disco de la unidad A: (raw, DSK o EDSK) |
| `ALESTE.HD1` | disco de la unidad B: |
| `ALESTE.HD2` | CMOS: RAM del reloj (SETUP y sumas de MSX-DOS), 512 bytes; `sd/ALESTE.CMO` renombrado |

## SiDi

`sidi/aleste_sidi.qpf`: Cyclone IV E EP4CE22F17C8, reloj de 27 MHz (PLL a
108/54/27 MHz y 80 MHz para el video), audio sigma-delta por AUDIO_L/AUDIO_R
(`dac.vhd`). Pines y ajustes tomados del port de NewBrain a la SiDi. Cabe con
optimizacion por area (98 % de los elementos logicos) y cumple los tiempos en
los tres modelos (54 MHz con +1,4 ns tras rehacer el calendario del reloj).

## Calypso

`calypso/aleste_calypso.qpf`: Cyclone 10 LP 10CL025YU256C8G (placa CYC1000),
reloj de 12 MHz (PLL a 108/54/27 MHz, x9; y 80 MHz para el video, x20/3), VGA de
4 bits por color, 8 LED (LED 0 = actividad), audio I2S y entrada de audio para
la cinta. Pines tomados del port de NewBrain a la Calypso. Macro CALYPSO.

SDRAM de 8 MB (4096 filas x 256 columnas x 4 bancos, 12 lineas de direccion)
frente a los 32 MB de las otras placas: el controlador se configura con filas
de 12 bits y columnas de 8, y `memory_arbiter.sv` recoloca las cuatro regiones
del core (bits 23-22 de la direccion de bytes) en ventanas: RAM 2 MB en
000000h, ROM del modo CPC 1 MB en 200000h, arranque nativo 1 MB en 300000h y
cinta 4 MB en 400000h. En modo nativo, mas de 1-2 MB por region se repetiria
(no se usa para el 520EX).

El proyecto sale del de la SiDi quitando solo las asignaciones que se
sustituyen (familia, dispositivo, macros, ficheros fuente y pines);
`GENERATE_RBF_FILE ON` se conserva (un filtro por "FILE" lo quitaria y Quartus
no generaria el .rbf).

