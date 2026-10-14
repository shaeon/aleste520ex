# Fase 1: sistema de video en la Poseidon

Objetivo: comprobar en la placa lo que no depende de la CPU. Es el
`aleste_video` del Aleste LX (CRTC, paleta, scaler, SDRAM) con el puerto de
carga cambiado: en vez del puente UART, el firmware MiST por `data_io`.

## Estructura

```
aleste_mist_top.sv   placa: PLL, user_io, data_io, OSD, pines, SDRAM_CLK
 └ aleste_core.sv    lo comun: resets, cargador, bus, video, SDRAM, refresco
    ├ mist_loader.sv      data_io -> FIFO 2048 -> maestro Wishbone
    ├ address_decoder     (Aleste LX)
    ├ video_ctrl_vga.sv   video_ctrl con vga_timing en vez de llhdmi (generado)
    │   ├ memory_arbiter.sv, color_palette.sv, mc6845mod.sv (generados)
    │   ├ pixel_pipeline.sv (generado)
    │   └ video_buffer, hdmi_scaler (Aleste LX)
    └ sdram_wishbone      (Aleste LX)
```

Los ficheros "generados" (`video_ctrl_vga`, `memory_arbiter`, `color_palette`, `mc6845mod`, `pixel_pipeline`) salen de `tools/gen_rtl.py`, que parchea los
originales con reemplazos exactos (ver la cabecera del script). El submodulo
`aleste-lx` no se toca.

## Decisiones

- **Relojes.** 108/54/27 MHz desde 50 MHz, del mismo PLL y en fase. El Aleste
  LX pasa datos entre esos dominios sin sincronizadores, asi que el `.sdc` no
  los declara asincronos.
- **Video.** El CRTC y el scaler van esclavos del barrido de salida (720x480,
  27 MHz, 31,47 kHz, 59,94 Hz), que es VGA estandar. Por eso `vga_timing`
  reproduce el contador de `llhdmi` y solo cambia la salida. No se usa el
  scandoubler de `mist_video`: el OSD va directo. Sincronismos negativos.
  No hay modo de 15 kHz en esta fase.
- **Carga.** `F0` ROM -> `0xC00000` (donde arranca la MMU nativa; el firmware
  la carga sola como `ALESTE.ROM`), `F1` imagen -> `0x000000`, `F2` guion de
  bus `.WBS` (registros de 4 bytes: direccion de 24 bits + dato). El guion
  sustituye a los scripts Python por UART del Aleste LX.
- **Reloj de SDRAM.** `clk_system` invertido por `altddio_out`, como en
  NewBrain (y como el `ODDRX1F` del original).

## Problemas del Aleste LX encontrados (y como se resuelven aqui)

| Problema | Efecto | Solucion |
|---|---|---|
| `wb_refresh_i` del controlador SDRAM atado a 0 | Lo que no barre el video (ROM en `0xC00000`) se pierde en ~64 ms | Generador de auto-refresh cada 7,2 us en `aleste_core` |
| `memory_arbiter`: `=` y `<=` sobre `sdram_req_o` | Quartus error 10110 (y Verilator) | `tools/gen_rtl.py` |
| `color_palette`: `logic x = control_logic[..]` y `logic yjk_mode = ...` | Es valor inicial, no asignacion continua: modo de escritura, autoincremento y modificador fijos | `tools/gen_rtl.py` (`wire`) |
| `memory_arbiter.clke_i` recibe el reloj de 54 MHz como dato | Ruta de reloj a logica, mala para timing | A 1: solo cambia la fase del ack, que igual cae en un flanco de 54 MHz |
| `T_RC` = 6 ciclos | 55,6 ns a 108 MHz; la SDRAM pide 60 | `.T_RC(7)` en la instancia |
| REFRESH justo al volver a IDLE tras una lectura | La rafaga de 4 con autoprecarga aun no ha acabado: viola tRP | El refresco espera 3 ciclos seguidos en IDLE |
| La RAM de la paleta no tiene valor inicial y varios presets no la cargan | Imagen negra aunque todo funcione | `aleste_wbs.py --palette` |
| `llhdmi` usa el DrawArea sin retrasar en el canal verde | Verde desplazado un pixel | `vga_timing` usa el retrasado en los tres |
| `mc6845mod`: `localparam` dentro de `#(...)` (SV-2009) | Quartus Lite: error 10170 | `tools/gen_rtl.py` (`parameter`) |
| `pixel_pipeline`: `logic pixel = 0` escrita por un `always_comb` | Dos procesos escriben la misma variable | `tools/gen_rtl.py` (sin valor inicial) |
| `video_ctrl` incluye `config_27mhz.vh` | Quartus no lo encuentra por `SEARCH_PATH` desde un `.qip` (error 10054) | `tools/gen_rtl.py` lo copia dentro |

Los avisos de tiempos de la SDRAM los encontro el modelo de `sim/`.

## Ventana de lectura de la SDRAM

`sdram_wishbone` saca READ en el flanco N y recoge el dato en N+3 (ack0 en el
ciclo T_RCD+CAS, muestreado un ciclo despues). La SDRAM ve la orden en N+0,5
(reloj invertido) y con CL2 el dato de la primera palabra es valido desde
N+1,5 + tAC hasta N+2,5 + tOH, mas los retardos de ida y vuelta de la placa.
Sin retardos la ventana no contiene un flanco de `clk_system`; con los
retardos reales (salida DDR + pistas) se desplaza hacia N+3, y por eso
funciona en el ECP5 del original. El `.sdc` lo modela: retardos del chip
(los mismos que NewBrain en esta placa) y un multiciclo de 2 desde
`sdram_clk` a `clk_system`. **Es lo primero que hay que mirar en TimeQuest.**
Si no cierra: bajar a 96 MHz o pasar a CL3 (parametro `CAS` del controlador
y un ciclo mas de espera).

## Simulacion (`sim/`)

`make` en `sim/` (Verilator 5 con `--timing`) simula `aleste_core` con un
modelo de SDRAM que comprueba tRCD, tRAS, tRP, tRC, tWR y choques en DQ:

- carga 16 KB a 3 MB/s (ritmo del SPI) y 2 KB a 9 MB/s: FIFO maxima 90 de
  2048, sin desbordes
- guion de bus al CRTC, la paleta y la memoria, sin timeouts
- 18433 bytes comprobados en el modelo de SDRAM: 0 mal
- barrido 858 x 525
- auto-refresh cada 7,22 us
- 0 errores de protocolo/tiempos de la SDRAM

`make run PLUSARGS=+wbs=../../sd/BARS.WBS` ejecuta ademas el guion de
barras y comprueba la imagen: 16 barras de 40 pixeles en la linea 240.

## Prueba en la placa

1. Compilar `poseidon/aleste_poseidon.qpf` (Quartus 22.1 Lite) y revisar
   TimeQuest, sobre todo las rutas de SDRAM.
2. Copiar `aleste.rbf` y `sd/BARS.WBS` a la SD.
3. Al arrancar: imagen negra con borde gris (la paleta esta vacia). El LED se
   enciende mientras carga.
4. OSD -> "Run bus script" -> `BARS.WBS`: 16 barras verticales de colores.
   `GRIS.WBS`: las mismas barras en 16 grises.
5. LED parpadeando = error del cargador (FIFO llena o escritura sin
   respuesta).

Si las barras salen pero con colores o bloques corruptos, es la SDRAM
(timing). Si no hay imagen, el PLL o el `.sdc`. Si el LED no se enciende al
cargar, `data_io`.
