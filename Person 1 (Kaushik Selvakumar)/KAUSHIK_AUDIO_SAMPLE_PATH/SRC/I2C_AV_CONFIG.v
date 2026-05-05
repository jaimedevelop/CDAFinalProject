`timescale 1ns / 1ps

module i2c_av_config (
    input clk,
    input reset,

    output i2c_sclk,
    inout  i2c_sdat,

    output [3:0] status
);

reg [23:0] i2c_data;
reg [15:0] lut_data;
reg [3:0]  lut_index = 4'd0;

localparam [7:0] CODEC_I2C_ADDR = 8'h34;
localparam [3:0] LAST_INDEX     = 4'ha;

localparam [1:0] ST_START  = 2'b00;
localparam [1:0] ST_LATCH  = 2'b01;
localparam [1:0] ST_WAIT   = 2'b10;
localparam [1:0] ST_DONE   = 2'b11;

reg  i2c_start = 1'b0;
wire i2c_done;
wire i2c_ack;

i2c_controller control (
    .clk (clk),
    .i2c_sclk (i2c_sclk),
    .i2c_sdat (i2c_sdat),
    .i2c_data (i2c_data),
    .start (i2c_start),
    .done (i2c_done),
    .ack (i2c_ack)
);

always @(*) begin
    case (lut_index)
        4'h0: lut_data = 16'h0c10; // power on everything except out
        4'h1: lut_data = 16'h0017; // left input
        4'h2: lut_data = 16'h0217; // right input
        4'h3: lut_data = 16'h0479; // left output
        4'h4: lut_data = 16'h0679; // right output
        4'h5: lut_data = 16'h08d4; // analog path
        4'h6: lut_data = 16'h0a04; // digital path
        4'h7: lut_data = 16'h0e01; // digital IF
        4'h8: lut_data = 16'h1020; // sampling rate
        4'h9: lut_data = 16'h0c00; // power on everything
        4'ha: lut_data = 16'h1201; // activate
        default: lut_data = 16'h0000;
    endcase
end

reg [1:0] control_state = ST_START;

assign status = lut_index;

always @(posedge clk) begin
    if (reset) begin
        lut_index <= 4'd0;
        i2c_start <= 1'b0;
        control_state <= ST_START;
    end else begin
        case (control_state)
            ST_START: begin
                i2c_start <= 1'b1;
                i2c_data <= {CODEC_I2C_ADDR, lut_data};
                control_state <= ST_LATCH;
            end
            ST_LATCH: begin
                i2c_start <= 1'b0;
                control_state <= ST_WAIT;
            end
            ST_WAIT: if (i2c_done) begin
                if (i2c_ack) begin
                    if (lut_index == LAST_INDEX)
                        control_state <= ST_DONE;
                    else begin
                        lut_index <= lut_index + 1'b1;
                        control_state <= ST_START;
                    end
                end else
                    control_state <= ST_START;
            end
        endcase
    end
end

endmodule
