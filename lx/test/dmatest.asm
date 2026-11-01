; dmatest.asm - Prueba de la DMA / blitter del modo LX (rtl/lx/lx_dma.sv)
; 1) relleno de 8x3 bytes con 55h en 010000h, paso de destino 16
; 2) copia 2D de 4x2 bytes desde la imagen (8000h = 418000h fisica) a 010040h
;    (paso origen 4, destino 16)
; 3) copia con transparente (KEY = 00h) de los mismos datos encima de 010080h
;    relleno antes con EEh (ancho 4, alto 2)
; Cada paso espera la interrupcion de fin (linea 1 del PIC) y cuenta en 3F12.
; 3F10 = A5 al acabar.
P_MMIOPG    equ 0F1h
PIC_MASKLO  equ 00h
PIC_CLRLO   equ 07h
VARS        equ 3F10h
SAMPLE      equ 8000h

            org 0
            di
            jp start
            ds 38h-$
irq:        push af
            push hl
            ld a, 6
            out (P_MMIOPG), a
            ld a, 1
            out (01h), a                ; borra el fin en la DMA
            xor a
            out (P_MMIOPG), a
            ld a, 02h
            out (PIC_CLRLO), a
            ld hl, (VARS+2)
            inc hl
            ld (VARS+2), hl
            pop hl
            pop af
            ei
            reti

; HL -> tabla de 15 bytes (02..10), A = CTRL
dma_go:     push af
            ld a, 6                     ; el manejador deja la pagina 0
            out (P_MMIOPG), a
            ld c, 02h
            ld b, 15
dg_lp:      ld a, (hl)
            out (c), a                  ; (OTIR no avanza el puerto)
            inc hl
            inc c
            djnz dg_lp
            pop af
            out (00h), a
            ld hl, (VARS+2)
wait:       ei
            halt                        ; hasta la interrupcion
            di
            ld de, (VARS+2)
            or a
            sbc hl, de
            add hl, de
            jr z, wait
            ret

start:      ld sp, 3F00h
            ld hl, VARS
            ld b, 16
clr:        ld (hl), 0
            inc hl
            djnz clr
            xor a
            out (P_MMIOPG), a
            ld a, 02h
            out (PIC_MASKLO), a
            im 1
            ld a, 6
            out (P_MMIOPG), a
            ld hl, t_fill
            ld a, 1011b                 ; relleno, IRQ
            call dma_go
            ld hl, t_copy
            ld a, 1001b                 ; copia, IRQ
            call dma_go
            ld hl, t_fill2
            ld a, 1011b
            call dma_go
            ld hl, t_key
            ld a, 1101b                 ; copia con transparente, IRQ
            call dma_go
            ld a, 0A5h
            ld (VARS), a
            halt

;            SRC(3)          DST(3)          W    H    SS   DS   KEY
t_fill:     db 0,0,0,        00h,00h,01h,    8,0, 3,0, 0,0, 16,0, 55h
t_copy:     db 00h,80h,41h,  40h,00h,01h,    4,0, 2,0, 4,0, 16,0, 0
t_fill2:    db 0,0,0,        80h,00h,01h,    4,0, 2,0, 0,0, 16,0, 0EEh
t_key:      db 00h,80h,41h,  80h,00h,01h,    4,0, 2,0, 4,0, 16,0, 00h

            ds SAMPLE-$
            db 11h, 00h, 33h, 44h,  55h, 66h, 00h, 88h
            ds 10000h-$
