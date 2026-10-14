; ============================================================================
; GameBios v2 (1997) del Aleste 520EX - desensamblado comentado
;
; Origen: LEO.COM, el cargador de King's Valley 2 (version MSX2) en
; Soft/kingvalley2.rar de github.com/hww/Aleste520EX. Codigo de la gente del
; Aleste (Patisonic / Foton); aqui solo se desensambla y comenta para
; documentar su API. CPCWiki la describe como "GameBIOS with VDP emulator".
;
; El cargador copia 0E48h bytes de LEO.COM (03CEh) a la pagina 0Fh del mapper;
; al ejecutar el juego queda en 0000h-0E47h como pagina 0 de MSX de
; sustitucion, con tres tablas de 256 bytes de LEO.COM en 3E00h (direccion de
; cada linea de pantalla), 3F00h (traduccion de los bits de cada pixel del
; MSX al Aleste) y 2F00h.
;
; Es un emulador del SCREEN 5 del MSX2 (V9938): mapa de bits de 256 pixeles
; y 16 colores escrito directamente en la pantalla de 16 colores del Aleste,
; desplazamiento vertical (R23) con el CRTC, comandos del V9938 como servicios
; (0200h-0220h) y sprites por software. La version 1995 (VKILLER.COM) es la
; misma con las rutinas de VRAM un byte mas arriba. La de 1994 (VALLEY.COM,
; King's Valley) es otra: MSX1, SCREEN 2 por patrones.
;
; Desensamblado con seguimiento del flujo desde las entradas (tools: ver
; doc/09-gamebios-v2-metal-gear.md). Las lineas DB son datos o variables.
; ============================================================================


; --------------------------------------------------------------------------
; RST 00h + byte: lee la pagina puesta en un cuarto del mapper (para el
; codigo que consulta el banco)
; --------------------------------------------------------------------------
RST00:
    JP do_RST00                       ; 0000  c3 16 03

; --------------------------------------------------------------------------
; 0003h: redibuja los sprites (llamar una vez por cuadro desde el bucle del
; juego)
; --------------------------------------------------------------------------
FRAME:
    JP do_FRAME                       ; 0003  c3 b7 0a
    DB FFh, FFh                                                    ; 0006  ..

; --------------------------------------------------------------------------
; RST 08h + byte: cambio de banco del mapper de Konami (byte: cuarto del
; Aleste; banco n = pagina D8h+n)
; --------------------------------------------------------------------------
RST08:
    JP do_RST08                       ; 0008  c3 00 03
    DB 00h, C9h, 00h, 00h, 00h                                     ; 000B  .....

; --------------------------------------------------------------------------
; RST 10h: OTIR al puerto de datos del VDP (B bytes desde HL a la VRAM)
; --------------------------------------------------------------------------
RST10:
    JP do_RST10                       ; 0010  c3 f9 05
    DB 00h, C9h, 00h, 00h, 00h                                     ; 0013  .....

; --------------------------------------------------------------------------
; RST 18h: OUT de A al puerto de datos del VDP (escribe en la VRAM y avanza
; la direccion)
; --------------------------------------------------------------------------
RST18:
    JP do_RST18                       ; 0018  c3 ec 05
    DB 00h, C9h, 00h, 00h, 00h                                     ; 001B  .....

; --------------------------------------------------------------------------
; RST 20h: DCOMPR de la BIOS de MSX (compara HL con DE)
; --------------------------------------------------------------------------
RST20:
    JP do_RST20                       ; 0020  c3 24 02
    DB 00h, C9h, 00h, 00h, 00h, C9h, 00h, 00h, 11h, 81h, 00h, 00h, 00h, C9h, 00h, 00h; 0023  ................
    DB 00h, C9h, 00h, 00h, 00h                                     ; 0033  .....

; --------------------------------------------------------------------------
; RST 38h: interrupcion del Aleste (300 Hz); cada 5 llama a H.TIMI y explora
; el teclado: 60 Hz como un MSX
; --------------------------------------------------------------------------
RST38:
    JP do_RST38                       ; 0038  c3 2a 02
    DB C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h  ; 003B  ............
WRTVDP:
    JP do_WRTVDP                      ; 0047  c3 b4 03
RDVRM:
    JP do_RDVRM                       ; 004A  c3 5b 05
WRTVRM:
    JP do_WRTVRM                      ; 004D  c3 87 05
SETRD:
    JP do_SETRD                       ; 0050  c3 57 05
SETWRT:
    JP do_SETRD                       ; 0053  c3 57 05
FILVRM:
    JP do_FILVRM                      ; 0056  c3 03 06
LDIRMV:
    JP do_LDIRMV                      ; 0059  c3 d2 05
LDIRVM:
    JP do_LDIRVM                      ; 005C  c3 de 05
CHGMOD:
    JP do_CHGMOD                      ; 005F  c3 c2 04
CHGCLR:
    JP do_CHGCLR                      ; 0062  c3 24 05
    DB 00h, EDh, 45h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h; 0065  ..E.............
    DB C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h; 0075  ................
    DB 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h; 0085  ..............
WRTPSG:
    JP do_WRTPSG                      ; 0093  c3 2b 03
RDPSG:
    JP do_RDPSG                       ; 0096  c3 77 03
    DB C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h; 0099  ................
    DB 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h; 00A9  ................
    DB 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C3h, 2Ch, 05h, C9h, 00h, 00h; 00B9  ...........,....
    DB C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h; 00C9  ................
    DB 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h; 00D9  ................
    DB 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h; 00E9  ................
    DB C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h; 00F9  ................
    DB 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h; 0109  ................
    DB 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h; 0119  ................
    DB C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h; 0129  ...............
RSLREG:
    LD A,FCh                          ; 0138  3e fc
    RET                               ; 013A  c9
    DB C9h, 00h, 00h, C9h, 00h, 00h                                ; 013B  ......
SNSMAT:
    JP do_SNSMAT                      ; 0141  c3 f2 02
    DB C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h; 0144  ................
    DB 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h, 00h, C9h, 00h; 0154  ................
    DB 00h, C9h, 00h, 00h, C9h, 00h, 00h, C3h, 03h                 ; 0164  .........
B016D:
    LD B,C3h                          ; 016D  06 c3
    LD D,A                            ; 016F  57
B0170:
    DEC B                             ; 0170  05
    JP do_SETRD                       ; 0171  c3 57 05
    DB C3h, 5Bh, 05h                                               ; 0174  .[.
NRDVRM:
    JP do_WRTVRM                      ; 0177  c3 87 05
    DB CDh, A9h, 1Bh                                               ; 017A  ...
NWRVRM:
    LD HL,(3EC3h)                     ; 017D  2a c3 3e
    LD A,H                            ; 0180  7c
    CP F8h                            ; 0181  fe f8
    JP z,2F2Ch                        ; 0183  ca 2c 2f
    XOR A                             ; 0186  af
    CALL 1C46h                        ; 0187  cd 46 1c
    JP 2F1Ch                          ; 018A  c3 1c 2f
    DB 01h, 0Fh, 00h, CDh, A9h, 1Bh, 06h, 00h, CDh, 2Bh, 1Ch, 3Ah, 8Ch, 40h, B7h, CAh; 018D  .........+.:.@..
    DB 43h, 2Fh, 3Eh, 80h, CDh, 76h, 4Ch, CDh, DBh, 4Bh, CDh, 1Bh, 4Ch, C3h, 00h, 01h; 019D  C/>..vL..K..L...
    DB 4Eh, 6Fh, 00h, 20h, 46h, 61h, 74h, 61h, 6Ch, 20h, 65h, 72h, 72h, 6Fh, 72h, 28h; 01AD  No. Fatal error(
    DB 73h, 29h, 00h, 20h, 57h, 61h, 72h, 6Eh, 69h, 6Eh, 67h, 28h, 73h, 29h, 00h, 0Eh; 01BD  s). Warning(s)..
    DB 00h, 3Ah, D1h, 3Dh, 47h, CDh, A9h, 1Bh, C3h, 1Ah, 2Eh, CDh, CDh, 2Fh, 21h, 86h; 01CD  .:.=G......../!.
    DB 2Fh, CDh, D0h, 2Fh, CDh, 29h, 1Bh, C3h, B4h, 2Fh, 52h, 45h, 50h, 54h, 2Fh, 49h; 01DD  /../.).../REPT/I
    DB 52h, 50h, 2Fh, 49h, 52h, 50h, 43h, 2Fh, 4Dh, 41h, 43h, 52h, 4Fh, 00h, 55h, 6Eh; 01ED  RP/IRPC/MACRO.Un
    DB 74h, 65h, 72h                                               ; 01FD  ter

; --------------------------------------------------------------------------
; SERVICIOS DE LA GAMEBIOS (no estan en la BIOS de MSX): sustituyen las
; rutinas de los juegos que usan el motor de comandos del V9938. Vampire
; Killer y King's Valley 2 llaman a cada uno una vez.
; --------------------------------------------------------------------------
GB_0200:
    JP SVC_PALETTE                    ; 0200  c3 6a 06
    DB 00h                                                         ; 0203  .
GB_0204:
    JP SVC_LINE_A                     ; 0204  c3 d3 06
    DB 00h                                                         ; 0207  .
GB_0208:
    JP SVC_LINE_B                     ; 0208  c3 10 07
    DB 00h                                                         ; 020B  .
GB_020C:
    JP SVC_HMMV                       ; 020C  c3 40 07
    DB 00h                                                         ; 020F  .
GB_0210:
    JP SVC_HMMM                       ; 0210  c3 b4 07
    DB 00h                                                         ; 0213  .
GB_0214:
    JP SVC_HMMC                       ; 0214  c3 58 08
    DB 00h                                                         ; 0217  .
GB_0218:
    JP SVC_0218                       ; 0218  c3 76 08
    DB 00h                                                         ; 021B  .
GB_021C:
    JP SVC_TILE8                      ; 021C  c3 cd 07
    DB 00h                                                         ; 021F  .
GB_0220:
    JP SVC_0220                       ; 0220  c3 8f 08
    DB 00h                                                         ; 0223  .
do_RST20:
    LD A,H                            ; 0224  7c
    CP D                              ; 0225  ba
    RET nz                            ; 0226  c0
    LD A,L                            ; 0227  7d
    CP E                              ; 0228  bb
    RET                               ; 0229  c9

; --------------------------------------------------------------------------
; Interrupcion: divide 300 Hz entre 5, llama al gancho H.TIMI (FD9Fh) y
; explora el teclado
; --------------------------------------------------------------------------
do_RST38:
    PUSH AF                           ; 022A  f5
    LD A,(0260h)                      ; 022B  3a 60 02
    DEC A                             ; 022E  3d
    LD (0260h),A                      ; 022F  32 60 02
    JR nz,L023C                       ; 0232  20 08
    LD A,5                            ; 0234  3e 05
    LD (0260h),A                      ; 0236  32 60 02
    CALL L023F                        ; 0239  cd 3f 02
L023C:
    POP AF                            ; 023C  f1
    EI                                ; 023D  fb
    RET                               ; 023E  c9
L023F:
    PUSH HL                           ; 023F  e5
    PUSH DE                           ; 0240  d5
    PUSH BC                           ; 0241  c5
    EXX                               ; 0242  d9
    EX AF,AF'                         ; 0243  08
    PUSH HL                           ; 0244  e5
    PUSH DE                           ; 0245  d5
    PUSH BC                           ; 0246  c5
    PUSH AF                           ; 0247  f5
    PUSH IX                           ; 0248  dd e5
    PUSH IY                           ; 024A  fd e5
    CALL FD9Fh                        ; 024C  cd 9f fd
    CALL KBD_SCAN                     ; 024F  cd 7a 02
    POP IY                            ; 0252  fd e1
    POP IX                            ; 0254  dd e1
    POP AF                            ; 0256  f1
    POP BC                            ; 0257  c1
    POP DE                            ; 0258  d1
    POP HL                            ; 0259  e1
    EX AF,AF'                         ; 025A  08
    EXX                               ; 025B  d9
    POP BC                            ; 025C  c1
    POP DE                            ; 025D  d1
    POP HL                            ; 025E  e1
    RET                               ; 025F  c9
    DB 06h, 10h, FFh, FFh, FFh, FFh, FFh, FFh, FFh, FFh, FFh, FFh, FFh, FFh, 00h, 00h; 0260  ................
    DB 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h            ; 0270  ..........

; --------------------------------------------------------------------------
; Exploracion del teclado del Aleste (11 filas) traducida a la matriz del
; MSX (para SNSMAT)
; --------------------------------------------------------------------------
KBD_SCAN:
    DI                                ; 027A  f3
    LD HL,0262h                       ; 027B  21 62 02
    LD BC,F40Eh                       ; 027E  01 0e f4
    OUT (C),C                         ; 0281  ed 49
    LD B,F6h                          ; 0283  06 f6
    IN A,(C)                          ; 0285  ed 78
    AND 30h                           ; 0287  e6 30
    LD C,A                            ; 0289  4f
    OR C0h                            ; 028A  f6 c0
    OUT (C),A                         ; 028C  ed 79
    OUT (C),C                         ; 028E  ed 49
    INC B                             ; 0290  04
    LD A,92h                          ; 0291  3e 92
    OUT (C),A                         ; 0293  ed 79
    PUSH BC                           ; 0295  c5
    SET 6,C                           ; 0296  cb f1
L0298:
    LD B,F6h                          ; 0298  06 f6
    OUT (C),C                         ; 029A  ed 49
    LD B,F4h                          ; 029C  06 f4
    IN A,(C)                          ; 029E  ed 78
    LD (HL),A                         ; 02A0  77
    INC HL                            ; 02A1  23
    INC C                             ; 02A2  0c
    LD A,C                            ; 02A3  79
    AND 15                            ; 02A4  e6 0f
    CP 11                             ; 02A6  fe 0b
    JR nz,L0298                       ; 02A8  20 ee
    POP BC                            ; 02AA  c1
    LD A,82h                          ; 02AB  3e 82
    OUT (C),A                         ; 02AD  ed 79
    DEC B                             ; 02AF  05
    OUT (C),C                         ; 02B0  ed 49
    LD HL,026Eh                       ; 02B2  21 6e 02
    LD DE,026Fh                       ; 02B5  11 6f 02
    LD BC,10                          ; 02B8  01 0a 00
    LD (HL),0                         ; 02BB  36 00
    LDIR                              ; 02BD  ed b0
    LD HL,0262h                       ; 02BF  21 62 02
    LD C,0                            ; 02C2  0e 00
L02C4:
    LD B,8                            ; 02C4  06 08
L02C6:
    RLC (HL)                          ; 02C6  cb 06
    CALL nc,L02D5                     ; 02C8  d4 d5 02
    DJNZ L02C6                        ; 02CB  10 f9
    INC HL                            ; 02CD  23
    INC C                             ; 02CE  0c
    LD A,C                            ; 02CF  79
    CP 11                             ; 02D0  fe 0b
    JR nz,L02C4                       ; 02D2  20 f0
    RET                               ; 02D4  c9
L02D5:
    PUSH BC                           ; 02D5  c5
    DEC B                             ; 02D6  05
    LD A,C                            ; 02D7  79
    SLA A                             ; 02D8  cb 27
    SLA A                             ; 02DA  cb 27
    SLA A                             ; 02DC  cb 27
    OR B                              ; 02DE  b0
    ADD A,A                           ; 02DF  87
    EX DE,HL                          ; 02E0  eb
    LD L,A                            ; 02E1  6f
    LD H,2Fh                          ; 02E2  26 2f
    LD C,(HL)                         ; 02E4  4e
    INC HL                            ; 02E5  23
    LD A,(HL)                         ; 02E6  7e
    LD B,0                            ; 02E7  06 00
    LD HL,026Eh                       ; 02E9  21 6e 02
    ADD HL,BC                         ; 02EC  09
    OR (HL)                           ; 02ED  b6
    LD (HL),A                         ; 02EE  77
    EX DE,HL                          ; 02EF  eb
    POP BC                            ; 02F0  c1
    RET                               ; 02F1  c9

; --------------------------------------------------------------------------
; SNSMAT: devuelve la fila A de la matriz del MSX (activa a 0)
; --------------------------------------------------------------------------
do_SNSMAT:
    PUSH HL                           ; 02F2  e5
    PUSH BC                           ; 02F3  c5
    LD C,A                            ; 02F4  4f
    LD B,0                            ; 02F5  06 00
    LD HL,026Eh                       ; 02F7  21 6e 02
    ADD HL,BC                         ; 02FA  09
    LD A,(HL)                         ; 02FB  7e
    CPL                               ; 02FC  2f
    POP BC                            ; 02FD  c1
    POP HL                            ; 02FE  e1
    RET                               ; 02FF  c9

; --------------------------------------------------------------------------
; Cambio de banco: el byte tras el RST da el cuarto (AND 3); pagina = D8h +
; (A AND 7)
; --------------------------------------------------------------------------
do_RST08:
    EX (SP),HL                        ; 0300  e3
    PUSH BC                           ; 0301  c5
    LD B,(HL)                         ; 0302  46
    INC HL                            ; 0303  23
    PUSH AF                           ; 0304  f5
    AND 7                             ; 0305  e6 07
    ADD A,D8h                         ; 0307  c6 d8
    LD C,A                            ; 0309  4f
    LD A,B                            ; 030A  78
    AND 3                             ; 030B  e6 03
    OR 7Ch                            ; 030D  f6 7c
    LD B,A                            ; 030F  47
    OUT (C),C                         ; 0310  ed 49
    POP AF                            ; 0312  f1
    POP BC                            ; 0313  c1
    EX (SP),HL                        ; 0314  e3
    RET                               ; 0315  c9

; --------------------------------------------------------------------------
; Lectura del banco: IN del registro del mapper del cuarto dado, OR F8h
; --------------------------------------------------------------------------
do_RST00:
    EX (SP),HL                        ; 0316  e3
    PUSH BC                           ; 0317  c5
    LD B,(HL)                         ; 0318  46
    INC HL                            ; 0319  23
    PUSH AF                           ; 031A  f5
    LD A,B                            ; 031B  78
    AND 3                             ; 031C  e6 03
    OR 7Ch                            ; 031E  f6 7c
    LD B,A                            ; 0320  47
    IN A,(C)                          ; 0321  ed 78
    OR F8h                            ; 0323  f6 f8
    LD C,A                            ; 0325  4f
    POP AF                            ; 0326  f1
    LD A,C                            ; 0327  79
    POP BC                            ; 0328  c1
    EX (SP),HL                        ; 0329  e3
    RET                               ; 032A  c9

; --------------------------------------------------------------------------
; WRTPSG: al AY del Aleste por la PPI; R0-R5 (periodos) divididos entre 2
; (AY a 1 MHz frente a 1,79 MHz)
; --------------------------------------------------------------------------
do_WRTPSG:
    PUSH HL                           ; 032B  e5
    PUSH DE                           ; 032C  d5
    PUSH AF                           ; 032D  f5
    CP 6                              ; 032E  fe 06
    JR c,L0339                        ; 0330  38 07
    CALL L0353                        ; 0332  cd 53 03
    POP AF                            ; 0335  f1
    POP DE                            ; 0336  d1
    POP HL                            ; 0337  e1
    RET                               ; 0338  c9
L0339:
    LD L,A                            ; 0339  6f
    LD H,39h                          ; 033A  26 39
    LD (HL),E                         ; 033C  73
    AND 6                             ; 033D  e6 06
    LD L,A                            ; 033F  6f
    LD E,(HL)                         ; 0340  5e
    INC HL                            ; 0341  23
    LD D,(HL)                         ; 0342  56
    SRL D                             ; 0343  cb 3a
    RR E                              ; 0345  cb 1b
    CALL L0353                        ; 0347  cd 53 03
    LD E,D                            ; 034A  5a
    INC A                             ; 034B  3c
    CALL L0353                        ; 034C  cd 53 03
    POP AF                            ; 034F  f1
    POP DE                            ; 0350  d1
    POP HL                            ; 0351  e1
    RET                               ; 0352  c9
L0353:
    DI                                ; 0353  f3
    PUSH BC                           ; 0354  c5
    PUSH AF                           ; 0355  f5
    LD B,F4h                          ; 0356  06 f4
    OUT (C),A                         ; 0358  ed 79
    LD B,F6h                          ; 035A  06 f6
    IN A,(C)                          ; 035C  ed 78
    OR C0h                            ; 035E  f6 c0
    OUT (C),A                         ; 0360  ed 79
    AND 3Fh                           ; 0362  e6 3f
    OUT (C),A                         ; 0364  ed 79
    LD B,F4h                          ; 0366  06 f4
    OUT (C),E                         ; 0368  ed 59
    LD B,F6h                          ; 036A  06 f6
    LD C,A                            ; 036C  4f
    OR 80h                            ; 036D  f6 80
    OUT (C),A                         ; 036F  ed 79
    OUT (C),C                         ; 0371  ed 49
    POP AF                            ; 0373  f1
    POP BC                            ; 0374  c1
    EI                                ; 0375  fb
    RET                               ; 0376  c9

; --------------------------------------------------------------------------
; RDPSG: R0-R13 del AY; R14/R15 (joystick del MSX) devuelven FFh: sin
; joystick
; --------------------------------------------------------------------------
do_RDPSG:
    CP 6                              ; 0377  fe 06
    JR nc,L0382                       ; 0379  30 07
    PUSH HL                           ; 037B  e5
    LD L,A                            ; 037C  6f
    LD H,39h                          ; 037D  26 39
    LD A,(HL)                         ; 037F  7e
    POP HL                            ; 0380  e1
    RET                               ; 0381  c9
L0382:
    DI                                ; 0382  f3
    PUSH DE                           ; 0383  d5
    PUSH BC                           ; 0384  c5
    LD D,A                            ; 0385  57
    LD E,FFh                          ; 0386  1e ff
    CP 14                             ; 0388  fe 0e
    JR nc,L03AF                       ; 038A  30 23
    LD B,F4h                          ; 038C  06 f4
    OUT (C),D                         ; 038E  ed 51
    LD B,F6h                          ; 0390  06 f6
    IN A,(C)                          ; 0392  ed 78
    AND 30h                           ; 0394  e6 30
    LD C,A                            ; 0396  4f
    OR C0h                            ; 0397  f6 c0
    OUT (C),A                         ; 0399  ed 79
    OUT (C),C                         ; 039B  ed 49
    INC B                             ; 039D  04
    LD A,92h                          ; 039E  3e 92
    OUT (C),A                         ; 03A0  ed 79
    LD B,F4h                          ; 03A2  06 f4
    IN E,(C)                          ; 03A4  ed 58
    LD B,F7h                          ; 03A6  06 f7
    LD A,82h                          ; 03A8  3e 82
    OUT (C),A                         ; 03AA  ed 79
    DEC B                             ; 03AC  05
    OUT (C),C                         ; 03AD  ed 49
L03AF:
    LD A,E                            ; 03AF  7b
    POP BC                            ; 03B0  c1
    POP DE                            ; 03B1  d1
    EI                                ; 03B2  fb
    RET                               ; 03B3  c9

; --------------------------------------------------------------------------
; WRTVDP: reparte por registro con la tabla de 03D3h (24 entradas; 03D2h =
; ignorado)
; --------------------------------------------------------------------------
do_WRTVDP:
    PUSH HL                           ; 03B4  e5
    PUSH DE                           ; 03B5  d5
    PUSH BC                           ; 03B6  c5
    PUSH AF                           ; 03B7  f5
    LD HL,03CEh                       ; 03B8  21 ce 03
    PUSH HL                           ; 03BB  e5
    LD A,C                            ; 03BC  79
    CP 18h                            ; 03BD  fe 18
    RET nc                            ; 03BF  d0
    ADD A,A                           ; 03C0  87
    LD HL,03D3h                       ; 03C1  21 d3 03
    ADD A,L                           ; 03C4  85
    LD L,A                            ; 03C5  6f
    JR nc,L03C9                       ; 03C6  30 01
    INC H                             ; 03C8  24
L03C9:
    LD E,(HL)                         ; 03C9  5e
    INC HL                            ; 03CA  23
    LD D,(HL)                         ; 03CB  56
    EX DE,HL                          ; 03CC  eb
    JP (HL)                           ; 03CD  e9
WRTVDP_RET:
    POP AF                            ; 03CE  f1
    POP BC                            ; 03CF  c1
    POP DE                            ; 03D0  d1
    POP HL                            ; 03D1  e1
VDP_IGNORE:
    RET                               ; 03D2  c9
    DB D2h, 03h                                                    ; 03D3  ..
    DB 21h, 04h                                                    ; 03D5  !.
    DB D2h, 03h                                                    ; 03D7  ..
    DB D2h, 03h                                                    ; 03D9  ..
    DB D2h, 03h                                                    ; 03DB  ..
    DB 11h, 04h                                                    ; 03DD  ..
    DB 09h, 04h                                                    ; 03DF  ..
    DB A1h, 06h                                                    ; 03E1  ..
    DB 37h, 04h                                                    ; 03E3  7.
    DB D2h, 03h                                                    ; 03E5  ..
    DB D2h, 03h                                                    ; 03E7  ..
    DB D2h, 03h                                                    ; 03E9  ..
    DB D2h, 03h                                                    ; 03EB  ..
    DB D2h, 03h                                                    ; 03ED  ..
    DB 92h, 04h                                                    ; 03EF  ..
    DB D2h, 03h                                                    ; 03F1  ..
    DB 9Bh, 04h                                                    ; 03F3  ..
    DB D2h, 03h                                                    ; 03F5  ..
    DB D2h, 03h                                                    ; 03F7  ..
    DB D2h, 03h                                                    ; 03F9  ..
    DB D2h, 03h                                                    ; 03FB  ..
    DB D2h, 03h                                                    ; 03FD  ..
    DB D2h, 03h                                                    ; 03FF  ..
    DB A0h, 04h                                                    ; 0401  ..
    DB 00h, 00h, 00h, 00h, 00h, 00h                                ; 0403  ......

; --------------------------------------------------------------------------
; R6: base de los patrones de sprites
; --------------------------------------------------------------------------
VDP_R6:
    LD A,B                            ; 0409  78
    ADD A,A                           ; 040A  87
    ADD A,A                           ; 040B  87
    ADD A,A                           ; 040C  87
    LD (0404h),A                      ; 040D  32 04 04
    RET                               ; 0410  c9

; --------------------------------------------------------------------------
; R5: base de la tabla de atributos de sprites
; --------------------------------------------------------------------------
VDP_R5:
    LD A,B                            ; 0411  78
    RRCA                              ; 0412  0f
    AND 2Eh                           ; 0413  e6 2e
    LD H,A                            ; 0415  67
    LD L,0                            ; 0416  2e 00
    LD (0405h),HL                     ; 0418  22 05 04
    DEC H                             ; 041B  25
    DEC H                             ; 041C  25
    LD (0407h),HL                     ; 041D  22 07 04
    RET                               ; 0420  c9

; --------------------------------------------------------------------------
; R1: modo, pantalla, tamano de los sprites
; --------------------------------------------------------------------------
VDP_R1:
    LD A,B                            ; 0421  78
    RRCA                              ; 0422  0f
    RRCA                              ; 0423  0f
    RRCA                              ; 0424  0f
    AND 8                             ; 0425  e6 08
    LD C,A                            ; 0427  4f
    LD A,(FDF5h)                      ; 0428  3a f5 fd
    RES 3,A                           ; 042B  cb 9f
    OR C                              ; 042D  b1
    LD BC,FABFh                       ; 042E  01 bf fa
    OUT (C),A                         ; 0431  ed 79
    LD (FDF5h),A                      ; 0433  32 f5 fd
    RET                               ; 0436  c9

; --------------------------------------------------------------------------
; R8 (MSX2): modo (sprites, transparencia)
; --------------------------------------------------------------------------
VDP_R8:
    LD A,(06D2h)                      ; 0437  3a d2 06
    XOR B                             ; 043A  a8
    LD C,A                            ; 043B  4f
    LD A,B                            ; 043C  78
    LD (06D2h),A                      ; 043D  32 d2 06
    BIT 5,C                           ; 0440  cb 69
    PUSH BC                           ; 0442  c5
    CALL nz,L06A7                     ; 0443  c4 a7 06
    POP BC                            ; 0446  c1
    BIT 1,C                           ; 0447  cb 49
    RET z                             ; 0449  c8
    AND 2                             ; 044A  e6 02
    JR z,L0471                        ; 044C  28 23
    PUSH IX                           ; 044E  dd e5
    PUSH IY                           ; 0450  fd e5
    LD IX,E87Ch                       ; 0452  dd 21 7c e8
    LD IY,387Ch                       ; 0456  fd 21 7c 38
    LD BC,201Fh                       ; 045A  01 1f 20
L045D:
    PUSH BC                           ; 045D  c5
    CALL L0DB8                        ; 045E  cd b8 0d
    POP BC                            ; 0461  c1
    LD DE,FFFCh                       ; 0462  11 fc ff
    ADD IX,DE                         ; 0465  dd 19
    ADD IY,DE                         ; 0467  fd 19
    DEC C                             ; 0469  0d
    DJNZ L045D                        ; 046A  10 f1
    POP IY                            ; 046C  fd e1
    POP IX                            ; 046E  dd e1
    RET                               ; 0470  c9
L0471:
    PUSH IX                           ; 0471  dd e5
    PUSH IY                           ; 0473  fd e5
    LD IX,E87Ch                       ; 0475  dd 21 7c e8
    LD IY,387Ch                       ; 0479  fd 21 7c 38
    LD BC,201Fh                       ; 047D  01 1f 20
L0480:
    CALL L0C58                        ; 0480  cd 58 0c
    LD DE,FFFCh                       ; 0483  11 fc ff
    ADD IX,DE                         ; 0486  dd 19
    ADD IY,DE                         ; 0488  fd 19
    DEC C                             ; 048A  0d
    DJNZ L0480                        ; 048B  10 f3
    POP IY                            ; 048D  fd e1
    POP IX                            ; 048F  dd e1
    RET                               ; 0491  c9

; --------------------------------------------------------------------------
; R14 (MSX2): bits altos de la direccion de VRAM
; --------------------------------------------------------------------------
VDP_R14:
    LD A,B                            ; 0492  78
    AND 7                             ; 0493  e6 07
    OR D0h                            ; 0495  f6 d0
    LD (0665h),A                      ; 0497  32 65 06
    RET                               ; 049A  c9

; --------------------------------------------------------------------------
; R16 (MSX2): indice de la paleta
; --------------------------------------------------------------------------
VDP_R16:
    LD A,B                            ; 049B  78
    LD (0668h),A                      ; 049C  32 68 06
    RET                               ; 049F  c9

; --------------------------------------------------------------------------
; R23 (MSX2): desplazamiento vertical -> direccion de inicio del CRTC del
; Aleste (R12/R13): desplazamiento por hardware
; --------------------------------------------------------------------------
VDP_R23:
    LD A,B                            ; 04A0  78
    SRL A                             ; 04A1  cb 3f
    SRL A                             ; 04A3  cb 3f
    SRL A                             ; 04A5  cb 3f
    LD H,A                            ; 04A7  67
    LD L,0                            ; 04A8  2e 00
    SRL H                             ; 04AA  cb 3c
    RR L                              ; 04AC  cb 1d
    SRL H                             ; 04AE  cb 3c
    RR L                              ; 04B0  cb 1d
    LD BC,BC0Ch                       ; 04B2  01 0c bc
    OUT (C),C                         ; 04B5  ed 49
    INC B                             ; 04B7  04
    OUT (C),H                         ; 04B8  ed 61
    DEC B                             ; 04BA  05
    INC C                             ; 04BB  0c
    OUT (C),C                         ; 04BC  ed 49
    INC B                             ; 04BE  04
    OUT (C),L                         ; 04BF  ed 69
    RET                               ; 04C1  c9

; --------------------------------------------------------------------------
; CHGMOD: prepara un SCREEN 5 en el Aleste: FABF=7 (alta resolucion,
; paleta), CRTC (tabla 0547h), sprites, pantalla en la pagina 3Fh, paleta
; --------------------------------------------------------------------------
do_CHGMOD:
    DI                                ; 04C2  f3
    LD A,7                            ; 04C3  3e 07
    LD BC,FABFh                       ; 04C5  01 bf fa
    OUT (C),A                         ; 04C8  ed 79
    LD HL,0547h                       ; 04CA  21 47 05
    LD B,10h                          ; 04CD  06 10
    LD D,0                            ; 04CF  16 00
L04D1:
    LD E,(HL)                         ; 04D1  5e
    PUSH BC                           ; 04D2  c5
    LD B,BCh                          ; 04D3  06 bc
    OUT (C),D                         ; 04D5  ed 51
    INC B                             ; 04D7  04
    OUT (C),E                         ; 04D8  ed 59
    POP BC                            ; 04DA  c1
    INC HL                            ; 04DB  23
    INC D                             ; 04DC  14
    DJNZ L04D1                        ; 04DD  10 f2
    LD B,1Ch                          ; 04DF  06 1c
    CALL VDP_R6                       ; 04E1  cd 09 04
    LD B,F5h                          ; 04E4  06 f5
    CALL VDP_R5                       ; 04E6  cd 11 04
    CALL L052C                        ; 04E9  cd 2c 05
    LD BC,7FBFh                       ; 04EC  01 bf 7f
    OUT (C),C                         ; 04EF  ed 49
    LD B,2                            ; 04F1  06 02
    CALL VDP_R8                       ; 04F3  cd 37 04
    LD B,0                            ; 04F6  06 00
    CALL VDP_R7                       ; 04F8  cd a1 06
    LD A,0                            ; 04FB  3e 00
    LD B,10h                          ; 04FD  06 10
L04FF:
    PUSH AF                           ; 04FF  f5
    PUSH BC                           ; 0500  c5
    LD DE,0                           ; 0501  11 00 00
    CALL SVC_PALETTE                  ; 0504  cd 6a 06
    POP BC                            ; 0507  c1
    POP AF                            ; 0508  f1
    INC A                             ; 0509  3c
    DJNZ L04FF                        ; 050A  10 f3
    LD HL,E800h                       ; 050C  21 00 e8
    LD DE,E801h                       ; 050F  11 01 e8
    LD BC,7Fh                         ; 0512  01 7f 00
    LD (HL),E0h                       ; 0515  36 e0
    LDIR                              ; 0517  ed b0
    LD A,15                           ; 0519  3e 0f
    LD BC,FABFh                       ; 051B  01 bf fa
    OUT (C),A                         ; 051E  ed 79
    LD (FDF5h),A                      ; 0520  32 f5 fd
    EI                                ; 0523  fb

; --------------------------------------------------------------------------
; CHGCLR: colores de primer plano, fondo y borde
; --------------------------------------------------------------------------
do_CHGCLR:
    LD A,(F3EBh)                      ; 0524  3a eb f3
    LD B,A                            ; 0527  47
    CALL VDP_R7                       ; 0528  cd a1 06
    RET                               ; 052B  c9
L052C:
    DI                                ; 052C  f3
    CALL L060F                        ; 052D  cd 0f 06
    LD A,(F3EAh)                      ; 0530  3a ea f3
    LD C,A                            ; 0533  4f
    LD B,3Fh                          ; 0534  06 3f
    LD A,(BC)                         ; 0536  0a
    LD HL,4000h                       ; 0537  21 00 40
    LD DE,4001h                       ; 053A  11 01 40
    LD BC,7FFFh                       ; 053D  01 ff 7f
    LD (HL),A                         ; 0540  77
    LDIR                              ; 0541  ed b0
    CALL VRAM_UNMAP                   ; 0543  cd 26 06
    RET                               ; 0546  c9
    DB 6Bh, 40h, 4Ah, 8Eh, 26h, 00h, 1Bh, 20h, 00h, 07h, 00h, 00h, 00h, 00h, 00h, 00h; 0547  k@J.&.. ........

; --------------------------------------------------------------------------
; SETRD / SETWRT: guarda la direccion de VRAM
; --------------------------------------------------------------------------
do_SETRD:
    LD (0666h),HL                     ; 0557  22 66 06
    RET                               ; 055A  c9

; --------------------------------------------------------------------------
; RDVRM: lee de la copia de la VRAM (paginas D0h-D3h)
; --------------------------------------------------------------------------
do_RDVRM:
    DI                                ; 055B  f3
    PUSH HL                           ; 055C  e5
    PUSH BC                           ; 055D  c5
    LD A,H                            ; 055E  7c
    CP F8h                            ; 055F  fe f8
    JR c,L056D                        ; 0561  38 0a
    AND 7                             ; 0563  e6 07
    ADD A,30h                         ; 0565  c6 30
    LD H,A                            ; 0567  67
    LD A,(HL)                         ; 0568  7e
    POP BC                            ; 0569  c1
    POP HL                            ; 056A  e1
    EI                                ; 056B  fb
    RET                               ; 056C  c9
L056D:
    RLCA                              ; 056D  07
    RLCA                              ; 056E  07
    AND 3                             ; 056F  e6 03
    OR D0h                            ; 0571  f6 d0
    LD B,7Dh                          ; 0573  06 7d
    IN C,(C)                          ; 0575  ed 48
    OUT (C),A                         ; 0577  ed 79
    SET 6,H                           ; 0579  cb f4
    RES 7,H                           ; 057B  cb bc
    LD L,(HL)                         ; 057D  6e
    LD H,3Dh                          ; 057E  26 3d
    LD A,(HL)                         ; 0580  7e
    OUT (C),C                         ; 0581  ed 49
    POP BC                            ; 0583  c1
    POP HL                            ; 0584  e1
    EI                                ; 0585  fb
    RET                               ; 0586  c9

; --------------------------------------------------------------------------
; WRTVRM: guarda el byte (traducido con la tabla de 3F00h: orden de los bits
; de cada pixel del MSX al del Aleste) en la copia de la VRAM (paginas
; D0h-D3h) y, si la direccion es < 8000h, tambien en la pantalla del Aleste
; (direccion de la linea en la tabla de 3E00h): SCREEN 5 = mapa de bits de
; 256 pixeles y 16 colores. F800h en adelante (atributos de sprites) va a
; 3000h
; --------------------------------------------------------------------------
do_WRTVRM:
    DI                                ; 0587  f3
    PUSH AF                           ; 0588  f5
    PUSH HL                           ; 0589  e5
    PUSH DE                           ; 058A  d5
    PUSH BC                           ; 058B  c5
    LD E,A                            ; 058C  5f
    LD A,H                            ; 058D  7c
    CP F8h                            ; 058E  fe f8
    JR c,L059A                        ; 0590  38 08
    AND 7                             ; 0592  e6 07
    ADD A,30h                         ; 0594  c6 30
    LD H,A                            ; 0596  67
    LD (HL),E                         ; 0597  73
    JR L05CC                          ; 0598  18 32
L059A:
    PUSH HL                           ; 059A  e5
    RLCA                              ; 059B  07
    RLCA                              ; 059C  07
    AND 3                             ; 059D  e6 03
    OR D0h                            ; 059F  f6 d0
    LD B,7Dh                          ; 05A1  06 7d
    IN C,(C)                          ; 05A3  ed 48
    OUT (C),A                         ; 05A5  ed 79
    SET 6,H                           ; 05A7  cb f4
    RES 7,H                           ; 05A9  cb bc
    LD D,3Fh                          ; 05AB  16 3f
    LD A,(DE)                         ; 05AD  1a
    LD (HL),A                         ; 05AE  77
    OUT (C),C                         ; 05AF  ed 49
    LD E,A                            ; 05B1  5f
    POP HL                            ; 05B2  e1
    LD A,H                            ; 05B3  7c
    CP 80h                            ; 05B4  fe 80
    JP nc,L05CC                       ; 05B6  d2 cc 05
    CALL L060F                        ; 05B9  cd 0f 06
    ADD HL,HL                         ; 05BC  29
    LD C,H                            ; 05BD  4c
    LD B,3Eh                          ; 05BE  06 3e
    LD A,(BC)                         ; 05C0  0a
    SRL A                             ; 05C1  cb 3f
    RR L                              ; 05C3  cb 1d
    ADD A,40h                         ; 05C5  c6 40
    LD H,A                            ; 05C7  67
    LD (HL),E                         ; 05C8  73
    CALL VRAM_UNMAP                   ; 05C9  cd 26 06
L05CC:
    POP BC                            ; 05CC  c1
    POP DE                            ; 05CD  d1
    POP HL                            ; 05CE  e1
    POP AF                            ; 05CF  f1
    EI                                ; 05D0  fb
    RET                               ; 05D1  c9

; --------------------------------------------------------------------------
; LDIRMV: de la VRAM a la RAM (bucle sobre RDVRM)
; --------------------------------------------------------------------------
do_LDIRMV:
    CALL do_RDVRM                     ; 05D2  cd 5b 05
    LD (DE),A                         ; 05D5  12
    INC HL                            ; 05D6  23
    INC DE                            ; 05D7  13
    DEC BC                            ; 05D8  0b
    LD A,B                            ; 05D9  78
    OR C                              ; 05DA  b1
    JR nz,do_LDIRMV                   ; 05DB  20 f5
    RET                               ; 05DD  c9

; --------------------------------------------------------------------------
; LDIRVM: de la RAM a la VRAM (bucle sobre WRTVRM)
; --------------------------------------------------------------------------
do_LDIRVM:
    EX DE,HL                          ; 05DE  eb
L05DF:
    LD A,(DE)                         ; 05DF  1a
    CALL do_WRTVRM                    ; 05E0  cd 87 05
    INC HL                            ; 05E3  23
    INC DE                            ; 05E4  13
    DEC BC                            ; 05E5  0b
    LD A,B                            ; 05E6  78
    OR C                              ; 05E7  b1
    JR nz,L05DF                       ; 05E8  20 f5
    EX DE,HL                          ; 05EA  eb
    RET                               ; 05EB  c9

; --------------------------------------------------------------------------
; OUT al VDP: WRTVRM en la direccion actual y la avanza
; --------------------------------------------------------------------------
do_RST18:
    PUSH HL                           ; 05EC  e5
    LD HL,(0666h)                     ; 05ED  2a 66 06
    CALL do_WRTVRM                    ; 05F0  cd 87 05
    INC HL                            ; 05F3  23
    LD (0666h),HL                     ; 05F4  22 66 06
    POP HL                            ; 05F7  e1
    RET                               ; 05F8  c9

; --------------------------------------------------------------------------
; OTIR al VDP: bucle de OUT
; --------------------------------------------------------------------------
do_RST10:
    PUSH AF                           ; 05F9  f5
L05FA:
    LD A,(HL)                         ; 05FA  7e
    CALL do_RST18                     ; 05FB  cd ec 05
    INC HL                            ; 05FE  23
    DJNZ L05FA                        ; 05FF  10 f9
    POP AF                            ; 0601  f1
    RET                               ; 0602  c9

; --------------------------------------------------------------------------
; FILVRM: rellena la VRAM (bucle sobre WRTVRM)
; --------------------------------------------------------------------------
do_FILVRM:
    LD D,A                            ; 0603  57
L0604:
    LD A,D                            ; 0604  7a
    CALL do_WRTVRM                    ; 0605  cd 87 05
    INC HL                            ; 0608  23
    DEC BC                            ; 0609  0b
    LD A,B                            ; 060A  78
    OR C                              ; 060B  b1
    JR nz,L0604                       ; 060C  20 f6
    RET                               ; 060E  c9
L060F:
    PUSH BC                           ; 060F  c5
    PUSH HL                           ; 0610  e5
    LD B,7Dh                          ; 0611  06 7d
    IN L,(C)                          ; 0613  ed 68
    INC B                             ; 0615  04
    IN H,(C)                          ; 0616  ed 60
    LD (0663h),HL                     ; 0618  22 63 06
    LD C,C1h                          ; 061B  0e c1
    OUT (C),C                         ; 061D  ed 49
    DEC B                             ; 061F  05
    DEC C                             ; 0620  0d
    OUT (C),C                         ; 0621  ed 49
    POP HL                            ; 0623  e1
    POP BC                            ; 0624  c1
    RET                               ; 0625  c9

; --------------------------------------------------------------------------
; Restaura la pagina de la ventana
; --------------------------------------------------------------------------
VRAM_UNMAP:
    PUSH BC                           ; 0626  c5
    PUSH HL                           ; 0627  e5
    LD B,7Dh                          ; 0628  06 7d
    LD HL,(0663h)                     ; 062A  2a 63 06
    OUT (C),L                         ; 062D  ed 69
    INC B                             ; 062F  04
    OUT (C),H                         ; 0630  ed 61
    POP HL                            ; 0632  e1
    POP BC                            ; 0633  c1
    RET                               ; 0634  c9
L0635:
    PUSH BC                           ; 0635  c5
    PUSH HL                           ; 0636  e5
    LD B,7Dh                          ; 0637  06 7d
    IN L,(C)                          ; 0639  ed 68
    INC B                             ; 063B  04
    IN H,(C)                          ; 063C  ed 60
    LD (0663h),HL                     ; 063E  22 63 06
    LD C,D1h                          ; 0641  0e d1
    OUT (C),C                         ; 0643  ed 49
    DEC B                             ; 0645  05
    DEC C                             ; 0646  0d
    OUT (C),C                         ; 0647  ed 49
    POP HL                            ; 0649  e1
    POP BC                            ; 064A  c1
    RET                               ; 064B  c9

; --------------------------------------------------------------------------
; Pone la pagina de la pantalla del Aleste en la ventana de 4000h
; --------------------------------------------------------------------------
VRAM_MAP:
    PUSH BC                           ; 064C  c5
    PUSH HL                           ; 064D  e5
    LD B,7Dh                          ; 064E  06 7d
    IN L,(C)                          ; 0650  ed 68
    INC B                             ; 0652  04
    IN H,(C)                          ; 0653  ed 60
    LD (0663h),HL                     ; 0655  22 63 06
    LD C,D3h                          ; 0658  0e d3
    OUT (C),C                         ; 065A  ed 49
    DEC B                             ; 065C  05
    DEC C                             ; 065D  0d
    OUT (C),C                         ; 065E  ed 49
    POP HL                            ; 0660  e1
    POP BC                            ; 0661  c1
    RET                               ; 0662  c9
    DB 00h, 00h, 00h, 00h, 00h, 00h, 00h                           ; 0663  .......

; --------------------------------------------------------------------------
; Servicio 0200h: escribe la paleta (registro 16 del V9938)
; --------------------------------------------------------------------------
SVC_PALETTE:
    PUSH HL                           ; 066A  e5
    PUSH BC                           ; 066B  c5
    LD B,7Fh                          ; 066C  06 7f
    AND 15                            ; 066E  e6 0f
    LD C,A                            ; 0670  4f
    OUT (C),A                         ; 0671  ed 79
    LD A,D                            ; 0673  7a
    RRCA                              ; 0674  0f
    AND 33h                           ; 0675  e6 33
    LD B,A                            ; 0677  47
    LD A,E                            ; 0678  7b
    RLCA                              ; 0679  07
    AND 12                            ; 067A  e6 0c
    OR B                              ; 067C  b0
    OR 40h                            ; 067D  f6 40
    LD B,7Fh                          ; 067F  06 7f
    OUT (C),A                         ; 0681  ed 79
    LD B,A                            ; 0683  47
    LD A,C                            ; 0684  79
    LD HL,3880h                       ; 0685  21 80 38
    ADD A,L                           ; 0688  85
    LD L,A                            ; 0689  6f
    LD (HL),B                         ; 068A  70
    LD HL,F680h                       ; 068B  21 80 f6
    LD A,C                            ; 068E  79
    ADD A,A                           ; 068F  87
    ADD A,L                           ; 0690  85
    LD L,A                            ; 0691  6f
    LD A,D                            ; 0692  7a
    CALL do_WRTVRM                    ; 0693  cd 87 05
    INC HL                            ; 0696  23
    LD A,E                            ; 0697  7b
    CALL do_WRTVRM                    ; 0698  cd 87 05
    CALL L06A7                        ; 069B  cd a7 06
    POP BC                            ; 069E  c1
    POP HL                            ; 069F  e1
    RET                               ; 06A0  c9

; --------------------------------------------------------------------------
; R7: color del borde
; --------------------------------------------------------------------------
VDP_R7:
    LD A,B                            ; 06A1  78
    AND 15                            ; 06A2  e6 0f
    LD (06D1h),A                      ; 06A4  32 d1 06
L06A7:
    LD A,(06D1h)                      ; 06A7  3a d1 06
    LD HL,3880h                       ; 06AA  21 80 38
    ADD A,L                           ; 06AD  85
    LD L,A                            ; 06AE  6f
    LD C,(HL)                         ; 06AF  4e
    LD B,7Fh                          ; 06B0  06 7f
    LD A,10h                          ; 06B2  3e 10
    OUT (C),A                         ; 06B4  ed 79
    RES 7,C                           ; 06B6  cb b9
    SET 6,C                           ; 06B8  cb f1
    OUT (C),C                         ; 06BA  ed 49
    LD A,(06D2h)                      ; 06BC  3a d2 06
    BIT 5,A                           ; 06BF  cb 6f
    JR z,L06C7                        ; 06C1  28 04
    LD A,(3880h)                      ; 06C3  3a 80 38
    LD C,A                            ; 06C6  4f
L06C7:
    SUB A                             ; 06C7  97
    OUT (C),A                         ; 06C8  ed 79
    RES 7,C                           ; 06CA  cb b9
    SET 6,C                           ; 06CC  cb f1
    OUT (C),C                         ; 06CE  ed 49
    RET                               ; 06D0  c9
    DB 00h, 00h                                                    ; 06D1  ..

; --------------------------------------------------------------------------
; Servicio 0204h: LINE (comando 70h del V9938), una variante
; --------------------------------------------------------------------------
SVC_LINE_A:
    LD A,C                            ; 06D3  79
    AND 15                            ; 06D4  e6 0f
    LD C,A                            ; 06D6  4f
    LD D,F0h                          ; 06D7  16 f0
    LD A,L                            ; 06D9  7d
    LD L,H                            ; 06DA  6c
    LD H,A                            ; 06DB  67
    SRL H                             ; 06DC  cb 3c
    RR L                              ; 06DE  cb 1d
    JR c,L06F2                        ; 06E0  38 10
    RLC C                             ; 06E2  cb 01
    RLC C                             ; 06E4  cb 01
    RLC C                             ; 06E6  cb 01
    RLC C                             ; 06E8  cb 01
    RLC D                             ; 06EA  cb 02
    RLC D                             ; 06EC  cb 02
    RLC D                             ; 06EE  cb 02
    RLC D                             ; 06F0  cb 02
L06F2:
    CALL do_RDVRM                     ; 06F2  cd 5b 05
    AND D                             ; 06F5  a2
    OR C                              ; 06F6  b1
    CALL do_WRTVRM                    ; 06F7  cd 87 05
    RLC C                             ; 06FA  cb 01
    RLC C                             ; 06FC  cb 01
    RLC C                             ; 06FE  cb 01
    RLC C                             ; 0700  cb 01
    RLC D                             ; 0702  cb 02
    RLC D                             ; 0704  cb 02
    RLC D                             ; 0706  cb 02
    RLC D                             ; 0708  cb 02
    JR nc,L070D                       ; 070A  30 01
    INC HL                            ; 070C  23
L070D:
    DJNZ L06F2                        ; 070D  10 e3
    RET                               ; 070F  c9

; --------------------------------------------------------------------------
; Servicio 0208h: LINE, otra variante
; --------------------------------------------------------------------------
SVC_LINE_B:
    LD A,C                            ; 0710  79
    AND 15                            ; 0711  e6 0f
    LD C,A                            ; 0713  4f
    LD D,F0h                          ; 0714  16 f0
    LD A,L                            ; 0716  7d
    LD L,H                            ; 0717  6c
    LD H,A                            ; 0718  67
    SRL H                             ; 0719  cb 3c
    RR L                              ; 071B  cb 1d
    JR c,L072F                        ; 071D  38 10
    RLC C                             ; 071F  cb 01
    RLC C                             ; 0721  cb 01
    RLC C                             ; 0723  cb 01
    RLC C                             ; 0725  cb 01
    RLC D                             ; 0727  cb 02
    RLC D                             ; 0729  cb 02
    RLC D                             ; 072B  cb 02
    RLC D                             ; 072D  cb 02
L072F:
    CALL do_RDVRM                     ; 072F  cd 5b 05
    AND D                             ; 0732  a2
    OR C                              ; 0733  b1
    CALL do_WRTVRM                    ; 0734  cd 87 05
    LD A,D                            ; 0737  7a
    LD DE,80h                         ; 0738  11 80 00
    ADD HL,DE                         ; 073B  19
    LD D,A                            ; 073C  57
    DJNZ L072F                        ; 073D  10 f0
    RET                               ; 073F  c9

; --------------------------------------------------------------------------
; Servicio 020Ch: HMMV, rellena un rectangulo
; --------------------------------------------------------------------------
SVC_HMMV:
    PUSH DE                           ; 0740  d5
    LD E,A                            ; 0741  5f
    LD A,H                            ; 0742  7c
    LD H,L                            ; 0743  65
    LD L,A                            ; 0744  6f
    LD D,3Fh                          ; 0745  16 3f
    LD A,(DE)                         ; 0747  1a
    RES 0,B                           ; 0748  cb 80
    POP DE                            ; 074A  d1
    BIT 0,D                           ; 074B  cb 42
    JP nz,L0795                       ; 074D  c2 95 07
    PUSH HL                           ; 0750  e5
    PUSH BC                           ; 0751  c5
    LD E,A                            ; 0752  5f
L0753:
    PUSH HL                           ; 0753  e5
    PUSH BC                           ; 0754  c5
    LD A,H                            ; 0755  7c
    SRL A                             ; 0756  cb 3f
    RR L                              ; 0758  cb 1d
    ADD A,40h                         ; 075A  c6 40
    LD H,A                            ; 075C  67
    DI                                ; 075D  f3
    CALL L0635                        ; 075E  cd 35 06
L0761:
    LD (HL),E                         ; 0761  73
    INC HL                            ; 0762  23
    DEC B                             ; 0763  05
    DJNZ L0761                        ; 0764  10 fb
    CALL VRAM_UNMAP                   ; 0766  cd 26 06
    EI                                ; 0769  fb
    POP BC                            ; 076A  c1
    POP HL                            ; 076B  e1
    INC H                             ; 076C  24
    DEC C                             ; 076D  0d
    JR nz,L0753                       ; 076E  20 e3
    POP BC                            ; 0770  c1
    POP HL                            ; 0771  e1
L0772:
    PUSH HL                           ; 0772  e5
    PUSH BC                           ; 0773  c5
    LD D,B                            ; 0774  50
    LD C,H                            ; 0775  4c
    LD B,3Eh                          ; 0776  06 3e
    LD A,(BC)                         ; 0778  0a
    LD B,D                            ; 0779  42
    SRL A                             ; 077A  cb 3f
    RR L                              ; 077C  cb 1d
    ADD A,40h                         ; 077E  c6 40
    LD H,A                            ; 0780  67
    DI                                ; 0781  f3
    CALL L060F                        ; 0782  cd 0f 06
L0785:
    LD (HL),E                         ; 0785  73
    INC HL                            ; 0786  23
    DEC B                             ; 0787  05
    DJNZ L0785                        ; 0788  10 fb
    CALL VRAM_UNMAP                   ; 078A  cd 26 06
    EI                                ; 078D  fb
    POP BC                            ; 078E  c1
    POP HL                            ; 078F  e1
    INC H                             ; 0790  24
    DEC C                             ; 0791  0d
    JR nz,L0772                       ; 0792  20 de
    RET                               ; 0794  c9
L0795:
    LD E,A                            ; 0795  5f
L0796:
    PUSH BC                           ; 0796  c5
    PUSH HL                           ; 0797  e5
    LD A,H                            ; 0798  7c
    SRL A                             ; 0799  cb 3f
    RR L                              ; 079B  cb 1d
    ADD A,40h                         ; 079D  c6 40
    LD H,A                            ; 079F  67
    DI                                ; 07A0  f3
    CALL VRAM_MAP                     ; 07A1  cd 4c 06
L07A4:
    LD (HL),E                         ; 07A4  73
    INC HL                            ; 07A5  23
    DEC B                             ; 07A6  05
    DJNZ L07A4                        ; 07A7  10 fb
    CALL VRAM_UNMAP                   ; 07A9  cd 26 06
    EI                                ; 07AC  fb
    POP HL                            ; 07AD  e1
    POP BC                            ; 07AE  c1
    INC H                             ; 07AF  24
    DEC C                             ; 07B0  0d
    JR nz,L0796                       ; 07B1  20 e3
    RET                               ; 07B3  c9

; --------------------------------------------------------------------------
; Servicio 0210h: HMMM, copia un rectangulo de VRAM a VRAM
; --------------------------------------------------------------------------
SVC_HMMM:
    EX AF,AF'                         ; 07B4  08
    LD A,H                            ; 07B5  7c
    LD H,L                            ; 07B6  65
    LD L,A                            ; 07B7  6f
    LD A,D                            ; 07B8  7a
    LD D,E                            ; 07B9  53
    LD E,A                            ; 07BA  5f
    EX AF,AF'                         ; 07BB  08
L07BC:
    PUSH BC                           ; 07BC  c5
    PUSH HL                           ; 07BD  e5
    PUSH DE                           ; 07BE  d5
    PUSH AF                           ; 07BF  f5
    CALL L09C3                        ; 07C0  cd c3 09
    POP AF                            ; 07C3  f1
    POP DE                            ; 07C4  d1
    POP HL                            ; 07C5  e1
    POP BC                            ; 07C6  c1
    INC H                             ; 07C7  24
    INC D                             ; 07C8  14
    DEC C                             ; 07C9  0d
    JR nz,L07BC                       ; 07CA  20 f0
    RET                               ; 07CC  c9

; --------------------------------------------------------------------------
; Servicio 021Ch: dibuja un bloque de 8x8 (con HMMM)
; --------------------------------------------------------------------------
SVC_TILE8:
    PUSH HL                           ; 07CD  e5
    PUSH DE                           ; 07CE  d5
    PUSH BC                           ; 07CF  c5
    LD C,E                            ; 07D0  4b
    LD E,D                            ; 07D1  5a
    LD D,C                            ; 07D2  51
    PUSH DE                           ; 07D3  d5
    LD B,A                            ; 07D4  47
    AND 1Fh                           ; 07D5  e6 1f
    ADD A,A                           ; 07D7  87
    ADD A,A                           ; 07D8  87
    LD L,A                            ; 07D9  6f
    LD A,B                            ; 07DA  78
    AND E0h                           ; 07DB  e6 e0
    SRL A                             ; 07DD  cb 3f
    SRL A                             ; 07DF  cb 3f
    SRL A                             ; 07E1  cb 3f
    ADD A,40h                         ; 07E3  c6 40
    LD H,A                            ; 07E5  67
    DI                                ; 07E6  f3
    CALL VRAM_MAP                     ; 07E7  cd 4c 06
    LD DE,3C00h                       ; 07EA  11 00 3c
    LD A,8                            ; 07ED  3e 08
L07EF:
    LDI                               ; 07EF  ed a0
    LDI                               ; 07F1  ed a0
    LDI                               ; 07F3  ed a0
    LDI                               ; 07F5  ed a0
    LD BC,7Ch                         ; 07F7  01 7c 00
    ADD HL,BC                         ; 07FA  09
    DEC A                             ; 07FB  3d
    JR nz,L07EF                       ; 07FC  20 f1
    LD BC,7DD0h                       ; 07FE  01 d0 7d
    OUT (C),C                         ; 0801  ed 49
    INC B                             ; 0803  04
    INC C                             ; 0804  0c
    OUT (C),C                         ; 0805  ed 49
    POP DE                            ; 0807  d1
    PUSH DE                           ; 0808  d5
    LD A,D                            ; 0809  7a
    SRL A                             ; 080A  cb 3f
    RR E                              ; 080C  cb 1b
    ADD A,40h                         ; 080E  c6 40
    LD D,A                            ; 0810  57
    LD HL,3C00h                       ; 0811  21 00 3c
    LD A,8                            ; 0814  3e 08
L0816:
    LDI                               ; 0816  ed a0
    LDI                               ; 0818  ed a0
    LDI                               ; 081A  ed a0
    LDI                               ; 081C  ed a0
    LD BC,7Ch                         ; 081E  01 7c 00
    EX DE,HL                          ; 0821  eb
    ADD HL,BC                         ; 0822  09
    EX DE,HL                          ; 0823  eb
    DEC A                             ; 0824  3d
    JR nz,L0816                       ; 0825  20 ef
    LD BC,7DC0h                       ; 0827  01 c0 7d
    OUT (C),C                         ; 082A  ed 49
    INC B                             ; 082C  04
    INC C                             ; 082D  0c
    OUT (C),C                         ; 082E  ed 49
    POP DE                            ; 0830  d1
    LD HL,3C00h                       ; 0831  21 00 3c
    LD B,8                            ; 0834  06 08
    LD C,D                            ; 0836  4a
L0837:
    PUSH BC                           ; 0837  c5
    PUSH DE                           ; 0838  d5
    LD B,3Eh                          ; 0839  06 3e
    LD A,(BC)                         ; 083B  0a
    SRL A                             ; 083C  cb 3f
    RR E                              ; 083E  cb 1b
    ADD A,40h                         ; 0840  c6 40
    LD D,A                            ; 0842  57
    LDI                               ; 0843  ed a0
    LDI                               ; 0845  ed a0
    LDI                               ; 0847  ed a0
    LDI                               ; 0849  ed a0
    POP DE                            ; 084B  d1
    POP BC                            ; 084C  c1
    INC C                             ; 084D  0c
    DJNZ L0837                        ; 084E  10 e7
    CALL VRAM_UNMAP                   ; 0850  cd 26 06
    EI                                ; 0853  fb
    POP BC                            ; 0854  c1
    POP DE                            ; 0855  d1
    POP HL                            ; 0856  e1
    RET                               ; 0857  c9

; --------------------------------------------------------------------------
; Servicio 0214h: HMMC, copia un rectangulo de la CPU a la VRAM
; --------------------------------------------------------------------------
SVC_HMMC:
    SRL B                             ; 0858  cb 38
    RRCA                              ; 085A  0f
    RR E                              ; 085B  cb 1b
    RR D                              ; 085D  cb 1a
    LD A,D                            ; 085F  7a
    LD D,E                            ; 0860  53
    LD E,A                            ; 0861  5f
    EX DE,HL                          ; 0862  eb
L0863:
    PUSH BC                           ; 0863  c5
    PUSH HL                           ; 0864  e5
L0865:
    LD A,(DE)                         ; 0865  1a
    CALL do_WRTVRM                    ; 0866  cd 87 05
    INC HL                            ; 0869  23
    INC DE                            ; 086A  13
    DJNZ L0865                        ; 086B  10 f8
    POP HL                            ; 086D  e1
    LD C,80h                          ; 086E  0e 80
    ADD HL,BC                         ; 0870  09
    POP BC                            ; 0871  c1
    DEC C                             ; 0872  0d
    JR nz,L0863                       ; 0873  20 ee
    RET                               ; 0875  c9

; --------------------------------------------------------------------------
; Servicio 0218h: por identificar (usa los registros desde R#32)
; --------------------------------------------------------------------------
SVC_0218:
    EX AF,AF'                         ; 0876  08
    LD A,H                            ; 0877  7c
    LD H,L                            ; 0878  65
    LD L,A                            ; 0879  6f
    LD A,D                            ; 087A  7a
    LD D,E                            ; 087B  53
    LD E,A                            ; 087C  5f
    EX AF,AF'                         ; 087D  08
L087E:
    PUSH BC                           ; 087E  c5
    PUSH HL                           ; 087F  e5
    PUSH DE                           ; 0880  d5
    PUSH AF                           ; 0881  f5
    CALL L0A28                        ; 0882  cd 28 0a
    POP AF                            ; 0885  f1
    POP DE                            ; 0886  d1
    POP HL                            ; 0887  e1
    POP BC                            ; 0888  c1
    INC H                             ; 0889  24
    INC D                             ; 088A  14
    DEC C                             ; 088B  0d
    JR nz,L087E                       ; 088C  20 f0
    RET                               ; 088E  c9

; --------------------------------------------------------------------------
; Servicio 0220h: por identificar (Vampire Killer lo llama desde otras
; paginas)
; --------------------------------------------------------------------------
SVC_0220:
    PUSH HL                           ; 088F  e5
    PUSH DE                           ; 0890  d5
    PUSH BC                           ; 0891  c5
    LD C,E                            ; 0892  4b
    LD E,D                            ; 0893  5a
    LD D,C                            ; 0894  51
    PUSH DE                           ; 0895  d5
    LD B,A                            ; 0896  47
    AND 1Fh                           ; 0897  e6 1f
    ADD A,A                           ; 0899  87
    ADD A,A                           ; 089A  87
    LD L,A                            ; 089B  6f
    LD A,B                            ; 089C  78
    AND E0h                           ; 089D  e6 e0
    SRL A                             ; 089F  cb 3f
    SRL A                             ; 08A1  cb 3f
    SRL A                             ; 08A3  cb 3f
    ADD A,40h                         ; 08A5  c6 40
    LD H,A                            ; 08A7  67
    DI                                ; 08A8  f3
    CALL VRAM_MAP                     ; 08A9  cd 4c 06
    LD DE,3C00h                       ; 08AC  11 00 3c
    LD A,8                            ; 08AF  3e 08
L08B1:
    LDI                               ; 08B1  ed a0
    LDI                               ; 08B3  ed a0
    LDI                               ; 08B5  ed a0
    LDI                               ; 08B7  ed a0
    LD BC,7Ch                         ; 08B9  01 7c 00
    ADD HL,BC                         ; 08BC  09
    DEC A                             ; 08BD  3d
    JR nz,L08B1                       ; 08BE  20 f1
    LD BC,7DD0h                       ; 08C0  01 d0 7d
    OUT (C),C                         ; 08C3  ed 49
    INC C                             ; 08C5  0c
    INC B                             ; 08C6  04
    OUT (C),C                         ; 08C7  ed 49
    POP DE                            ; 08C9  d1
    PUSH DE                           ; 08CA  d5
    LD HL,3C00h                       ; 08CB  21 00 3c
    LD B,8                            ; 08CE  06 08
L08D0:
    PUSH BC                           ; 08D0  c5
    PUSH DE                           ; 08D1  d5
    LD A,D                            ; 08D2  7a
    SRL A                             ; 08D3  cb 3f
    RR E                              ; 08D5  cb 1b
    ADD A,40h                         ; 08D7  c6 40
    LD D,A                            ; 08D9  57
    LD A,(HL)                         ; 08DA  7e
    OR A                              ; 08DB  b7
    JR nz,L08E2                       ; 08DC  20 04
    INC HL                            ; 08DE  23
    INC DE                            ; 08DF  13
    JR L08E4                          ; 08E0  18 02
L08E2:
    LDI                               ; 08E2  ed a0
L08E4:
    LD A,(HL)                         ; 08E4  7e
    OR A                              ; 08E5  b7
    JR nz,L08EC                       ; 08E6  20 04
    INC HL                            ; 08E8  23
    INC DE                            ; 08E9  13
    JR L08EE                          ; 08EA  18 02
L08EC:
    LDI                               ; 08EC  ed a0
L08EE:
    LD A,(HL)                         ; 08EE  7e
    OR A                              ; 08EF  b7
    JR nz,L08F6                       ; 08F0  20 04
    INC HL                            ; 08F2  23
    INC DE                            ; 08F3  13
    JR L08F8                          ; 08F4  18 02
L08F6:
    LDI                               ; 08F6  ed a0
L08F8:
    LD A,(HL)                         ; 08F8  7e
    OR A                              ; 08F9  b7
    JR nz,L08FF                       ; 08FA  20 03
    INC HL                            ; 08FC  23
    JR L0901                          ; 08FD  18 02
L08FF:
    LDI                               ; 08FF  ed a0
L0901:
    POP DE                            ; 0901  d1
    POP BC                            ; 0902  c1
    INC D                             ; 0903  14
    DJNZ L08D0                        ; 0904  10 ca
    LD BC,7DC0h                       ; 0906  01 c0 7d
    OUT (C),C                         ; 0909  ed 49
    INC B                             ; 090B  04
    INC C                             ; 090C  0c
    OUT (C),C                         ; 090D  ed 49
    POP DE                            ; 090F  d1
    LD HL,3C00h                       ; 0910  21 00 3c
    LD B,8                            ; 0913  06 08
    LD C,D                            ; 0915  4a
L0916:
    PUSH BC                           ; 0916  c5
    PUSH DE                           ; 0917  d5
    LD B,3Eh                          ; 0918  06 3e
    LD A,(BC)                         ; 091A  0a
    SRL A                             ; 091B  cb 3f
    RR E                              ; 091D  cb 1b
    ADD A,40h                         ; 091F  c6 40
    LD D,A                            ; 0921  57
    LD A,(HL)                         ; 0922  7e
    OR A                              ; 0923  b7
    JR nz,L092A                       ; 0924  20 04
    INC HL                            ; 0926  23
    INC DE                            ; 0927  13
    JR L092C                          ; 0928  18 02
L092A:
    LDI                               ; 092A  ed a0
L092C:
    LD A,(HL)                         ; 092C  7e
    OR A                              ; 092D  b7
    JR nz,L0934                       ; 092E  20 04
    INC HL                            ; 0930  23
    INC DE                            ; 0931  13
    JR L0936                          ; 0932  18 02
L0934:
    LDI                               ; 0934  ed a0
L0936:
    LD A,(HL)                         ; 0936  7e
    OR A                              ; 0937  b7
    JR nz,L093E                       ; 0938  20 04
    INC HL                            ; 093A  23
    INC DE                            ; 093B  13
    JR L0940                          ; 093C  18 02
L093E:
    LDI                               ; 093E  ed a0
L0940:
    LD A,(HL)                         ; 0940  7e
    OR A                              ; 0941  b7
    JR nz,L0947                       ; 0942  20 03
    INC HL                            ; 0944  23
    JR L0949                          ; 0945  18 02
L0947:
    LDI                               ; 0947  ed a0
L0949:
    POP DE                            ; 0949  d1
    POP BC                            ; 094A  c1
    INC C                             ; 094B  0c
    DJNZ L0916                        ; 094C  10 c8
    CALL VRAM_UNMAP                   ; 094E  cd 26 06
    EI                                ; 0951  fb
    POP BC                            ; 0952  c1
    POP DE                            ; 0953  d1
    POP HL                            ; 0954  e1
    RET                               ; 0955  c9
L0956:
    PUSH BC                           ; 0956  c5
    PUSH AF                           ; 0957  f5
    PUSH AF                           ; 0958  f5
    PUSH HL                           ; 0959  e5
    LD B,7Dh                          ; 095A  06 7d
    IN L,(C)                          ; 095C  ed 68
    INC B                             ; 095E  04
    IN H,(C)                          ; 095F  ed 60
    LD (0663h),HL                     ; 0961  22 63 06
    POP HL                            ; 0964  e1
    RLC H                             ; 0965  cb 04
    RLA                               ; 0967  17
    RRC H                             ; 0968  cb 0c
    AND 3                             ; 096A  e6 03
    OR D0h                            ; 096C  f6 d0
    DEC B                             ; 096E  05
    OUT (C),A                         ; 096F  ed 79
    POP AF                            ; 0971  f1
    RRCA                              ; 0972  0f
    RRCA                              ; 0973  0f
    RLC D                             ; 0974  cb 02
    RLA                               ; 0976  17
    RRC D                             ; 0977  cb 0a
    AND 3                             ; 0979  e6 03
    OR D0h                            ; 097B  f6 d0
    INC B                             ; 097D  04
    OUT (C),A                         ; 097E  ed 79
    POP AF                            ; 0980  f1
    POP BC                            ; 0981  c1
    RET                               ; 0982  c9
L0983:
    PUSH BC                           ; 0983  c5
    PUSH AF                           ; 0984  f5
    PUSH HL                           ; 0985  e5
    LD B,7Dh                          ; 0986  06 7d
    IN L,(C)                          ; 0988  ed 68
    INC B                             ; 098A  04
    IN H,(C)                          ; 098B  ed 60
    LD (0663h),HL                     ; 098D  22 63 06
    POP HL                            ; 0990  e1
    RLCA                              ; 0991  07
    RLCA                              ; 0992  07
    PUSH AF                           ; 0993  f5
    RLC H                             ; 0994  cb 04
    RLA                               ; 0996  17
    RRC H                             ; 0997  cb 0c
    AND 3                             ; 0999  e6 03
    OR D0h                            ; 099B  f6 d0
    DEC B                             ; 099D  05
    OUT (C),A                         ; 099E  ed 79
    POP AF                            ; 09A0  f1
    RLCA                              ; 09A1  07
    RLCA                              ; 09A2  07
    RLC D                             ; 09A3  cb 02
    RLA                               ; 09A5  17
    RRC D                             ; 09A6  cb 0a
    AND 3                             ; 09A8  e6 03
    OR D0h                            ; 09AA  f6 d0
    INC B                             ; 09AC  04
    OUT (C),A                         ; 09AD  ed 79
    POP AF                            ; 09AF  f1
    POP BC                            ; 09B0  c1
    RET                               ; 09B1  c9
L09B2:
    PUSH BC                           ; 09B2  c5
    LD C,D                            ; 09B3  4a
    LD B,3Eh                          ; 09B4  06 3e
    LD A,(BC)                         ; 09B6  0a
    LD D,A                            ; 09B7  57
    RLCA                              ; 09B8  07
    AND 1                             ; 09B9  e6 01
    OR C0h                            ; 09BB  f6 c0
    LD B,7Eh                          ; 09BD  06 7e
    OUT (C),A                         ; 09BF  ed 79
    POP BC                            ; 09C1  c1
    RET                               ; 09C2  c9
L09C3:
    BIT 2,A                           ; 09C3  cb 57
    JR nz,L0A01                       ; 09C5  20 3a
    PUSH DE                           ; 09C7  d5
    DI                                ; 09C8  f3
    CALL L0956                        ; 09C9  cd 56 09
    SRL B                             ; 09CC  cb 38
    LD A,B                            ; 09CE  78
    OR A                              ; 09CF  b7
    LD BC,80h                         ; 09D0  01 80 00
    JR z,L09D8                        ; 09D3  28 03
    LD C,A                            ; 09D5  4f
    LD B,0                            ; 09D6  06 00
L09D8:
    PUSH BC                           ; 09D8  c5
    SRL H                             ; 09D9  cb 3c
    RR L                              ; 09DB  cb 1d
    SRL D                             ; 09DD  cb 3a
    RR E                              ; 09DF  cb 1b
    SET 6,H                           ; 09E1  cb f4
    RES 7,H                           ; 09E3  cb bc
    SET 7,D                           ; 09E5  cb fa
    RES 6,D                           ; 09E7  cb b2
    PUSH HL                           ; 09E9  e5
    LDIR                              ; 09EA  ed b0
    POP HL                            ; 09EC  e1
    POP BC                            ; 09ED  c1
    POP DE                            ; 09EE  d1
    CALL L09B2                        ; 09EF  cd b2 09
    SRL D                             ; 09F2  cb 3a
    RR E                              ; 09F4  cb 1b
    SET 7,D                           ; 09F6  cb fa
    RES 6,D                           ; 09F8  cb b2
    LDIR                              ; 09FA  ed b0
    CALL VRAM_UNMAP                   ; 09FC  cd 26 06
    EI                                ; 09FF  fb
    RET                               ; 0A00  c9
L0A01:
    DI                                ; 0A01  f3
    CALL L0956                        ; 0A02  cd 56 09
    SRL B                             ; 0A05  cb 38
    LD A,B                            ; 0A07  78
    OR A                              ; 0A08  b7
    LD BC,80h                         ; 0A09  01 80 00
    JR z,L0A11                        ; 0A0C  28 03
    LD C,A                            ; 0A0E  4f
    LD B,0                            ; 0A0F  06 00
L0A11:
    SRL H                             ; 0A11  cb 3c
    RR L                              ; 0A13  cb 1d
    SRL D                             ; 0A15  cb 3a
    RR E                              ; 0A17  cb 1b
    SET 6,H                           ; 0A19  cb f4
    RES 7,H                           ; 0A1B  cb bc
    SET 7,D                           ; 0A1D  cb fa
    RES 6,D                           ; 0A1F  cb b2
    LDIR                              ; 0A21  ed b0
    CALL VRAM_UNMAP                   ; 0A23  cd 26 06
    EI                                ; 0A26  fb
    RET                               ; 0A27  c9
L0A28:
    BIT 4,A                           ; 0A28  cb 67
    JR nz,L0A82                       ; 0A2A  20 56
    PUSH DE                           ; 0A2C  d5
    DI                                ; 0A2D  f3
    CALL L0983                        ; 0A2E  cd 83 09
    SRL B                             ; 0A31  cb 38
    LD A,B                            ; 0A33  78
    OR A                              ; 0A34  b7
    LD BC,80h                         ; 0A35  01 80 00
    JR z,L0A3D                        ; 0A38  28 03
    LD C,A                            ; 0A3A  4f
    LD B,0                            ; 0A3B  06 00
L0A3D:
    PUSH BC                           ; 0A3D  c5
    SRL H                             ; 0A3E  cb 3c
    RR L                              ; 0A40  cb 1d
    SRL D                             ; 0A42  cb 3a
    RR E                              ; 0A44  cb 1b
    SET 6,H                           ; 0A46  cb f4
    RES 7,H                           ; 0A48  cb bc
    SET 7,D                           ; 0A4A  cb fa
    RES 6,D                           ; 0A4C  cb b2
    PUSH HL                           ; 0A4E  e5
L0A4F:
    LD A,(HL)                         ; 0A4F  7e
    OR A                              ; 0A50  b7
    JR nz,L0A5A                       ; 0A51  20 07
    INC HL                            ; 0A53  23
    INC DE                            ; 0A54  13
    DEC C                             ; 0A55  0d
    JR nz,L0A4F                       ; 0A56  20 f7
    JR L0A5F                          ; 0A58  18 05
L0A5A:
    LDI                               ; 0A5A  ed a0
    JP pe,L0A4F                       ; 0A5C  ea 4f 0a
L0A5F:
    POP HL                            ; 0A5F  e1
    POP BC                            ; 0A60  c1
    POP DE                            ; 0A61  d1
    CALL L09B2                        ; 0A62  cd b2 09
    SRL D                             ; 0A65  cb 3a
    RR E                              ; 0A67  cb 1b
    SET 7,D                           ; 0A69  cb fa
    RES 6,D                           ; 0A6B  cb b2
L0A6D:
    LD A,(HL)                         ; 0A6D  7e
    OR A                              ; 0A6E  b7
    JR nz,L0A78                       ; 0A6F  20 07
    INC HL                            ; 0A71  23
    INC DE                            ; 0A72  13
    DEC C                             ; 0A73  0d
    JR nz,L0A6D                       ; 0A74  20 f7
    JR L0A7D                          ; 0A76  18 05
L0A78:
    LDI                               ; 0A78  ed a0
    JP pe,L0A6D                       ; 0A7A  ea 6d 0a
L0A7D:
    CALL VRAM_UNMAP                   ; 0A7D  cd 26 06
    EI                                ; 0A80  fb
    RET                               ; 0A81  c9
L0A82:
    DI                                ; 0A82  f3
    CALL L0983                        ; 0A83  cd 83 09
    SRL B                             ; 0A86  cb 38
    LD A,B                            ; 0A88  78
    OR A                              ; 0A89  b7
    LD BC,80h                         ; 0A8A  01 80 00
    JR z,L0A92                        ; 0A8D  28 03
    LD C,A                            ; 0A8F  4f
    LD B,0                            ; 0A90  06 00
L0A92:
    SRL H                             ; 0A92  cb 3c
    RR L                              ; 0A94  cb 1d
    SRL D                             ; 0A96  cb 3a
    RR E                              ; 0A98  cb 1b
    SET 6,H                           ; 0A9A  cb f4
    RES 7,H                           ; 0A9C  cb bc
    SET 7,D                           ; 0A9E  cb fa
    RES 6,D                           ; 0AA0  cb b2
L0AA2:
    LD A,(HL)                         ; 0AA2  7e
    OR A                              ; 0AA3  b7
    JR nz,L0AAD                       ; 0AA4  20 07
    INC HL                            ; 0AA6  23
    INC DE                            ; 0AA7  13
    DEC C                             ; 0AA8  0d
    JR nz,L0AA2                       ; 0AA9  20 f7
    JR L0AB2                          ; 0AAB  18 05
L0AAD:
    LDI                               ; 0AAD  ed a0
    JP pe,L0AA2                       ; 0AAF  ea a2 0a
L0AB2:
    CALL VRAM_UNMAP                   ; 0AB2  cd 26 06
    EI                                ; 0AB5  fb
    RET                               ; 0AB6  c9

; --------------------------------------------------------------------------
; Sprites: si cambia la tabla de atributos (copia en E800h / 3800h),
; restaura el fondo y los redibuja; solo redibuja los que cambian
; --------------------------------------------------------------------------
do_FRAME:
    LD A,(06D2h)                      ; 0AB7  3a d2 06
    AND 2                             ; 0ABA  e6 02
    RET nz                            ; 0ABC  c0
    LD IX,E800h                       ; 0ABD  dd 21 00 e8
    LD IY,3800h                       ; 0AC1  fd 21 00 38
    LD BC,1000h                       ; 0AC5  01 00 10
    LD A,(IX+1)                       ; 0AC8  dd 7e 01
    CP (IX+5)                         ; 0ACB  dd be 05
    JP nz,L0B36                       ; 0ACE  c2 36 0b
    DI                                ; 0AD1  f3
    CALL VRAM_MAP                     ; 0AD2  cd 4c 06
    LD L,0                            ; 0AD5  2e 00
    LD B,80h                          ; 0AD7  06 80
    LD D,3Dh                          ; 0AD9  16 3d
L0ADB:
    LD H,B8h                          ; 0ADB  26 b8
    LD E,(HL)                         ; 0ADD  5e
    LD A,(DE)                         ; 0ADE  1a
    LD H,30h                          ; 0ADF  26 30
    CP (HL)                           ; 0AE1  be
    JR nz,L0AF4                       ; 0AE2  20 10
    INC L                             ; 0AE4  2c
    DJNZ L0ADB                        ; 0AE5  10 f4
    CALL VRAM_UNMAP                   ; 0AE7  cd 26 06
    EI                                ; 0AEA  fb
    JP L0B13                          ; 0AEB  c3 13 0b
L0AEE:
    LD H,B8h                          ; 0AEE  26 b8
    LD E,(HL)                         ; 0AF0  5e
    LD A,(DE)                         ; 0AF1  1a
    LD H,30h                          ; 0AF2  26 30
L0AF4:
    LD (HL),A                         ; 0AF4  77
    INC L                             ; 0AF5  2c
    DJNZ L0AEE                        ; 0AF6  10 f6
    CALL VRAM_UNMAP                   ; 0AF8  cd 26 06
    EI                                ; 0AFB  fb
    LD IX,E800h                       ; 0AFC  dd 21 00 e8
    LD IY,3800h                       ; 0B00  fd 21 00 38
    CALL SPR_DRAW_ALL                 ; 0B04  cd 6f 0b
    LD HL,0B8Ah                       ; 0B07  21 8a 0b
    INC (HL)                          ; 0B0A  34
    LD A,(HL)                         ; 0B0B  7e
    CP 3                              ; 0B0C  fe 03
    RET c                             ; 0B0E  d8
    LD (HL),0                         ; 0B0F  36 00
    JR L0B2B                          ; 0B11  18 18
L0B13:
    LD HL,0B8Ah                       ; 0B13  21 8a 0b
    INC (HL)                          ; 0B16  34
    LD A,(HL)                         ; 0B17  7e
    CP 3                              ; 0B18  fe 03
    RET c                             ; 0B1A  d8
    LD (HL),0                         ; 0B1B  36 00
    LD IX,E800h                       ; 0B1D  dd 21 00 e8
    LD IY,3800h                       ; 0B21  fd 21 00 38
    CALL L0BC4                        ; 0B25  cd c4 0b
    CALL nz,SPR_DRAW_ALL              ; 0B28  c4 6f 0b
L0B2B:
    LD IX,E810h                       ; 0B2B  dd 21 10 e8
    LD IY,3810h                       ; 0B2F  fd 21 10 38
    LD BC,0E04h                       ; 0B33  01 04 0e
L0B36:
    LD A,(IX+1)                       ; 0B36  dd 7e 01
    CP (IX+5)                         ; 0B39  dd be 05
    JR nz,L0B50                       ; 0B3C  20 12
    CALL L0BCB                        ; 0B3E  cd cb 0b
    CALL nz,L0B8C                     ; 0B41  c4 8c 0b
    LD DE,8                           ; 0B44  11 08 00
    ADD IX,DE                         ; 0B47  dd 19
    ADD IY,DE                         ; 0B49  fd 19
    INC C                             ; 0B4B  0c
    INC C                             ; 0B4C  0c
    DJNZ L0B36                        ; 0B4D  10 e7
    RET                               ; 0B4F  c9
L0B50:
    CALL L0BCB                        ; 0B50  cd cb 0b
    CALL nz,L0C53                     ; 0B53  c4 53 0c
    LD DE,4                           ; 0B56  11 04 00
    ADD IX,DE                         ; 0B59  dd 19
    ADD IY,DE                         ; 0B5B  fd 19
    INC C                             ; 0B5D  0c
    CALL L0BCB                        ; 0B5E  cd cb 0b
    CALL nz,L0C53                     ; 0B61  c4 53 0c
    LD DE,4                           ; 0B64  11 04 00
    ADD IX,DE                         ; 0B67  dd 19
    ADD IY,DE                         ; 0B69  fd 19
    INC C                             ; 0B6B  0c
    DJNZ L0B36                        ; 0B6C  10 c8
    RET                               ; 0B6E  c9

; --------------------------------------------------------------------------
; Dibuja los sprites (modo 2 del MSX2, colores por linea) sobre el mapa de
; bits
; --------------------------------------------------------------------------
SPR_DRAW_ALL:
    CALL L0DB8                        ; 0B6F  cd b8 0d
    LD DE,8                           ; 0B72  11 08 00
    ADD IX,DE                         ; 0B75  dd 19
    ADD IY,DE                         ; 0B77  fd 19
    LD C,2                            ; 0B79  0e 02
    CALL L0B8C                        ; 0B7B  cd 8c 0b
    LD DE,FFF8h                       ; 0B7E  11 f8 ff
    ADD IX,DE                         ; 0B81  dd 19
    ADD IY,DE                         ; 0B83  fd 19
    LD C,0                            ; 0B85  0e 00
    JP L0B91                          ; 0B87  c3 91 0b
    DB 00h, 00h                                                    ; 0B8A  ..
L0B8C:
    PUSH BC                           ; 0B8C  c5
    CALL L0DB8                        ; 0B8D  cd b8 0d
    POP BC                            ; 0B90  c1
L0B91:
    LD A,(IX)                         ; 0B91  dd 7e 00
    LD (IY),A                         ; 0B94  fd 77 00
    LD A,(IX+2)                       ; 0B97  dd 7e 02
    LD (IY+2),A                       ; 0B9A  fd 77 02
    LD A,(IX+1)                       ; 0B9D  dd 7e 01
    LD (IY+1),A                       ; 0BA0  fd 77 01
    PUSH BC                           ; 0BA3  c5
    PUSH IX                           ; 0BA4  dd e5
    LD H,0                            ; 0BA6  26 00
    LD L,C                            ; 0BA8  69
    ADD HL,HL                         ; 0BA9  29
    ADD HL,HL                         ; 0BAA  29
    ADD HL,HL                         ; 0BAB  29
    ADD HL,HL                         ; 0BAC  29
    LD DE,D200h                       ; 0BAD  11 00 d2
    ADD HL,DE                         ; 0BB0  19
    PUSH HL                           ; 0BB1  e5
    POP IX                            ; 0BB2  dd e1
    LD D,(IY)                         ; 0BB4  fd 56 00
    LD E,(IY+1)                       ; 0BB7  fd 5e 01
    LD A,(IY+2)                       ; 0BBA  fd 7e 02
    CALL L0BE0                        ; 0BBD  cd e0 0b
    POP IX                            ; 0BC0  dd e1
    POP BC                            ; 0BC2  c1
    RET                               ; 0BC3  c9
L0BC4:
    LD A,(IY+10)                      ; 0BC4  fd 7e 0a
    CP (IX+10)                        ; 0BC7  dd be 0a
    RET nz                            ; 0BCA  c0
L0BCB:
    LD A,(IY+2)                       ; 0BCB  fd 7e 02
    CP (IX+2)                         ; 0BCE  dd be 02
    RET nz                            ; 0BD1  c0
    LD A,(IY)                         ; 0BD2  fd 7e 00
    CP (IX)                           ; 0BD5  dd be 00
    RET nz                            ; 0BD8  c0
    LD A,(IY+1)                       ; 0BD9  fd 7e 01
    CP (IX+1)                         ; 0BDC  dd be 01
    RET                               ; 0BDF  c9
L0BE0:
    LD C,A                            ; 0BE0  4f
    LD A,D                            ; 0BE1  7a
    CP E0h                            ; 0BE2  fe e0
    RET z                             ; 0BE4  c8
    LD A,E                            ; 0BE5  7b
    CP F0h                            ; 0BE6  fe f0
    RET nc                            ; 0BE8  d0
    PUSH IY                           ; 0BE9  fd e5
    LD A,C                            ; 0BEB  79
    AND FCh                           ; 0BEC  e6 fc
    LD L,A                            ; 0BEE  6f
    LD H,0                            ; 0BEF  26 00
    ADD HL,HL                         ; 0BF1  29
    ADD HL,HL                         ; 0BF2  29
    ADD HL,HL                         ; 0BF3  29
    LD BC,3000h                       ; 0BF4  01 00 30
    ADD HL,BC                         ; 0BF7  09
    PUSH HL                           ; 0BF8  e5
    POP IY                            ; 0BF9  fd e1
    DI                                ; 0BFB  f3
    CALL L060F                        ; 0BFC  cd 0f 06
    LD B,10h                          ; 0BFF  06 10
    LD C,D                            ; 0C01  4a
L0C02:
    PUSH BC                           ; 0C02  c5
    PUSH DE                           ; 0C03  d5
    LD A,C                            ; 0C04  79
    CP D0h                            ; 0C05  fe d0
    JR nc,L0C43                       ; 0C07  30 3a
    LD B,3Eh                          ; 0C09  06 3e
    LD A,(BC)                         ; 0C0B  0a
    SRL A                             ; 0C0C  cb 3f
    RR E                              ; 0C0E  cb 1b
    ADD A,40h                         ; 0C10  c6 40
    LD D,A                            ; 0C12  57
    INC B                             ; 0C13  04
    LD A,(IX)                         ; 0C14  dd 7e 00
    AND 15                            ; 0C17  e6 0f
    LD C,A                            ; 0C19  4f
    LD A,(BC)                         ; 0C1A  0a
    RLCA                              ; 0C1B  07
    LD H,A                            ; 0C1C  67
    LD A,(IX+10h)                     ; 0C1D  dd 7e 10
    AND 15                            ; 0C20  e6 0f
    LD C,A                            ; 0C22  4f
    LD A,(BC)                         ; 0C23  0a
    RLCA                              ; 0C24  07
    LD C,A                            ; 0C25  4f
    LD B,H                            ; 0C26  44
    LD H,(IY)                         ; 0C27  fd 66 00
    LD L,(IY+20h)                     ; 0C2A  fd 6e 20
    LD A,L                            ; 0C2D  7d
    OR H                              ; 0C2E  b4
    JR nz,L0C37                       ; 0C2F  20 06
    INC DE                            ; 0C31  13
    INC DE                            ; 0C32  13
    INC DE                            ; 0C33  13
    INC DE                            ; 0C34  13
    JR L0C3A                          ; 0C35  18 03
L0C37:
    CALL L0CFB                        ; 0C37  cd fb 0c
L0C3A:
    LD H,(IY+10h)                     ; 0C3A  fd 66 10
    LD L,(IY+30h)                     ; 0C3D  fd 6e 30
    CALL L0CFB                        ; 0C40  cd fb 0c
L0C43:
    INC IX                            ; 0C43  dd 23
    INC IY                            ; 0C45  fd 23
    POP DE                            ; 0C47  d1
    POP BC                            ; 0C48  c1
    INC C                             ; 0C49  0c
    DJNZ L0C02                        ; 0C4A  10 b6
    POP IY                            ; 0C4C  fd e1
    CALL VRAM_UNMAP                   ; 0C4E  cd 26 06
    EI                                ; 0C51  fb
    RET                               ; 0C52  c9
L0C53:
    PUSH BC                           ; 0C53  c5
    CALL L0DB8                        ; 0C54  cd b8 0d
    POP BC                            ; 0C57  c1
L0C58:
    LD A,(IX)                         ; 0C58  dd 7e 00
    LD (IY),A                         ; 0C5B  fd 77 00
    LD A,(IX+2)                       ; 0C5E  dd 7e 02
    LD (IY+2),A                       ; 0C61  fd 77 02
    LD A,(IX+1)                       ; 0C64  dd 7e 01
    LD (IY+1),A                       ; 0C67  fd 77 01
    PUSH BC                           ; 0C6A  c5
    PUSH IX                           ; 0C6B  dd e5
    LD H,0                            ; 0C6D  26 00
    LD L,C                            ; 0C6F  69
    ADD HL,HL                         ; 0C70  29
    ADD HL,HL                         ; 0C71  29
    ADD HL,HL                         ; 0C72  29
    ADD HL,HL                         ; 0C73  29
    LD DE,D200h                       ; 0C74  11 00 d2
    ADD HL,DE                         ; 0C77  19
    PUSH HL                           ; 0C78  e5
    POP IX                            ; 0C79  dd e1
    LD D,(IY)                         ; 0C7B  fd 56 00
    LD E,(IY+1)                       ; 0C7E  fd 5e 01
    LD A,(IY+2)                       ; 0C81  fd 7e 02
    CALL L0C8B                        ; 0C84  cd 8b 0c
    POP IX                            ; 0C87  dd e1
    POP BC                            ; 0C89  c1
    RET                               ; 0C8A  c9
L0C8B:
    LD C,A                            ; 0C8B  4f
    LD A,D                            ; 0C8C  7a
    CP E0h                            ; 0C8D  fe e0
    RET z                             ; 0C8F  c8
    LD A,E                            ; 0C90  7b
    CP F0h                            ; 0C91  fe f0
    RET nc                            ; 0C93  d0
    PUSH IY                           ; 0C94  fd e5
    LD A,C                            ; 0C96  79
    AND FCh                           ; 0C97  e6 fc
    LD L,A                            ; 0C99  6f
    LD H,0                            ; 0C9A  26 00
    ADD HL,HL                         ; 0C9C  29
    ADD HL,HL                         ; 0C9D  29
    ADD HL,HL                         ; 0C9E  29
    LD BC,3000h                       ; 0C9F  01 00 30
    ADD HL,BC                         ; 0CA2  09
    PUSH HL                           ; 0CA3  e5
    POP IY                            ; 0CA4  fd e1
    DI                                ; 0CA6  f3
    CALL L060F                        ; 0CA7  cd 0f 06
    LD B,10h                          ; 0CAA  06 10
    LD C,D                            ; 0CAC  4a
L0CAD:
    PUSH BC                           ; 0CAD  c5
    PUSH DE                           ; 0CAE  d5
    LD A,C                            ; 0CAF  79
    CP D0h                            ; 0CB0  fe d0
    JR nc,L0CEB                       ; 0CB2  30 37
    LD B,3Eh                          ; 0CB4  06 3e
    LD A,(BC)                         ; 0CB6  0a
    SRL A                             ; 0CB7  cb 3f
    RR E                              ; 0CB9  cb 1b
    ADD A,40h                         ; 0CBB  c6 40
    LD D,A                            ; 0CBD  57
    INC B                             ; 0CBE  04
    LD A,(IX)                         ; 0CBF  dd 7e 00
    AND 15                            ; 0CC2  e6 0f
    LD C,A                            ; 0CC4  4f
    LD A,(BC)                         ; 0CC5  0a
    RLCA                              ; 0CC6  07
    LD H,A                            ; 0CC7  67
    LD A,0                            ; 0CC8  3e 00
    AND 15                            ; 0CCA  e6 0f
    LD C,A                            ; 0CCC  4f
    LD A,(BC)                         ; 0CCD  0a
    RLCA                              ; 0CCE  07
    LD C,A                            ; 0CCF  4f
    LD B,H                            ; 0CD0  44
    LD H,(IY)                         ; 0CD1  fd 66 00
    LD L,0                            ; 0CD4  2e 00
    LD A,L                            ; 0CD6  7d
    OR H                              ; 0CD7  b4
    JR nz,L0CE0                       ; 0CD8  20 06
    INC DE                            ; 0CDA  13
    INC DE                            ; 0CDB  13
    INC DE                            ; 0CDC  13
    INC DE                            ; 0CDD  13
    JR L0CE3                          ; 0CDE  18 03
L0CE0:
    CALL L0CFB                        ; 0CE0  cd fb 0c
L0CE3:
    LD H,(IY+10h)                     ; 0CE3  fd 66 10
    LD L,0                            ; 0CE6  2e 00
    CALL L0CFB                        ; 0CE8  cd fb 0c
L0CEB:
    INC IX                            ; 0CEB  dd 23
    INC IY                            ; 0CED  fd 23
    POP DE                            ; 0CEF  d1
    POP BC                            ; 0CF0  c1
    INC C                             ; 0CF1  0c
    DJNZ L0CAD                        ; 0CF2  10 b9
    POP IY                            ; 0CF4  fd e1
    CALL VRAM_UNMAP                   ; 0CF6  cd 26 06
    EI                                ; 0CF9  fb
    RET                               ; 0CFA  c9
L0CFB:
    LD A,(DE)                         ; 0CFB  1a
    RLC L                             ; 0CFC  cb 05
    JR nc,L0D0A                       ; 0CFE  30 0a
    AND 55h                           ; 0D00  e6 55
    OR C                              ; 0D02  b1
    RLC H                             ; 0D03  cb 04
    JR nc,L0D11                       ; 0D05  30 0a
    OR B                              ; 0D07  b0
    JR L0D11                          ; 0D08  18 07
L0D0A:
    RLC H                             ; 0D0A  cb 04
    JR nc,L0D11                       ; 0D0C  30 03
    AND 55h                           ; 0D0E  e6 55
    OR B                              ; 0D10  b0
L0D11:
    RLCA                              ; 0D11  07
    RLC L                             ; 0D12  cb 05
    JR nc,L0D20                       ; 0D14  30 0a
    AND 55h                           ; 0D16  e6 55
    OR C                              ; 0D18  b1
    RLC H                             ; 0D19  cb 04
    JR nc,L0D27                       ; 0D1B  30 0a
    OR B                              ; 0D1D  b0
    JR L0D27                          ; 0D1E  18 07
L0D20:
    RLC H                             ; 0D20  cb 04
    JR nc,L0D27                       ; 0D22  30 03
    AND 55h                           ; 0D24  e6 55
    OR B                              ; 0D26  b0
L0D27:
    RRCA                              ; 0D27  0f
    LD (DE),A                         ; 0D28  12
    INC DE                            ; 0D29  13
    LD A,(DE)                         ; 0D2A  1a
    RLC L                             ; 0D2B  cb 05
    JR nc,L0D39                       ; 0D2D  30 0a
    AND 55h                           ; 0D2F  e6 55
    OR C                              ; 0D31  b1
    RLC H                             ; 0D32  cb 04
    JR nc,L0D40                       ; 0D34  30 0a
    OR B                              ; 0D36  b0
    JR L0D40                          ; 0D37  18 07
L0D39:
    RLC H                             ; 0D39  cb 04
    JR nc,L0D40                       ; 0D3B  30 03
    AND 55h                           ; 0D3D  e6 55
    OR B                              ; 0D3F  b0
L0D40:
    RLCA                              ; 0D40  07
    RLC L                             ; 0D41  cb 05
    JR nc,L0D4F                       ; 0D43  30 0a
    AND 55h                           ; 0D45  e6 55
    OR C                              ; 0D47  b1
    RLC H                             ; 0D48  cb 04
    JR nc,L0D56                       ; 0D4A  30 0a
    OR B                              ; 0D4C  b0
    JR L0D56                          ; 0D4D  18 07
L0D4F:
    RLC H                             ; 0D4F  cb 04
    JR nc,L0D56                       ; 0D51  30 03
    AND 55h                           ; 0D53  e6 55
    OR B                              ; 0D55  b0
L0D56:
    RRCA                              ; 0D56  0f
    LD (DE),A                         ; 0D57  12
    INC DE                            ; 0D58  13
    LD A,(DE)                         ; 0D59  1a
    RLC L                             ; 0D5A  cb 05
    JR nc,L0D68                       ; 0D5C  30 0a
    AND 55h                           ; 0D5E  e6 55
    OR C                              ; 0D60  b1
    RLC H                             ; 0D61  cb 04
    JR nc,L0D6F                       ; 0D63  30 0a
    OR B                              ; 0D65  b0
    JR L0D6F                          ; 0D66  18 07
L0D68:
    RLC H                             ; 0D68  cb 04
    JR nc,L0D6F                       ; 0D6A  30 03
    AND 55h                           ; 0D6C  e6 55
    OR B                              ; 0D6E  b0
L0D6F:
    RLCA                              ; 0D6F  07
    RLC L                             ; 0D70  cb 05
    JR nc,L0D7E                       ; 0D72  30 0a
    AND 55h                           ; 0D74  e6 55
    OR C                              ; 0D76  b1
    RLC H                             ; 0D77  cb 04
    JR nc,L0D85                       ; 0D79  30 0a
    OR B                              ; 0D7B  b0
    JR L0D85                          ; 0D7C  18 07
L0D7E:
    RLC H                             ; 0D7E  cb 04
    JR nc,L0D85                       ; 0D80  30 03
    AND 55h                           ; 0D82  e6 55
    OR B                              ; 0D84  b0
L0D85:
    RRCA                              ; 0D85  0f
    LD (DE),A                         ; 0D86  12
    INC DE                            ; 0D87  13
    LD A,(DE)                         ; 0D88  1a
    RLC L                             ; 0D89  cb 05
    JR nc,L0D97                       ; 0D8B  30 0a
    AND 55h                           ; 0D8D  e6 55
    OR C                              ; 0D8F  b1
    RLC H                             ; 0D90  cb 04
    JR nc,L0D9E                       ; 0D92  30 0a
    OR B                              ; 0D94  b0
    JR L0D9E                          ; 0D95  18 07
L0D97:
    RLC H                             ; 0D97  cb 04
    JR nc,L0D9E                       ; 0D99  30 03
    AND 55h                           ; 0D9B  e6 55
    OR B                              ; 0D9D  b0
L0D9E:
    RLCA                              ; 0D9E  07
    RLC L                             ; 0D9F  cb 05
    JR nc,L0DAD                       ; 0DA1  30 0a
    AND 55h                           ; 0DA3  e6 55
    OR C                              ; 0DA5  b1
    RLC H                             ; 0DA6  cb 04
    JR nc,L0DB4                       ; 0DA8  30 0a
    OR B                              ; 0DAA  b0
    JR L0DB4                          ; 0DAB  18 07
L0DAD:
    RLC H                             ; 0DAD  cb 04
    JR nc,L0DB4                       ; 0DAF  30 03
    AND 55h                           ; 0DB1  e6 55
    OR B                              ; 0DB3  b0
L0DB4:
    RRCA                              ; 0DB4  0f
    LD (DE),A                         ; 0DB5  12
    INC DE                            ; 0DB6  13
    RET                               ; 0DB7  c9
L0DB8:
    LD A,(IY+1)                       ; 0DB8  fd 7e 01
    CP F0h                            ; 0DBB  fe f0
    RET nc                            ; 0DBD  d0
    LD L,A                            ; 0DBE  6f
    LD A,(IY)                         ; 0DBF  fd 7e 00
    CP E0h                            ; 0DC2  fe e0
    RET z                             ; 0DC4  c8
    LD H,A                            ; 0DC5  67
    SRL H                             ; 0DC6  cb 3c
    RR L                              ; 0DC8  cb 1d
    DI                                ; 0DCA  f3
    CALL L0635                        ; 0DCB  cd 35 06
    LD DE,3C00h                       ; 0DCE  11 00 3c
    LD B,10h                          ; 0DD1  06 10
L0DD3:
    PUSH BC                           ; 0DD3  c5
    PUSH HL                           ; 0DD4  e5
    LD A,H                            ; 0DD5  7c
    CP 68h                            ; 0DD6  fe 68
    JR c,L0DE0                        ; 0DD8  38 06
    LD A,E                            ; 0DDA  7b
    ADD A,8                           ; 0DDB  c6 08
    LD E,A                            ; 0DDD  5f
    JR L0DF3                          ; 0DDE  18 13
L0DE0:
    ADD A,40h                         ; 0DE0  c6 40
    LD H,A                            ; 0DE2  67
    LDI                               ; 0DE3  ed a0
    LDI                               ; 0DE5  ed a0
    LDI                               ; 0DE7  ed a0
    LDI                               ; 0DE9  ed a0
    LDI                               ; 0DEB  ed a0
    LDI                               ; 0DED  ed a0
    LDI                               ; 0DEF  ed a0
    LDI                               ; 0DF1  ed a0
L0DF3:
    POP HL                            ; 0DF3  e1
    POP BC                            ; 0DF4  c1
    ADD HL,HL                         ; 0DF5  29
    INC H                             ; 0DF6  24
    SRL H                             ; 0DF7  cb 3c
    RR L                              ; 0DF9  cb 1d
    DJNZ L0DD3                        ; 0DFB  10 d6
    LD BC,7DC0h                       ; 0DFD  01 c0 7d
    OUT (C),C                         ; 0E00  ed 49
    INC B                             ; 0E02  04
    INC C                             ; 0E03  0c
    OUT (C),C                         ; 0E04  ed 49
    LD C,(IY)                         ; 0E06  fd 4e 00
    LD E,(IY+1)                       ; 0E09  fd 5e 01
    LD HL,3C00h                       ; 0E0C  21 00 3c
    LD B,10h                          ; 0E0F  06 10
L0E11:
    LD A,C                            ; 0E11  79
    CP D0h                            ; 0E12  fe d0
    JR nc,L0E3C                       ; 0E14  30 26
    PUSH BC                           ; 0E16  c5
    PUSH DE                           ; 0E17  d5
    LD B,3Eh                          ; 0E18  06 3e
    LD A,(BC)                         ; 0E1A  0a
    SRL A                             ; 0E1B  cb 3f
    RR E                              ; 0E1D  cb 1b
    ADD A,40h                         ; 0E1F  c6 40
    LD D,A                            ; 0E21  57
    LDI                               ; 0E22  ed a0
    LDI                               ; 0E24  ed a0
    LDI                               ; 0E26  ed a0
    LDI                               ; 0E28  ed a0
    LDI                               ; 0E2A  ed a0
    LDI                               ; 0E2C  ed a0
    LDI                               ; 0E2E  ed a0
    LDI                               ; 0E30  ed a0
    POP DE                            ; 0E32  d1
    POP BC                            ; 0E33  c1
    INC C                             ; 0E34  0c
    DJNZ L0E11                        ; 0E35  10 da
    CALL VRAM_UNMAP                   ; 0E37  cd 26 06
    EI                                ; 0E3A  fb
    RET                               ; 0E3B  c9
L0E3C:
    INC C                             ; 0E3C  0c
    LD A,L                            ; 0E3D  7d
    ADD A,8                           ; 0E3E  c6 08
    LD L,A                            ; 0E40  6f
    DJNZ L0E11                        ; 0E41  10 ce
    CALL VRAM_UNMAP                   ; 0E43  cd 26 06
    EI                                ; 0E46  fb
    RET                               ; 0E47  c9
