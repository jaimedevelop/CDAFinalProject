`timescale 1ns / 1ps

module manual_control_frontend #(
    parameter [19:0] BUTTON_DEBOUNCE_CLKS = 20'd1000000,
    parameter [7:0]  CMD_PLAY             = 8'h01,
    parameter [7:0]  CMD_RECORD           = 8'h02,
    parameter [7:0]  CMD_DELETE           = 8'h03,
    parameter [7:0]  CMD_DELETE_ALL       = 8'h04,
    parameter [7:0]  CMD_STOP             = 8'h06,
    parameter [7:0]  CMD_PAUSE_RESUME     = 8'h07
) (
    input         clk,
    input         reset,
    input         manual_test_mode,
    input  [3:0]  switches,
    input  [7:0]  dip_switches,
    input  [2:0]  buttons,
    input         control_recording,
    input         control_playing,
    input         control_paused,
    output [2:0]  button_pressed,
    output [2:0]  button_rise,
    output [1:0]  selected_message,
    output [3:0]  volume_setting,
    output [7:0]  command,
    output        command_strobe,
    output        clear_status_pulse
);

    reg [2:0]  buttons_sync0;
    reg [2:0]  buttons_sync1;
    reg [2:0]  button_rise_reg;
    reg [2:0]  button_pressed_prev;
    reg [19:0] button_debounce_counter;
    reg [1:0]  selected_message_reg;
    reg [3:0]  volume_setting_reg;
    reg [7:0]  command_reg;
    reg        command_strobe_reg;
    reg        clear_status_pulse_reg;

    assign button_pressed     = buttons_sync1;
    assign button_rise        = button_rise_reg;
    assign selected_message   = selected_message_reg;
    assign volume_setting     = volume_setting_reg;
    assign command            = command_reg;
    assign command_strobe     = command_strobe_reg;
    assign clear_status_pulse = clear_status_pulse_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            buttons_sync0          <= 3'b000;
            buttons_sync1          <= 3'b000;
            button_rise_reg        <= 3'b000;
            button_pressed_prev    <= 3'b000;
            button_debounce_counter <= 20'd0;
            selected_message_reg   <= 2'b00;
            volume_setting_reg     <= 4'h8;
            command_reg            <= 8'h00;
            command_strobe_reg     <= 1'b0;
            clear_status_pulse_reg <= 1'b0;
        end else begin
            buttons_sync0 <= buttons;
            buttons_sync1 <= buttons_sync0;
            button_rise_reg <= 3'b000;
            command_strobe_reg <= 1'b0;
            clear_status_pulse_reg <= 1'b0;

            if (button_debounce_counter != 20'd0) begin
                button_debounce_counter <= button_debounce_counter - 20'd1;
            end else begin
                button_rise_reg <= button_pressed & ~button_pressed_prev;
                if ((button_pressed & ~button_pressed_prev) != 3'b000)
                    button_debounce_counter <= BUTTON_DEBOUNCE_CLKS;
            end
            button_pressed_prev <= button_pressed;

            if (manual_test_mode) begin
                selected_message_reg <= dip_switches[1:0];
                volume_setting_reg   <= dip_switches[5:2];

                if (button_rise_reg[0]) begin
                    command_reg            <= (control_recording || control_playing || control_paused) ? CMD_STOP : CMD_RECORD;
                    command_strobe_reg     <= 1'b1;
                    clear_status_pulse_reg <= 1'b1;
                end else if (button_rise_reg[1]) begin
                    command_reg            <= (control_playing || control_paused) ? CMD_STOP : CMD_PLAY;
                    command_strobe_reg     <= 1'b1;
                    clear_status_pulse_reg <= 1'b1;
                end else if (button_rise_reg[2]) begin
                    command_reg            <= switches[3] ? (switches[2] ? CMD_DELETE_ALL : CMD_DELETE)
                                                          : CMD_PAUSE_RESUME;
                    command_strobe_reg     <= 1'b1;
                    clear_status_pulse_reg <= 1'b1;
                end
            end
        end
    end

endmodule
