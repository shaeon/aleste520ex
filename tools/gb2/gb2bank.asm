; ============================================================================
; gb2bank.asm - Rutina de bancos para la GameBios v2 (en 0E00h, pagina 0).
; Sustituye a las escrituras al mapper de Konami (LD (6000h/8000h/A000h),A):
; el juego hace CALL BANK6/BANK8/BANKA con el banco en A. Pone en el cuarto
; del Aleste la pagina compuesta (banco 0 + banco de 6000h; banco de 8000h +
; banco de A000h) de las tablas Q1TAB / Q2TAB (C0h + pagina; las rellena la
; herramienta). Conserva registros e indicadores.
; ============================================================================
        org     0E00h
BANK6:  push    af
        push    bc
        push    hl
        and     0Fh
        ld      (cur6),a
        ld      hl,q1tab
        ld      c,a
        ld      b,0
        add     hl,bc
        ld      a,(hl)
        ld      bc,7D00h
        out     (c),a
        pop     hl
        pop     bc
        pop     af
        ret
BANK8:  push    af
        push    bc
        push    hl
        and     0Fh
        ld      (cur8),a
        jr      setq2
BANKA:  push    af
        push    bc
        push    hl
        and     0Fh
        ld      (curA),a
setq2:  ld      a,(cur8)
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        ld      c,a
        ld      a,(curA)
        or      c
        ld      c,a
        ld      b,0
        ld      hl,q2tab
        add     hl,bc
        ld      a,(hl)
        ld      bc,7E00h
        out     (c),a
        pop     hl
        pop     bc
        pop     af
        ret
cur6:   db      1
cur8:   db      2
curA:   db      3
q1tab:  ds      16,0
q2tab:  ds      256,0
fin:
