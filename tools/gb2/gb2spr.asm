; ============================================================================
; gb2spr.asm - Limite de 8 sprites por linea para la GameBios v2 (0F70h, en
; la pagina de la GameBios). Se llama antes de cada redibujado (CALL 0003h).
;
; Copia la lista de sprites del juego (SRC, 32 x 4 bytes) a una intermedia
; (DST, 1200h) que es la que lee la GameBios. Por orden de prioridad, como el
; VDP: un sprite que cae en una linea del tramo LO..HI que ya tiene 8 sprites
; se oculta entero (Y = E0h); Y = D8h termina la lista (modo 2 del MSX2).
; Solo se cuentan las lineas LO..HI (por coste): los juegos usan el truco en
; zonas concretas (Metal Gear: el marcador, lineas 192-211). Sprites de 16
; lineas. La herramienta rellena SRC, LO y HI.
; ============================================================================
CNT     equ     1100h                   ; contadores por linea (indice = linea)
DST     equ     1200h

        org     0F68h
term:   db      0
        ds      7,0
        ; 0F70h
SPRLIM: push    af
        push    bc
        push    de
        push    hl
        push    ix
        db      21h                     ; LD HL,SRC
src:    dw      0EA00h
        ld      ix,DST
        xor     a
        ld      (term),a
        ld      de,CNT
        db      1Eh                     ; LD E,LO
lo1:    db      0C0h
        db      3Eh                     ; LD A,HI+1
hi1:    db      0D4h
        sub     e
        ld      b,a
        xor     a
clr:    ld      (de),a                  ; contadores LO..HI a cero
        inc     e
        djnz    clr
        ld      c,32
nexts:  ld      a,(hl)                  ; Y
        ld      b,a
        ld      a,(term)
        or      a
        jr      nz,hide
        ld      a,b
        cp      0D8h                    ; fin de lista
        jr      nz,chk
        ld      a,1
        ld      (term),a
        jr      hide
chk:    ld      a,b                     ; descarte rapido: t = (Y + 1 - LO) mod 256
        inc     a
        db      0D6h                    ; SUB LO
lo4:    db      0C0h
        db      0FEh                    ; CP N (= HI - LO + 1): empieza dentro del tramo
nlin:   db      20
        jr      c,inside
        cp      0F1h                    ; empieza hasta 15 lineas antes del tramo
        jr      nc,inside
        ld      a,b                     ; no toca el tramo: tal cual
        jr      store
inside: push    bc
        ld      a,b
        inc     a
        ld      e,a                     ; E = primera linea (Y + 1)
        ld      b,16
p1:     ld      a,e
        db      0FEh                    ; CP LO
lo2:    db      0C0h
        jr      c,s1
        db      0FEh                    ; CP HI+1
hi2:    db      0D4h
        jr      nc,s1
        ld      d,CNT/256
        ld      a,(de)
        cp      8
        jr      nc,full                 ; linea llena: oculto
s1:     inc     e
        djnz    p1
        pop     bc                      ; cabe: cuenta sus lineas
        push    bc
        ld      a,b
        inc     a
        ld      e,a
        ld      b,16
p2:     ld      a,e
        db      0FEh
lo3:    db      0C0h
        jr      c,s2
        db      0FEh
hi3:    db      0D4h
        jr      nc,s2
        ld      d,CNT/256
        ld      a,(de)
        inc     a
        ld      (de),a
s2:     inc     e
        djnz    p2
        pop     bc
        ld      a,b
        jr      store
full:   pop     bc
hide:   ld      a,0E0h
store:  ld      (ix+0),a
        inc     hl
        ld      a,(hl)
        ld      (ix+1),a
        inc     hl
        ld      a,(hl)
        ld      (ix+2),a
        inc     hl
        ld      a,(hl)
        ld      (ix+3),a
        inc     hl
        ld      de,4
        add     ix,de
        dec     c
        jr      nz,nexts
        pop     ix
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret
fin:
