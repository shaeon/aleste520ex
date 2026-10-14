; ============================================================================
; TIME.COM - Muestra o cambia la hora en MSX-DOS 1 (Aleste 520EX)
;
; El COMMAND.COM 2.2A del 520EX no tiene TIME (solo DATE). Este programa usa
; las funciones de la BDOS:
;     2Ch  leer la hora:  H = horas, L = minutos, D = segundos
;     2Dh  poner la hora: H, L, D (y E = centesimas); A = 0 si es valida
; La BIOS del 520EX las lleva al reloj MC146818.
;
;   TIME              muestra la hora
;   TIME hh:mm        la cambia (segundos a 0)
;   TIME hh:mm:ss     la cambia
;
; Ensamblar:  pasmo --bin time.asm TIME.COM
; ============================================================================
BDOS    equ     0005h
CMDLIN  equ     0080h

        org     0100h

        ld      hl,CMDLIN
        ld      b,(hl)                  ; longitud de la linea de ordenes
        inc     hl
skip:   ld      a,b
        or      a
        jr      z,show                  ; sin parametros: mostrar
        ld      a,(hl)
        cp      ' '
        jr      nz,parse
        inc     hl
        dec     b
        jr      skip

; ---- TIME hh:mm[:ss]
parse:  call    num                     ; horas
        jr      c,bad
        cp      24
        jr      nc,bad
        ld      (hour),a
        call    sep
        jr      nz,bad
        call    num                     ; minutos
        jr      c,bad
        cp      60
        jr      nc,bad
        ld      (minute),a
        xor     a
        ld      (second),a
        ld      a,b
        or      a
        jr      z,setit
        call    sep
        jr      nz,bad
        call    num                     ; segundos
        jr      c,bad
        cp      60
        jr      nc,bad
        ld      (second),a
setit:  ld      a,(hour)
        ld      h,a
        ld      a,(minute)
        ld      l,a
        ld      a,(second)
        ld      d,a
        ld      e,0
        ld      c,2Dh
        call    BDOS
        or      a
        jr      nz,bad
show:   ld      c,2Ch
        call    BDOS                    ; H horas, L minutos, D segundos
        push    de
        push    hl
        ld      de,msg
        ld      c,09h
        call    BDOS
        pop     hl
        push    hl
        ld      a,h
        call    pr2
        ld      e,':'
        call    putc
        pop     hl
        ld      a,l
        call    pr2
        ld      e,':'
        call    putc
        pop     de
        ld      a,d
        call    pr2
        ld      de,crlf
        ld      c,09h
        jp      BDOS

bad:    ld      de,errmsg
        ld      c,09h
        jp      BDOS

; ---- numero decimal de 1 o 2 cifras en (HL), B caracteres restantes -> A; C=1 si error
num:    ld      a,b
        or      a
        scf
        ret     z
        ld      a,(hl)
        sub     '0'
        ret     c
        cp      10
        ccf
        ret     c
        ld      c,a                     ; primera cifra
        inc     hl
        dec     b
        ld      a,b
        or      a
        ld      a,c
        ret     z
        ld      a,(hl)
        sub     '0'
        jr      c,num1
        cp      10
        jr      nc,num1
        ld      e,a                     ; segunda cifra: C*10 + E
        ld      a,c
        add     a,a
        ld      c,a
        add     a,a
        add     a,a
        add     a,c
        add     a,e
        inc     hl
        dec     b
        or      a                       ; C=0
        ret
num1:   ld      a,c
        or      a
        ret

; ---- separador ':' o '.'; Z=1 si lo hay
sep:    ld      a,b
        or      a
        jr      z,sepno
        ld      a,(hl)
        cp      ':'
        jr      z,sepok
        cp      '.'
        jr      nz,sepno
sepok:  inc     hl
        dec     b
        xor     a
        ret
sepno:  or      1
        ret

; ---- A (0-99) en dos cifras
pr2:    ld      c,'0'-1
pr2a:   inc     c
        sub     10
        jr      nc,pr2a
        add     a,10+'0'
        push    af
        ld      e,c
        call    putc
        pop     af
        ld      e,a
putc:   ld      c,02h
        jp      BDOS

msg:    db      'Current time is $'
crlf:   db      13,10,'$'
errmsg: db      'Invalid time (TIME hh:mm[:ss])',13,10,'$'
hour:   db      0
minute: db      0
second: db      0
