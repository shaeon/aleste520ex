; ============================================================================
; gb2load.asm - Cargador generico para juegos de MSX2 con la GameBios v2
;               (Aleste 520EX, MSX-DOS). Lo usa tools/msxrom2aleste.py.
;
; 1. Lee la ROM del juego (fichero del FCB) banco a banco (8 KB) y copia cada
;    banco a las paginas compuestas de 16 KB donde va (tabla DEST: por banco,
;    hasta 5 parejas pagina / mitad, 40h = 4000h, 60h = 6000h; 0 = fin).
; 2. Monta la GameBios v2 en la pagina 0Fh (copiada de un cargador del Aleste
;    por la herramienta; aqui solo hay punteros), sus tres tablas, la inversa
;    de 3F00h en 3D00h y la rutina de bancos (en 0E00h al ejecutar).
; 3. RAM del juego (pagina 3Fh): a cero, y los ganchos del MSX (FD9Ah-FFC9h)
;    a RET.
; 4. Arranca desde un trozo en C000h de la pagina 3Fh: GameBios como pagina 0,
;    paginas iniciales de los bancos, y salta a la direccion de inicio (4002h).
;
; La herramienta rellena el bloque de parametros (PARAM) y anade los datos.
; ============================================================================
BDOS    equ     0005h
GBPAGE  equ     0CFh                    ; C0h + 0Fh: pagina de la GameBios
RAMPAGE equ     0FFh                    ; C0h + 3Fh: RAM del juego

        org     0100h
start:  ld      sp,(0006h)
        ld      de,msg_load
        ld      c,09h
        call    BDOS
        ld      de,fcb
        ld      c,0Fh                   ; abrir
        call    BDOS
        or      a
        jp      nz,error
        xor     a
        ld      (fcb+32),a              ; registro actual = 0
        ld      (bank),a

nbank:  ld      hl,8000h                ; 8 KB del banco en 8000h (TPA)
        ld      b,64
rdl:    push    bc
        push    hl
        ex      de,hl
        ld      c,1Ah                   ; DMA
        call    BDOS
        ld      de,fcb
        ld      c,14h                   ; lectura secuencial (128 bytes)
        call    BDOS
        pop     hl
        pop     bc
        or      a
        jp      nz,error
        ld      de,128
        add     hl,de
        djnz    rdl

        ld      a,(bank)                ; HL = DEST + banco * 11
        ld      l,a
        ld      h,0
        ld      e,l
        ld      d,h
        add     hl,hl                   ; 2
        add     hl,hl                   ; 4
        add     hl,de                   ; 5
        add     hl,hl                   ; 10
        add     hl,de                   ; 11
        ld      de,dest
        add     hl,de
dl:     ld      a,(hl)                  ; pagina (C0h + n) o 0 = fin
        or      a
        jr      z,dnext
        inc     hl
        ld      bc,7D00h
        out     (c),a                   ; pagina compuesta en 4000h
        ld      d,(hl)                  ; mitad: 40h o 60h
        inc     hl
        ld      e,0
        push    hl
        ld      hl,8000h
        ld      bc,2000h
        ldir
        pop     hl
        jr      dl
dnext:  ld      a,(bank)
        inc     a
        ld      (bank),a
        cp      16
        jr      nz,nbank

        ld      a,GBPAGE                ; GameBios en su pagina
        ld      bc,7D00h
        out     (c),a
        ld      hl,(p_gb)
        ld      de,4000h
        ld      bc,(p_gblen)
        ldir
        ld      hl,(p_t3e)
        ld      de,7E00h
        ld      bc,0100h
        ldir
        ld      hl,(p_t3f)
        ld      de,7F00h
        ld      bc,0100h
        ldir
        ld      hl,(p_t2f)
        ld      de,6F00h
        ld      bc,0100h
        ldir
        ld      b,0                     ; inversa de 3F00h en 3D00h (como VKILLER.COM)
        ld      hl,7F00h
        ld      d,7Dh
inv:    ld      e,(hl)
        ld      a,l
        ld      (de),a
        inc     l
        djnz    inv
        ld      hl,(p_bank)             ; rutina de bancos en 0E00h
        ld      de,4E00h
        ld      bc,(p_banklen)
        ldir

        ld      a,RAMPAGE               ; RAM del juego
        ld      bc,7D00h
        out     (c),a
        ld      hl,4000h
        ld      de,4001h
        ld      bc,3FFFh
        ld      (hl),0
        ldir
        ld      hl,7D9Ah                ; ganchos FD9Ah-FFC9h = RET
        ld      de,7D9Bh
        ld      bc,022Fh
        ld      (hl),0C9h
        ldir
        ld      hl,stub                 ; arranque en C000h
        ld      de,4000h
        ld      bc,stubend-stub
        ldir
        di
        ld      a,RAMPAGE
        ld      bc,7F00h
        out     (c),a                   ; cuarto 3 = RAM del juego (fin de MSX-DOS)
        jp      0C000h

stub:   ld      a,GBPAGE                ; (en C000h) pagina 0 = GameBios
        ld      bc,7C00h
        out     (c),a
        db      3Eh                     ; LD A,n
q1init: db      0C0h                    ;   pagina inicial de 4000h (banco 0 + 1)
        ld      b,7Dh
        out     (c),a
        db      3Eh
q2init: db      0C0h                    ;   pagina inicial de 8000h (bancos 2 + 3)
        ld      b,7Eh
        out     (c),a
        ld      sp,0F380h
        im      1
        ld      hl,(4002h)
        jp      (hl)
stubend:

error:  ld      de,msg_err
        ld      c,09h
        call    BDOS
        rst     0

msg_load: db    "Cargando...",13,10,"$"
msg_err:  db    "Error al leer el juego",13,10,"$"
bank:   db      0

; ---- parametros (los rellena la herramienta)
param:
fcb:    db      0,"JUEGO   DAT"
        ds      25,0
p_gb:     dw    0                       ; GameBios
p_gblen:  dw    0
p_t3e:    dw    0                       ; tablas
p_t3f:    dw    0
p_t2f:    dw    0
p_bank:   dw    0                       ; rutina de bancos
p_banklen: dw   0
dest:   ds      16*11,0
fin:
