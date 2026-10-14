// ============================================================================
// FICHERO GENERADO por tools/gen_rtl.py - no editar a mano.
// Origen: aleste-lx/src/components/video/palette/cpc_colors.sv @ ?
// Cambios: 32 colores hardware del Gate Array, tabla del 520EX (cpc_palette_520ex.mem).
// ============================================================================
// cpc_colors.sv - Accurate CPC hardware register to RGB converter
module cpc_colors (
    input  wire        clk_i,
    input  wire [4:0]  hw_register, 
    output reg [11:0]  rgb_color
);

(* no_rw_check *)
reg [11:0] cpc_hw_to_rgb [0:31];

// Загрузка из файла - НЕТ КОМБИНАТОРНОГО ВЗРЫВА
initial begin
    $readmemh("cpc_palette_520ex.mem", cpc_hw_to_rgb);  // tools/gen_rtl.py
end

always @(posedge clk_i) begin
    if (1'b1)  // 32 colores hardware
        rgb_color <= cpc_hw_to_rgb[hw_register];
    else
        rgb_color <= 12'h000;
end

endmodule
