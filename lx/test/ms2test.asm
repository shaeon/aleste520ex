; ms2test.asm - Prueba de la Magic Sound 2 del modo LX (rtl/lx/lx_ms2.sv)
; Canal 0: onda cuadrada de 8 bits (256 muestras, +-64) en bucle, paso 1.0,
; con interrupcion de fin de muestra; temporizador de la MS2 a 300 Hz.
; Contadores (manejador de IM 1):
;   3F10  A5 cuando empieza el bucle
;   3F12  fines de muestra (16 bits)
;   3F14  ticks del temporizador de la MS2 (16 bits)
; La muestra esta en la imagen en 8000h: en modo LX es la direccion fisica 418000h.
P_MMIOPG    equ 0F1h
PIC_MASKLO  equ 00h
PIC_STATLO  equ 03h
PIC_CLRLO   equ 07h
MS2_CTRL    equ 00h
MS2_IRQC    equ 04h
MS2_IRQS    equ 05h
MS2_STAT    equ 03h
MS2_TMRLO   equ 10h
MS2_TMRHI   equ 11h
CH0         equ 20h
VARS        equ 3F10h
SAMPLE      equ 8000h
PHYS_HI     equ 41h             ; 418000h

            org 0
            di
            jp start
            ds 38h-$
irq:        push af
            push hl
            ld a, 7
            out (P_MMIOPG), a
            in a, (MS2_IRQS)
            out (MS2_IRQS), a           ; borra en la MS2
            bit 0, a
            jr z, no_eof
            ld hl, (VARS+2)
            inc hl
            ld (VARS+2), hl
no_eof:     bit 1, a
            jr z, no_tmr
            ld hl, (VARS+4)
            inc hl
            ld (VARS+4), hl
no_tmr:     ld a, 0
            out (P_MMIOPG), a
            ld a, 08h                   ; linea 3 (AUDIO) del PIC
            out (PIC_CLRLO), a
            pop hl
            pop af
            ei
            reti

start:      ld sp, 3F00h
            ld hl, VARS
            ld b, 16
clr:        ld (hl), 0
            inc hl
            djnz clr
            ld a, 7
            out (P_MMIOPG), a
            ld a, 1
            out (MS2_CTRL), a           ; MS2 en marcha
            ld a, 03h
            out (MS2_IRQC), a           ; IRQ de fin y de temporizador
            ld a, 160                   ; 300 Hz
            out (MS2_TMRLO), a
            xor a
            out (MS2_TMRHI), a
            ; canal 0
            ld a, low SAMPLE
            out (CH0+1), a
            ld a, high SAMPLE
            out (CH0+2), a
            ld a, PHYS_HI
            out (CH0+3), a              ; START
            ld a, low (SAMPLE+256)
            out (CH0+4), a
            ld a, high (SAMPLE+256)
            out (CH0+5), a
            ld a, PHYS_HI
            out (CH0+6), a              ; END
            ld a, low SAMPLE
            out (CH0+7), a
            ld a, high SAMPLE
            out (CH0+8), a
            ld a, PHYS_HI
            out (CH0+9), a              ; LOOP
            ld a, 0FFh
            out (CH0+0Ah), a
            out (CH0+0Bh), a            ; volumen
            xor a
            out (CH0+0Ch), a
            out (CH0+0Dh), a
            ld a, 1
            out (CH0+0Eh), a            ; paso 1.0
            ld a, 1011b                 ; suena, bucle, 8 bits, IRQ al terminar
            out (CH0+0), a
            xor a
            out (P_MMIOPG), a
            ld a, 08h                   ; PIC: linea 3
            out (PIC_MASKLO), a
            im 1
            ld a, 0A5h
            ld (VARS), a
            ei
loop:       jr loop

            ds SAMPLE-$
            rept 128
            db 64
            endm
            rept 128
            db -64
            endm
            ds 10000h-$
