`timescale 1ns / 1ps

module hw_input_handler #(
    parameter [19:0] DEBOUNCE_CYCLES  = 20'd1000000,
    parameter [7:0]  OP_PLAY          = 8'h01,
    parameter [7:0]  OP_RECORD        = 8'h02,
    parameter [7:0]  OP_DELETE        = 8'h03,
    parameter [7:0]  OP_DELETE_ALL    = 8'h04,
    parameter [7:0]  OP_STOP          = 8'h06,
    parameter [7:0]  OP_PAUSE_RESUME  = 8'h07
) (
    input         clk,
    input         reset,
    input         btn_mode_active,
    input  [3:0]  slide_sw,
    input  [7:0]  dip_sw,
    input  [2:0]  push_btn,
    input         is_recording,
    input         is_playing,
    input         is_paused,
    output [2:0]  btn_state,
    output [2:0]  btn_edge,
    output [1:0]  msg_sel,
    output [3:0]  vol_out,
    output [7:0]  cmd_out,
    output        cmd_pulse,
    output        clr_pulse
);

    reg [2:0]  btn_sync0;
    reg [2:0]  btn_sync1;
    reg [2:0]  btn_edge_reg;
    reg [2:0]  btn_prev;
    reg [19:0] dbnc_cnt;
    reg [1:0]  msg_sel_reg;
    reg [3:0]  vol_reg;
    reg [7:0]  cmd_reg;
    reg        cmd_pulse_reg;
    reg        clr_pulse_reg;

    assign btn_state  = btn_sync1;
    assign btn_edge   = btn_edge_reg;
    assign msg_sel    = msg_sel_reg;
    assign vol_out    = vol_reg;
    assign cmd_out    = cmd_reg;
    assign cmd_pulse  = cmd_pulse_reg;
    assign clr_pulse  = clr_pulse_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            btn_sync0      <= 3'b000;
            btn_sync1      <= 3'b000;
            btn_edge_reg   <= 3'b000;
            btn_prev       <= 3'b000;
            dbnc_cnt       <= 20'd0;
            msg_sel_reg    <= 2'b00;
            vol_reg        <= 4'h8;
            cmd_reg        <= 8'h00;
            cmd_pulse_reg  <= 1'b0;
            clr_pulse_reg  <= 1'b0;
        end else begin
            btn_sync0     <= push_btn;
            btn_sync1     <= btn_sync0;
            btn_edge_reg  <= 3'b000;
            cmd_pulse_reg <= 1'b0;
            clr_pulse_reg <= 1'b0;

            if (dbnc_cnt != 20'd0) begin
                dbnc_cnt <= dbnc_cnt - 20'd1;
            end else begin
                btn_edge_reg <= btn_state & ~btn_prev;
                if ((btn_state & ~btn_prev) != 3'b000)
                    dbnc_cnt <= DEBOUNCE_CYCLES;
            end
            btn_prev <= btn_state;

            if (btn_mode_active) begin
                msg_sel_reg <= dip_sw[1:0];
                vol_reg     <= dip_sw[5:2];

                if (btn_edge_reg[0]) begin
                    cmd_reg       <= (is_recording || is_playing || is_paused) ? OP_STOP : OP_RECORD;
                    cmd_pulse_reg <= 1'b1;
                    clr_pulse_reg <= 1'b1;
                end else if (btn_edge_reg[1]) begin
                    cmd_reg       <= (is_playing || is_paused) ? OP_STOP : OP_PLAY;
                    cmd_pulse_reg <= 1'b1;
                    clr_pulse_reg <= 1'b1;
                end else if (btn_edge_reg[2]) begin
                    cmd_reg       <= slide_sw[3] ? (slide_sw[2] ? OP_DELETE_ALL : OP_DELETE)
                                                  : OP_PAUSE_RESUME;
                    cmd_pulse_reg <= 1'b1;
                    clr_pulse_reg <= 1'b1;
                end
            end
        end
    end

endmodule
