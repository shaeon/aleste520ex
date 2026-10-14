// Modelos minimos de las primitivas de Altera, solo para lint y simulacion.
`timescale 1ns/1ps
module altddio_out #(
    parameter extend_oe_disable = "OFF",
    parameter intended_device_family = "Cyclone IV GX",
    parameter invert_output = "OFF",
    parameter lpm_hint = "UNUSED",
    parameter lpm_type = "altddio_out",
    parameter oe_reg = "UNREGISTERED",
    parameter power_up_high = "OFF",
    parameter width = 1
)(
    input  [width-1:0] datain_h, datain_l,
    input  outclock, aclr, aset, oe, outclocken, sclr, sset,
    output [width-1:0] dataout
);
    reg [width-1:0] h = 0, l = 0;
    always @(posedge outclock) h <= datain_h;
    always @(negedge outclock) l <= datain_l;
    assign dataout = outclock ? h : l;
endmodule
