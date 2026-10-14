; =============================================================================
; diag.asm - ROM de diagnostico de la fase 2 (Aleste LX en placas MiST)
;
; Se carga desde la SD (DIAG.ROM con "Reload ROM", o renombrada ALESTE.ROM) en 0xC00000. Tras el reset la MMU
; nativa pone las cuatro paginas del Z80 en el slot 3, banco 0, asi que la
; CPU empieza a ejecutar aqui en 0000h, en modo supervisor.
;
; Hace en la placa lo que el Aleste LX comprobaba con sus programas de prueba
; y el puente UART, pero ensenando el resultado en pantalla:
;   - pone el modo 160x200 de 16 colores y una paleta por MMIO (CRTC y paleta
;     en la pagina MMIO 2 = FF0100)
;   - Z80:  llega hasta aqui y ejecuta
;   - MMU:  lee y escribe registros de la MMU
;   - RAM:  escribe y comprueba muestras de 3 MB de SDRAM a traves del mapper
;   - MMIO: lee registros del CRTC y de la paleta
;   - un contador que no para (la CPU sigue viva)
; Los resultados quedan tambien en RESULTS (C03F10h) para el banco de pruebas.
;
; Ensamblar:  pasmo --bin diag.asm DIAG.ROM   (ver Makefile)
; =============================================================================

; ---- Puertos de la MMU nativa (rtl/mmu_native.sv) ---------------------------
P_CTRL      equ 0F0h        ; control: [0] supervisor [1] nativo [4] mmio desbloqueado
P_MMIOPG    equ 0F1h        ; pagina MMIO (128 bytes) que ve la ventana 00-7Fh
P_SSLOT     equ 0FAh        ; slots del supervisor: 2 bits por pagina del Z80
P_BANK0     equ 0FCh        ; banco de la pagina 0 en el slot que tenga
P_BANK1     equ 0FDh
P_BANK2     equ 0FEh
P_BANK3     equ 0FFh

; ---- Dispositivos en la pagina MMIO 2 (FF0100) ------------------------------
MMIO_PAGE   equ 2
PAL_IDX     equ 00h         ; paleta: indice
PAL_LO      equ 01h         ;         G,B (se guarda)
PAL_HI      equ 02h         ;         R (escribe la entrada en modo 12 bits)
PAL_BLO     equ 03h         ;         borde G,B
PAL_BHI     equ 04h         ;         borde R
PAL_CTRL    equ 05h         ;         control (0 = 12 bits, sin autoincremento)
CRTC_IDX    equ 20h         ; CRTC:   indice
CRTC_DAT    equ 21h         ;         dato

; ---- Mapa de memoria que se monta ---------------------------------------------
; pagina 0 (0000-3FFF): slot 3 banco 0 = esta ROM (C00000)
; pagina 1 (4000-7FFF): slot 0 banco 0 = pantalla (000000)
; pagina 2 (8000-BFFF): ventana para la prueba de RAM
; pagina 3 (C000-FFFF): slot 3 banco 0 = alias de la ROM (pila al final)
SSLOT_BASE  equ 11000011b   ; pag3=3 pag2=0 pag1=0 pag0=3
SCR         equ 4000h
WAIT_N      equ 2           ; vueltas de 65536 entre incrementos del contador
WIN         equ 8000h

; ---- Variables (al final del banco de la ROM, por debajo de la pila) --------
VARS        equ 3F00h
INK_HI      equ VARS+0
INK_LO      equ VARS+1
COUNTER     equ VARS+2      ; 2 bytes
TMP         equ VARS+4
RESULTS     equ 3F10h       ; +1 Z80, +2 MMU, +3 RAM, +4 MMIO: 1 = OK, 2 = FALLO (banco de pruebas)
R_MAGIC     equ RESULTS+0   ; 0A5h cuando las pruebas han terminado

; ---- Colores (paleta de prueba, igual que sd/BARS.WBS) ----------------------
C_BLACK     equ 0
C_GREY      equ 7
C_DGREY     equ 8
C_GREEN     equ 10
C_CYAN      equ 11
C_RED       equ 12
C_YELLOW    equ 14
C_WHITE     equ 15

