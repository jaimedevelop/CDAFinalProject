`timescale 1ns / 1ps

module tb_manual_control_frontend;

    reg         clk;
    reg         reset;
    reg         manual_test_mode;
    reg  [3:0]  switches;
    reg  [7:0]  dip_switches;
    reg  [2:0]  buttons;
    reg         control_recording;
    reg         control_playing;
    reg         control_paused;

    wire [2:0]  button_pressed;
    wire [2:0]  button_rise;
    wire [1:0]  selected_message;
    wire [3:0]  volume_setting;
    wire [7:0]  command;
    wire        command_strobe;
    wire        clear_status_pulse;

    integer error_count;
    integer strobe_count;
    reg [7:0] last_strobe_command;

    localparam [7:0] CMD_PLAY         = 8'h01;
    localparam [7:0] CMD_RECORD       = 8'h02;
    localparam [7:0] CMD_DELETE       = 8'h03;
    localparam [7:0] CMD_DELETE_ALL   = 8'h04;
    localparam [7:0] CMD_STOP         = 8'h06;
    localparam [7:0] CMD_PAUSE_RESUME = 8'h07;

    manual_control_frontend #(
        .BUTTON_DEBOUNCE_CLKS(20'd3),
        .CMD_PLAY(CMD_PLAY),
        .CMD_RECORD(CMD_RECORD),
        .CMD_DELETE(CMD_DELETE),
        .CMD_DELETE_ALL(CMD_DELETE_ALL),
        .CMD_STOP(CMD_STOP),
        .CMD_PAUSE_RESUME(CMD_PAUSE_RESUME)
    ) dut (
        .clk(clk),
        .reset(reset),
        .manual_test_mode(manual_test_mode),
        .switches(switches),
        .dip_switches(dip_switches),
        .buttons(buttons),
        .control_recording(control_recording),
        .control_playing(control_playing),
        .control_paused(control_paused),
        .button_pressed(button_pressed),
        .button_rise(button_rise),
        .selected_message(selected_message),
        .volume_setting(volume_setting),
        .command(command),
        .command_strobe(command_strobe),
        .clear_status_pulse(clear_status_pulse)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (command_strobe) begin
            strobe_count <= strobe_count + 1;
            last_strobe_command <= command;
        end
    end

    task tick;
        input integer cycle_count;
        integer idx;
        begin
            for (idx = 0; idx < cycle_count; idx = idx + 1)
                @(posedge clk);
        end
    endtask

    task reset_command_observer;
        begin
            strobe_count = 0;
            last_strobe_command = 8'h00;
        end
    endtask

    task pulse_button;
        input [2:0] mask;
        begin
            buttons = mask;
            tick(3);
            buttons = 3'b000;
            tick(6);
        end
    endtask

    task pulse_button_async;
        input [2:0] mask;
        input integer press_offset_ns;
        input integer press_width_ns;
        input integer settle_cycles;
        begin
            #(press_offset_ns);
            buttons = mask;
            #(press_width_ns);
            buttons = 3'b000;
            tick(settle_cycles);
        end
    endtask

    task bounce_button_async;
        input [2:0] mask;
        begin
            #2  buttons = mask;
            #4  buttons = 3'b000;
            #3  buttons = mask;
            #4  buttons = 3'b000;
            #2  buttons = mask;
            #25 buttons = 3'b000;
            tick(8);
        end
    endtask

    task check_single_command_event;
        input [7:0] expected_command;
        input [255:0] check_name;
        begin
            if (strobe_count !== 1) begin
                $display("ERROR: %0s expected exactly 1 command strobe, got %0d", check_name, strobe_count);
                error_count = error_count + 1;
            end
            if (last_strobe_command !== expected_command) begin
                $display("ERROR: %0s expected command 0x%0h, got 0x%0h", check_name, expected_command, last_strobe_command);
                error_count = error_count + 1;
            end
        end
    endtask

    task check_equal_1bit;
        input actual_value;
        input expected_value;
        input [255:0] check_name;
        begin
            if (actual_value !== expected_value) begin
                $display("ERROR: %0s expected %0d, got %0d", check_name, expected_value, actual_value);
                error_count = error_count + 1;
            end
        end
    endtask

    task check_equal_2bit;
        input [1:0] actual_value;
        input [1:0] expected_value;
        input [255:0] check_name;
        begin
            if (actual_value !== expected_value) begin
                $display("ERROR: %0s expected %0d, got %0d", check_name, expected_value, actual_value);
                error_count = error_count + 1;
            end
        end
    endtask

    task check_equal_4bit;
        input [3:0] actual_value;
        input [3:0] expected_value;
        input [255:0] check_name;
        begin
            if (actual_value !== expected_value) begin
                $display("ERROR: %0s expected 0x%0h, got 0x%0h", check_name, expected_value, actual_value);
                error_count = error_count + 1;
            end
        end
    endtask

    task check_equal_8bit;
        input [7:0] actual_value;
        input [7:0] expected_value;
        input [255:0] check_name;
        begin
            if (actual_value !== expected_value) begin
                $display("ERROR: %0s expected 0x%0h, got 0x%0h", check_name, expected_value, actual_value);
                error_count = error_count + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        manual_test_mode = 1'b1;
        switches = 4'b0010;
        dip_switches = 8'b00111001; // volume=1110, slot=01
        buttons = 3'b000;
        control_recording = 1'b0;
        control_playing = 1'b0;
        control_paused = 1'b0;
        error_count = 0;
        strobe_count = 0;
        last_strobe_command = 8'h00;

        tick(4);
        reset = 1'b0;
        tick(3);

        check_equal_2bit(selected_message, 2'b01, "slot follows DIP[1:0]");
        check_equal_4bit(volume_setting, 4'b1110, "volume follows DIP[5:2]");
        check_equal_1bit(command_strobe, 1'b0, "idle command_strobe");

        reset_command_observer;
        pulse_button(3'b001);
        check_equal_8bit(command, CMD_RECORD, "BTN0 issues record");
        check_equal_1bit(command_strobe, 1'b0, "BTN0 strobe returns low");
        check_equal_1bit(clear_status_pulse, 1'b0, "BTN0 clear pulse returns low");
        check_single_command_event(CMD_RECORD, "BTN0 clean press");

        control_recording = 1'b1;
        reset_command_observer;
        pulse_button(3'b001);
        check_equal_8bit(command, CMD_STOP, "BTN0 issues stop while recording");
        check_single_command_event(CMD_STOP, "BTN0 stop while recording");
        control_recording = 1'b0;

        reset_command_observer;
        pulse_button(3'b010);
        check_equal_8bit(command, CMD_PLAY, "BTN1 issues play");
        check_single_command_event(CMD_PLAY, "BTN1 clean press");

        control_playing = 1'b1;
        reset_command_observer;
        pulse_button(3'b010);
        check_equal_8bit(command, CMD_STOP, "BTN1 issues stop while playing");
        check_single_command_event(CMD_STOP, "BTN1 stop while playing");
        control_playing = 1'b0;

        reset_command_observer;
        pulse_button(3'b100);
        check_equal_8bit(command, CMD_PAUSE_RESUME, "BTN2 issues pause/resume");
        check_single_command_event(CMD_PAUSE_RESUME, "BTN2 clean press");

        switches[3] = 1'b1;
        switches[2] = 1'b0;
        reset_command_observer;
        pulse_button(3'b100);
        check_equal_8bit(command, CMD_DELETE, "BTN2 with SW3 issues delete");
        check_single_command_event(CMD_DELETE, "BTN2 delete modifier");

        switches[2] = 1'b1;
        reset_command_observer;
        pulse_button(3'b100);
        check_equal_8bit(command, CMD_DELETE_ALL, "BTN2 with SW3+SW2 issues delete all");
        check_single_command_event(CMD_DELETE_ALL, "BTN2 delete-all modifier");

        reset_command_observer;
        buttons = 3'b001;
        tick(10);
        check_equal_1bit(button_rise[0], 1'b0, "long hold does not keep button_rise asserted");
        buttons = 3'b000;
        tick(10);
        check_single_command_event(CMD_RECORD, "BTN0 long hold one-shot");

        switches[3] = 1'b0;
        switches[2] = 1'b0;
        reset_command_observer;
        pulse_button_async(3'b001, 2, 23, 8);
        check_single_command_event(CMD_RECORD, "BTN0 asynchronous off-edge press");

        reset_command_observer;
        bounce_button_async(3'b010);
        check_single_command_event(CMD_PLAY, "BTN1 bounce-like press");

        reset_command_observer;
        pulse_button_async(3'b100, 7, 9, 8);
        if (strobe_count > 1) begin
            $display("ERROR: BTN2 near-threshold tap produced more than one command strobe (%0d)", strobe_count);
            error_count = error_count + 1;
        end

        if (error_count == 0) begin
            $display("PASS: tb_manual_control_frontend completed without errors.");
        end else begin
            $display("FAIL: tb_manual_control_frontend completed with %0d error(s).", error_count);
        end

        $finish;
    end

endmodule
