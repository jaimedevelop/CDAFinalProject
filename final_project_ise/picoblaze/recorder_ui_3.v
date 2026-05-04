`timescale 1ns / 1ps

module ROM_form (
    input  [11:0] address,
    output [17:0] instruction,
    input         enable,
    input         clk
);

reg [17:0] rom [0:4095];
reg [17:0] instruction_reg;

initial begin
    $readmemh("picoblaze/recorder_ui.hex", rom);
end

always @(posedge clk) begin
    if (enable)
        instruction_reg <= rom[address];
end

assign instruction = instruction_reg;

endmodule