; Posicion de texto: 20 columnas x 25 filas de 8x8 (160x200, 80 bytes/linea)
AT          macro row, col
            ld de, SCR + (row) * 640 + (col) * 4
            endm

; =============================================================================
            org 0
start:
            di
            ld sp, 0                ; la pila crece desde FFFF (fin del banco)

            xor a
            ld (R_MAGIC), a

            ; --- mapa de memoria
            ld a, SSLOT_BASE
            out (P_SSLOT), a
            xor a
            out (P_BANK1), a        ; slot 0, pagina 1 -> banco 0 = 000000

            ; --- dispositivos
            ld a, MMIO_PAGE
            out (P_MMIOPG), a
            call crtc_init
            call pal_init
            call cls

            ; --- cabecera
            ld a, C_YELLOW
            call set_ink
            AT 1, 5
            ld hl, txt_title
            call print
            ld a, C_CYAN
            call set_ink
            AT 3, 1
            ld hl, txt_sub
            call print

            ; --- Z80: si estamos aqui, ejecuta
            AT 6, 1
            ld hl, txt_z80
            ld a, 1
            ld (RESULTS+1), a
            call show_result

            ; --- MMU
            call test_mmu
            ld (RESULTS+2), a
            AT 8, 1
            ld hl, txt_mmu
            call show_result

            ; --- RAM
            call test_ram
            ld (RESULTS+3), a
            AT 10, 1
            ld hl, txt_ram
            call show_result

            ; --- MMIO
            call test_mmio
            ld (RESULTS+4), a
            AT 12, 1
            ld hl, txt_mmio
            call show_result

            ; --- muestra de colores
            call color_bars

            ld a, 0A5h
            ld (R_MAGIC), a

            ; --- contador: la CPU sigue viva
            ld a, C_GREY
            call set_ink
            AT 16, 1
            ld hl, txt_count
            call print
            ld hl, 0
            ld (COUNTER), hl
main_loop:
            ld hl, (COUNTER)
            inc hl
            ld (COUNTER), hl
            ld a, C_WHITE
            call set_ink
            AT 16, 11
            call print_hex16
            ld b, WAIT_N            ; espera: el numero cambia a un ritmo legible
wait_outer:
            push bc
            ld bc, 0
wait_inner:
            dec bc
            ld a, b
            or c
            jr nz, wait_inner
            pop bc
            djnz wait_outer
            jr main_loop

; =============================================================================
; Dispositivos
; =============================================================================

; Modo 160x200x16 (preset "16k4b" del Aleste LX)
crtc_init:
            ld hl, crtc_table
crtc_loop:
            ld a, (hl)
            cp 0FFh
            ret z
            out (CRTC_IDX), a
            inc hl
            ld a, (hl)
            out (CRTC_DAT), a
            inc hl
            jr crtc_loop

crtc_table:
            defb 0, 63, 1, 40, 2, 46, 3, 08Eh, 4, 38, 5, 0, 6, 25, 7, 30
            defb 8, 0, 9, 7, 12, 0, 13, 0
            defb 18, 012h           ; R18: 4 bpp, pixeles lineales
            defb 20, 001h           ; R20: direccionamiento lineal
            defb 21, 000h           ; R21
            defb 0FFh

; Paleta de 16 colores en modo de 12 bits (R4G4B4), borde negro
pal_init:
            xor a
            out (PAL_CTRL), a
            ld hl, palette
            ld b, 0
pal_loop:
            ld a, b
            out (PAL_IDX), a
            ld a, (hl)              ; G,B
            out (PAL_LO), a
            inc hl
            ld a, (hl)              ; R
            out (PAL_HI), a
            inc hl
            inc b
            ld a, b
            cp 16
            jr nz, pal_loop
            xor a
            out (PAL_BLO), a
            out (PAL_BHI), a
            ret

