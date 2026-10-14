# Cargador generico de la GameBios v2 (juegos de MSX2 con mapper de Konami)

- `gb2load.asm`: el cargador (.COM de MSX-DOS). Lee la ROM banco a banco y
  monta las paginas compuestas de 16 KB; monta la GameBios v2 en la pagina 0Fh
  (con sus tablas, la inversa de 3F00h en 3D00h y la rutina de bancos en
  0E00h); pone a cero la RAM del juego (pagina 3Fh) con los ganchos del MSX a
  RET; y arranca desde C000h: GameBios como pagina 0, paginas iniciales, salto
  a (4002h).
- `gb2bank.asm`: rutina de bancos (0E00h al ejecutar). El juego parcheado
  hace CALL BANK6/BANK8/BANKA (0E00h/0E19h/0E23h) con el banco en A, en lugar
  de LD (6000h/8000h/A000h),A: pone la pagina compuesta con tablas; conserva
  registros e indicadores.
- `*.bin`, `*.sym`: ya ensamblados (pasmo --bin x.asm x.bin x.sym), para no
  necesitar pasmo.
- `gb2build.py`: monta el cargador para un juego (paginas compuestas a partir
  de los bancos de cada ventana; GameBios tomada de un VKILLER.COM, que no se
  incluye).
- `test_gb2load.py ROM VKILLER.COM`: ejecuta el cargador en un emulador de Z80
  con el mapper del Aleste (64 paginas) y la BDOS simulados, y comprueba la
  memoria al llegar al juego.

Probado con Metal Gear (30 paginas compuestas 20h-3Dh): el cargador llega al
inicio del juego (41F3h) con las 30 paginas, la GameBios, sus tablas, la RAM y
el mapper bien; la rutina de bancos pone la pagina correcta en cada caso
(incluida la combinacion de paso al cambiar 8000h antes que A000h) sin tocar
registros ni indicadores.
