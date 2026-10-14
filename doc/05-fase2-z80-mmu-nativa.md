# Fase 2: Z80 y MMU nativa

El Z80 (tv80lx) y la MMU nativa del Aleste LX arrancan desde una ROM que el
firmware MiST carga de la SD. Se comprueba con una ROM de diagnostico propia
(`rom/diag.asm`) que ensena el resultado en pantalla.

## Que se ha anadido

```
aleste_core.sv
 ├ z80_system         (Aleste LX: tv80lx + mmu_native + mmu_legacy + z80_debug)
 ├ system_arbiter     (Aleste LX) maestros: Z80 (prioridad) y cargador
 ├ wb_wdt_simple      (Aleste LX) watchdog del bus, 64 ciclos
 ├ mist_loader        ahora en el puerto del antiguo puente UART
 └ address_decoder, video_ctrl_vga, sdram_wishbone   (fase 1)
```

- **Arranque.** La CPU esta en reset hasta que hay una ROM cargada por el
  indice 0, y tambien mientras se carga. Al terminar la carga (FIFO vacia)
  arranca en `0xC00000`: tras el reset la MMU pone las cuatro paginas del
  Z80 en el slot 3, banco 0. Sin `ALESTE.ROM` en la SD el core se comporta
  como en la fase 1 (los guiones `.WBS` siguen funcionando).
- **Reset del OSD.** Reinicia CPU y video. La SDRAM no se toca, asi que la
  ROM sigue cargada y la CPU vuelve a arrancar.
- **LED.** Fijo mientras carga, parpadeo lento si la CPU esta en HALT,
  parpadeo rapido si el cargador tuvo un error.

## Fallos del Aleste LX corregidos (`tools/gen_rtl.py`)

| Fichero | Problema | Efecto |
|---|---|---|
| `mmu_native.sv` | La direccion MMIO se forma con 26 bits truncados a 24: sale `FCpppp` en vez de `FF0000 + pagina*128 + puerto` (`docs/lx_mmu7.md`) | La CPU no llegaba al CRTC ni a la paleta: escribia en la SDRAM |
| `mmu_native.sv` | Senales usadas antes de declararse | Quartus error 10161 |
| `tv80lx.v` | `nxt_*` declaradas `wire` y asignadas en un `always` | Quartus error 10137 |
| `tv80lx.v` | En los `IN` el dato se recogia otra vez con el bus ya liberado | `IN` devolvia 00 o el dato segun la fase del reloj |
| `mmu_legacy.sv` | `;;` al final de dos declaraciones | Quartus error 10170 |

`tools/check_quartus.py` revisa los fuentes en busca de construcciones que
Quartus Lite rechaza (uso antes de declarar, `localparam` en `#(...)`,
variables con valor inicial no constante, `;;`). Sobre los originales encuentra los
problemas conocidos; sobre los ficheros del proyecto, ninguno.

## ROM de diagnostico (`rom/`)

`rom/diag.asm`, ensamblado con pasmo (`make` en `rom/`; ya va hecho en
`sd/DIAG.ROM`). En modo supervisor:

1. Pone el CRTC en 160x200x16 y la paleta de prueba por MMIO (pagina 2).
2. Comprueba:
   - **Z80**: llega a ejecutar.
   - **MMU**: escribe y relee registros del mapper.
   - **RAM 3MB**: escribe y comprueba muestras en 3 MB de SDRAM a traves del
     mapper (slots y bancos).
   - **MMIO**: lee registros del CRTC y de la paleta.
3. Escribe los resultados (OK verde / FALLO rojo), un contador que no para y
   16 barras con los colores de la paleta.

Resultado en simulacion (`doc/img/fase2_pantalla_sim.png`): las cuatro pruebas OK.

## Simulacion

`make fase2` en `sim/`: el banco `tb_fase2.sv` carga `rom/DIAG.ROM` por el
indice 0 como lo haria el firmware y comprueba:

- que la CPU no corre sin ROM ni arranca antes de acabar la carga
- que la ROM termina y las cuatro pruebas dan OK (lee los resultados de la SDRAM)
- que el contador avanza
- latencia del bus (maximo 9 ciclos de 54 MHz) y 0 errores de bus
- 0 errores de protocolo/tiempos en el modelo de SDRAM
- guarda la pantalla en `sim/obj2/pantalla.png`

`make` sigue ejecutando la prueba de la fase 1, ahora con la CPU presente y
parada.

## Prueba en la placa

1. Compilar, revisar TimeQuest como en la fase 1.
2. Copiar `aleste_poseidon.rbf` a la SD y `sd/DIAG.ROM` con el nombre
   `ALESTE.ROM` (o cargarla desde el OSD con "Reload ROM").
3. Al cargar el core el LED se enciende un momento (carga de la ROM) y debe
   aparecer la pantalla de diagnostico con las cuatro pruebas en OK y el
   contador avanzando (unas 4 veces por segundo).

Probado en la Poseidon: arranca y pasa las cuatro pruebas.

| Lo que se ve | Donde mirar |
|---|---|
| Pantalla negra con borde gris, LED apagado | No ha cargado la ROM: nombre del fichero (`ALESTE.ROM`) |
| Pantalla negra, LED fijo | La carga no termina: `data_io` / cargador |
| Pantalla con basura o sin texto | La CPU no llega al video: MMIO o la propia CPU |
| Alguna prueba en FALLO | Ese bloque; RAM en FALLO apunta a la SDRAM |
| Contador parado | La CPU se ha colgado |

## Lo que falta para usar la BIOS del Aleste LX

La BIOS de `aleste-lx/firmware/bios` se compila con z88dk, que no esta en los
repositorios de Ubuntu. Ademas esta a medias en el original (por ejemplo,
`crtc_init` usa la pagina MMIO 3 pero el CRTC esta en la 2). Cuando haya un
binario, se carga igual: renombrado a `ALESTE.ROM`.

Tampoco hay todavia interrupciones (`int_req_i` a 0, como en el top del
Aleste LX), teclado, PPI ni sonido: eso es la fase 3.
