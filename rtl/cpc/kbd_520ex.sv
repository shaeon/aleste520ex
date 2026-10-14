// ============================================================================
// kbd_520ex.sv - Teclado PS/2 a la matriz del Aleste 520EX
//
// La matriz es la del CPC (filas 0-9) mas la fila 10 propia del 520EX
// (Aleste520EX/Documentation/programming-en.txt y CPCWiki, "Aleste 520EX -
// I/O Ports"). La CPU la lee como en el CPC: PC3..PC0 de la PPI eligen la
// fila y el dato entra por el puerto A del AY (registro 14), activo a 0.
//
//  fila  D7      D6      D5      D4      D3      D2      D1      D0
//   0    f.      ENTER   f3      f6      f9      ABAJO   DCHA    ARRIBA
//   1    f0      f2      f1      f5      f8      f7      ALT     IZQDA
//   2    CTRL    \       SHIFT   f4      ]       RETURN  [       BS(CLR)
//   3    .       /       :       ;       P       @       -       ^
//   4    ,       M       K       L       I       O       9       0
//   5    ESPACIO N       J       H       Y       U       7       8
//   6    V       B       F       G       T       R       5       6
//   7    X       C       D       S       W       E       3       4
//   8    Z       CAPS    A       TAB     Q       ESC     2       1
//   9    DEL     R/L     J.F1    J.F2    J.DCHA  J.IZQDA J.ABAJO J.ARRIBA
//  10    Ъ       INS     HELP    F5/F10  F4/F9   F3/F8   F2/F7   F1/F6
//         (fila 10: F1 en el bit 0, como lee el SETUP del BOOTMENU -
//          "LD D,10 / BIT 0,E ;F1" - y como define MAME; la tabla del manual
//          de programacion tiene esta fila al reves)
//
// Teclado del PC (como en los cores de CPC de MiST, con la disposicion
// del CPC en la fila de simbolos):
//   F1-F5 -> F1-F5 del 520EX; F6-F10 -> SHIFT + F1-F5 (el 520EX las saca asi)
//   F11 -> HELP, Fin (End) -> Ъ, Insert -> INS, Alt -> ALT (COPY del CPC)
//   F12 abre el OSD del firmware MiST: no se usa y, al pulsarla, se sueltan
//   todas las teclas (la tecla soltada con el OSD abierto no llega al core
//   y se quedaba pulsada).
//   ` (a la izquierda del 1) y AltGr -> R/L (cambio ruso/latino)
//   teclado numerico -> f0-f9, f. y ENTER; Supr -> BS (CLR); Retroceso -> DEL
//   '=' -> ^, '[' -> @, ']' -> [, '\' -> ], ''' -> ;, ';' -> :
// Joystick 1 de MiST -> fila 9.
// ============================================================================
`default_nettype none

module kbd_520ex (
    input  logic        clk,
    input  logic        reset,

    // user_io
    input  logic        key_strobe,
    input  logic        key_pressed,
    input  logic        key_extended,
    input  logic [7:0]  key_code,
    input  logic [7:0]  joystick,       // MiST: 0 dcha, 1 izqda, 2 abajo, 3 arriba, 4 fuego 1, 5 fuego 2

    input  logic        force_shift,    // SHIFT pulsado (arranque en modo AMSTRAD)
    input  logic        force_bs,       // BS pulsado (arranque en el SETUP del 520EX)
    output logic        res_key,        // tecla RES del 520EX (Bloq Despl): reset mientras se pulsa

    input  logic [3:0]  row,            // PC3..PC0 de la PPI
    output logic [7:0]  cols            // activo a 0
);

logic [7:0] key [0:10];
logic       fshift;                     // SHIFT de F6-F10

always_ff @(posedge clk) begin
    if (reset) begin
        for (int i = 0; i <= 10; i++) key[i] <= '0;
        fshift <= 1'b0;
        res_key <= 1'b0;
    end else if (key_strobe && !key_extended && key_code == 8'h07) begin
        // F12: el firmware abre el OSD y la soltada de las teclas pulsadas no
        // llegara al core: se sueltan todas ahora
        for (int i = 0; i <= 10; i++) key[i] <= '0;
        fshift <= 1'b0;
    end else if (key_strobe) begin
        if (key_extended) begin
            case (key_code)
                8'h75: key[0][0]  <= key_pressed;   // arriba
                8'h74: key[0][1]  <= key_pressed;   // derecha
                8'h72: key[0][2]  <= key_pressed;   // abajo
                8'h6B: key[1][0]  <= key_pressed;   // izquierda
                8'h5A: key[0][6]  <= key_pressed;   // ENTER del teclado numerico
                8'h4A: key[3][6]  <= key_pressed;   // / del teclado numerico
                8'h71: key[2][0]  <= key_pressed;   // Supr -> BS (CLR)
                8'h70: key[10][6] <= key_pressed;   // Insert -> INS
                8'h69: key[10][7] <= key_pressed;   // Fin (End) -> Ъ
                8'h14: key[2][7]  <= key_pressed;   // Ctrl derecho
                8'h11: key[9][6]  <= key_pressed;   // AltGr -> R/L
                default: ;
            endcase
        end else begin
            case (key_code)
                // fila 10: F1-F5, y F6-F10 con SHIFT
                8'h05: key[10][0] <= key_pressed;   // F1
                8'h06: key[10][1] <= key_pressed;   // F2
                8'h04: key[10][2] <= key_pressed;   // F3
                8'h0C: key[10][3] <= key_pressed;   // F4
                8'h03: key[10][4] <= key_pressed;   // F5
                8'h0B: begin key[10][0] <= key_pressed; fshift <= key_pressed; end  // F6
                8'h83: begin key[10][1] <= key_pressed; fshift <= key_pressed; end  // F7
                8'h0A: begin key[10][2] <= key_pressed; fshift <= key_pressed; end  // F8
                8'h01: begin key[10][3] <= key_pressed; fshift <= key_pressed; end  // F9
                8'h09: begin key[10][4] <= key_pressed; fshift <= key_pressed; end  // F10
                8'h78: key[10][5] <= key_pressed;   // F11 -> HELP
                // teclado numerico -> f0-f9, f.
                8'h70: key[1][7]  <= key_pressed;   // f0
                8'h69: key[1][5]  <= key_pressed;   // f1
                8'h72: key[1][6]  <= key_pressed;   // f2
                8'h7A: key[0][5]  <= key_pressed;   // f3
                8'h6B: key[2][4]  <= key_pressed;   // f4
                8'h73: key[1][4]  <= key_pressed;   // f5
                8'h74: key[0][4]  <= key_pressed;   // f6
                8'h6C: key[1][2]  <= key_pressed;   // f7
                8'h75: key[1][3]  <= key_pressed;   // f8
                8'h7D: key[0][3]  <= key_pressed;   // f9
                8'h71: key[0][7]  <= key_pressed;   // f.
                8'h7B: key[3][1]  <= key_pressed;   // - del teclado numerico
                // fila 2
                8'h5B: key[2][1]  <= key_pressed;   // ] -> [
                8'h5A: key[2][2]  <= key_pressed;   // RETURN
                8'h5D: key[2][3]  <= key_pressed;   // \ -> ]
                8'h12: key[2][5]  <= key_pressed;   // SHIFT izquierdo
                8'h59: key[2][5]  <= key_pressed;   // SHIFT derecho
                8'h61: key[2][6]  <= key_pressed;   // \ (tecla ISO)
                8'h14: key[2][7]  <= key_pressed;   // CTRL
                // fila 3
                8'h55: key[3][0]  <= key_pressed;   // = -> ^
                8'h4E: key[3][1]  <= key_pressed;   // -
                8'h54: key[3][2]  <= key_pressed;   // [ -> @
                8'h4D: key[3][3]  <= key_pressed;   // P
                8'h52: key[3][4]  <= key_pressed;   // ' -> ;
                8'h4C: key[3][5]  <= key_pressed;   // ; -> :
                8'h4A: key[3][6]  <= key_pressed;   // /
                8'h49: key[3][7]  <= key_pressed;   // .
                // fila 4
                8'h45: key[4][0]  <= key_pressed;   // 0
                8'h46: key[4][1]  <= key_pressed;   // 9
                8'h44: key[4][2]  <= key_pressed;   // O
                8'h43: key[4][3]  <= key_pressed;   // I
                8'h4B: key[4][4]  <= key_pressed;   // L
                8'h42: key[4][5]  <= key_pressed;   // K
                8'h3A: key[4][6]  <= key_pressed;   // M
                8'h41: key[4][7]  <= key_pressed;   // ,
                // fila 5
                8'h3E: key[5][0]  <= key_pressed;   // 8
                8'h3D: key[5][1]  <= key_pressed;   // 7
                8'h3C: key[5][2]  <= key_pressed;   // U
                8'h35: key[5][3]  <= key_pressed;   // Y
                8'h33: key[5][4]  <= key_pressed;   // H
                8'h3B: key[5][5]  <= key_pressed;   // J
                8'h31: key[5][6]  <= key_pressed;   // N
                8'h29: key[5][7]  <= key_pressed;   // ESPACIO
                // fila 6
                8'h36: key[6][0]  <= key_pressed;   // 6
                8'h2E: key[6][1]  <= key_pressed;   // 5
                8'h2D: key[6][2]  <= key_pressed;   // R
                8'h2C: key[6][3]  <= key_pressed;   // T
                8'h34: key[6][4]  <= key_pressed;   // G
                8'h2B: key[6][5]  <= key_pressed;   // F
                8'h32: key[6][6]  <= key_pressed;   // B
                8'h2A: key[6][7]  <= key_pressed;   // V
                // fila 7
                8'h25: key[7][0]  <= key_pressed;   // 4
                8'h26: key[7][1]  <= key_pressed;   // 3
                8'h24: key[7][2]  <= key_pressed;   // E
                8'h1D: key[7][3]  <= key_pressed;   // W
                8'h1B: key[7][4]  <= key_pressed;   // S
                8'h23: key[7][5]  <= key_pressed;   // D
                8'h21: key[7][6]  <= key_pressed;   // C
                8'h22: key[7][7]  <= key_pressed;   // X
                // fila 8
                8'h16: key[8][0]  <= key_pressed;   // 1
                8'h1E: key[8][1]  <= key_pressed;   // 2
                8'h76: key[8][2]  <= key_pressed;   // ESC
                8'h15: key[8][3]  <= key_pressed;   // Q
                8'h0D: key[8][4]  <= key_pressed;   // TAB
                8'h1C: key[8][5]  <= key_pressed;   // A
                8'h58: key[8][6]  <= key_pressed;   // CAPS LOCK
                8'h1A: key[8][7]  <= key_pressed;   // Z
                // fila 9
                8'h0E: key[9][6]  <= key_pressed;   // ` -> R/L
                8'h66: key[9][7]  <= key_pressed;   // Retroceso -> DEL
                8'h11: key[1][1]  <= key_pressed;   // Alt -> ALT (COPY)
                8'h7E: res_key    <= key_pressed;   // Bloq Despl -> RES (reset por hardware)
                default: ;
            endcase
        end
    end
end

// Joystick en la fila 9: D5 fuego 1, D4 fuego 2, D3 dcha, D2 izqda, D1 abajo, D0 arriba
wire [7:0] joy = {2'b00, joystick[4], joystick[5], joystick[0], joystick[1], joystick[2], joystick[3]};

always_comb begin
    logic [7:0] k;
    k = (row <= 4'd10) ? key[row] : 8'h00;
    if (row == 4'd9) k = k | joy;
    if (row == 4'd2 && (force_shift || fshift)) k[5] = 1'b1;
    if (row == 4'd2 && force_bs) k[0] = 1'b1;
    cols = ~k;
end

endmodule

`default_nettype wire