palette:    ; {G<<4|B, R}
            defb 000h,0, 00Ah,0, 0A0h,0, 0AAh,0, 000h,0Ah, 00Ah,0Ah, 050h,0Ah, 0AAh,0Ah
            defb 055h,5, 05Fh,5, 0F5h,5, 0FFh,5, 055h,0Fh, 05Fh,0Fh, 0F5h,0Fh, 0FFh,0Fh

; Borra la pantalla (16 KB a 0)
cls:
            ld hl, SCR
            ld de, SCR + 1
            ld bc, 16383
            ld (hl), 0
            ldir
            ret

; =============================================================================
; Pruebas: devuelven A = 1 (bien) o 2 (mal)
; =============================================================================

; MMU: los registros se leen como se escribieron
test_mmu:
            in a, (P_SSLOT)
            cp SSLOT_BASE
            jr nz, mmu_bad
            in a, (P_MMIOPG)
            and 7Fh
            cp MMIO_PAGE
            jr nz, mmu_bad
            ld a, 5Ah               ; banco de la pagina 2 (slot 0)
            out (P_BANK2), a
            in a, (P_BANK2)
            cp 5Ah
            jr nz, mmu_bad
            ld a, 21h
            out (P_BANK2), a
            in a, (P_BANK2)
            cp 21h
            jr nz, mmu_bad
            ld a, 1
            ret
mmu_bad:
            ld a, 2
            ret

; RAM: por la pagina 2 recorre los bancos 1-63 del slot 0 y 0-63 de los
; slots 1 y 2 (3 MB), escribe 4 bytes en cada uno y luego los comprueba. Las
; dos pasadas detectan bancos que se pisan entre si.
test_ram:
            xor a
            ld (TMP), a             ; TMP = 1 si algun byte no coincide
            ld c, 0                 ; pasada 0 = escribir, 1 = comprobar
ram_pass:
            ld d, 0                 ; slot
ram_slot:
            ld a, d                 ; slots: pagina 2 = d
            add a, a
            add a, a
            add a, a
            add a, a
            or SSLOT_BASE & 11001111b
            out (P_SSLOT), a
            ld e, 0                 ; banco
            ld a, d
            or a
            jr nz, ram_bank
            inc e                   ; slot 0: el banco 0 es la pantalla
ram_bank:
            ld a, e
            out (P_BANK2), a
            ; valor = banco ^ slot*64 ^ 5Ah, y variaciones por direccion
            ld a, d
            rrca
            rrca
            xor e
            xor 5Ah
            ld b, a
            ld hl, WIN
            call ram_cell
            ld hl, WIN + 1555h
            call ram_cell
            ld hl, WIN + 2AAAh
            call ram_cell
            ld hl, WIN + 3FFFh
            call ram_cell
            inc e
            ld a, e
            cp 64
            jr nz, ram_bank
            inc d
            ld a, d
            cp 3
            jr nz, ram_slot
            inc c
            ld a, c
            cp 2
            jr nz, ram_pass
            ld a, (TMP)
            or a
            jr nz, ram_bad
            ld a, SSLOT_BASE        ; dejar el mapa como estaba
            out (P_SSLOT), a
            ld a, 1
            ret
ram_bad:
            ld a, SSLOT_BASE
            out (P_SSLOT), a
            ld a, 2
            ret

; Escribe (pasada 0) o comprueba (pasada 1) B ^ L en (HL). Si no coincide
; pone TMP = 1.
ram_cell:
            ld a, b
            xor l
            bit 0, c
            jr nz, ram_check
            ld (hl), a
            xor a                   ; Z = 1
            ret
ram_check:
            cp (hl)
            ret z
            ld a, 1
            ld (TMP), a
            or a                    ; Z = 0
            ret

; MMIO: lectura del CRTC (R1 = 40) y de la paleta (entrada 9, byte bajo)
test_mmio:
            ld a, 1
            out (CRTC_IDX), a
            in a, (CRTC_DAT)
            ld (RESULTS+5), a       ; lo leido, para el banco de pruebas
            cp 40
            jr nz, mmio_bad
            ld a, 9
            out (PAL_IDX), a
            in a, (PAL_LO)
            ld (RESULTS+6), a
            cp 05Fh
            jr nz, mmio_bad
            ld a, 1
            ret
mmio_bad:
            ld a, 2
            ret

; =============================================================================
; Pantalla
; =============================================================================

; A = color de tinta (1-15)
set_ink:
            ld (INK_LO), a
            add a, a
            add a, a
            add a, a
            add a, a
            ld (INK_HI), a
            ret

; HL = texto, DE = posicion, A = 1 bien / 2 mal. Escribe "texto .... OK"
show_result:
            push af
            push de
            ld a, C_GREY
            call set_ink
            call print
            pop de
            ld hl, 13 * 4           ; columna 14 del renglon
            add hl, de
            ex de, hl
            pop af
            cp 1
            jr nz, show_bad
            ld a, C_GREEN
            call set_ink
            ld hl, txt_ok
            jp print
show_bad:
            ld a, C_RED
            call set_ink
            ld hl, txt_bad
            jp print

; HL = texto acabado en 0, DE = posicion en pantalla
print:
            ld a, (hl)
            or a
            ret z
            push hl
            push de
            call draw_char
            pop de
            pop hl
            inc hl
            inc de                  ; siguiente columna: 4 bytes
            inc de
            inc de
            inc de
            jr print

; A = caracter (20h-5Fh), DE = posicion. 8 lineas de 4 bytes (2 pixeles por
; byte, el de la izquierda en el nibble alto).
draw_char:
            sub 20h
            ld l, a
            ld h, 0
            add hl, hl
            add hl, hl
            add hl, hl
            ld bc, font
            add hl, bc
            ld b, 8
dc_row:
            ld c, (hl)
            inc hl
            push hl
            push bc
            ld b, 4
dc_pix:
            xor a
            sla c
            jr nc, dc_left0
            ld a, (INK_HI)
dc_left0:
            ld h, a
            xor a
            sla c
            jr nc, dc_right0
            ld a, (INK_LO)
dc_right0:
            or h
            ld (de), a
            inc de
            djnz dc_pix
            pop bc
            ld hl, 76               ; a la linea siguiente: 80 - 4
            add hl, de
            ex de, hl
            pop hl
            djnz dc_row
            ret

; HL = valor, DE = posicion: 4 cifras hexadecimales
print_hex16:
            ld a, h
            call print_hex8
            ld a, l
print_hex8:
            push af
            rrca
            rrca
            rrca
            rrca
            call print_nibble
            pop af
print_nibble:
            and 0Fh
            add a, '0'
            cp '9' + 1
            jr c, pn_digit
            add a, 'A' - '9' - 1
pn_digit:
            push hl
            push de
            call draw_char
            pop de
            pop hl
            inc de
            inc de
            inc de
            inc de
            ret

; Muestra de los 16 colores (filas 20-23)
color_bars:
            ld de, SCR + 20 * 640
            ld c, 32                ; 32 lineas de pixel
cb_line:
            xor a                   ; color 0..15, 5 bytes (10 pixeles) cada uno
cb_color:
            ld b, a
            add a, a
            add a, a
            add a, a
            add a, a
            or b
            ld h, 5
cb_byte:
            ld (de), a
            inc de
            dec h
            jr nz, cb_byte
            ld a, b
            inc a
            cp 16
            jr nz, cb_color
            dec c
            jr nz, cb_line
            ret

; =============================================================================
txt_title:  defb "ALESTE LX", 0
txt_sub:    defb "FASE 2: Z80 Y MMU", 0
txt_z80:    defb "Z80", 0
txt_mmu:    defb "MMU", 0
txt_ram:    defb "RAM 3MB", 0
txt_mmio:   defb "MMIO", 0
txt_ok:     defb "OK", 0
txt_bad:    defb "FALLO", 0
txt_count:  defb "CONTADOR", 0

font:
            include "font.inc"
rom_end:
