`timescale 1ns / 1ps
// Simulation/syntax-check stub only.
// In Xilinx ISE, use the real clk_wiz_v3_6.vhd file instead.

module clk_wiz_v3_6 (
    input  wire CLK_IN1,
    output wire CLK_OUT1,
    output wire CLK_OUT2,
    input  wire RESET,
    output wire LOCKED
);

    assign CLK_OUT1 = CLK_IN1;
    assign CLK_OUT2 = CLK_IN1;
    assign LOCKED = !RESET;

endmodule
