; pictest.asm - Prueba del PIC y del temporizador del modo LX (rtl/lx/lx_sys.sv)
; Se carga como imagen LX (64 KB, la CPU la ve en 0000-FFFF en modo nativo).
; Programa el temporizador a 1 ms periodico, habilita en el PIC las lineas
; 6 (SYSTIMER) y 2 (GPU, VBlank) y cuenta en el manejador de IM 1:
;   3F10  A5 cuando arranca el bucle
;   3F12  ticks del temporizador (16 bits)
;   3F14  VBlanks (16 bits)
;   3F16  otras interrupciones (16 bits)
; pasmo --bin pictest.asm PICTEST.ROM
P_MMIOPG    equ 0F1h
PIC_MASKLO  equ 00h
PIC_STATLO  equ 03h
PIC_CLRLO   equ 07h
TMR_CTRL    equ 40h
TMR_RELLO   equ 41h
TMR_RELHI   equ 42h
VARS        equ 3F10h

            org 0
            di
            jp start
            ds 38h-$
; ---- IM 1
irq:        push af
            push hl
            ld a, 0
            out (P_MMIOPG), a
            in a, (PIC_STATLO)
            out (PIC_CLRLO), a          ; borra lo que se atiende
            bit 6, a
            jr z, no_tmr
            ld hl, (VARS+2)
            inc hl
            ld (VARS+2), hl
no_tmr:     bit 2, a
            jr z, no_vbl
            ld hl, (VARS+4)
            inc hl
            ld (VARS+4), hl
no_vbl:     and 10111011b
            jr z, irq_end
            ld hl, (VARS+6)
            inc hl
            ld (VARS+6), hl
irq_end:    pop hl
            pop af
            ei
            reti

start:      ld sp, 3F00h
            ld hl, VARS
            ld b, 16
clr:        ld (hl), 0
            inc hl
            djnz clr
            xor a
            out (P_MMIOPG), a
            ld a, 0E8h                  ; 1000 us
            out (TMR_RELLO), a
            ld a, 03h
            out (TMR_RELHI), a
            ld a, 03h                   ; marcha + periodico
            out (TMR_CTRL), a
            ld a, 01000100b             ; lineas 6 y 2
            out (PIC_MASKLO), a
            im 1
            ld a, 0A5h
            ld (VARS), a
            ei
loop:       jr loop
            ds 10000h-$
