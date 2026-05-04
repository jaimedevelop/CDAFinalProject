`timescale 1ns / 1ps

module tb_recorder_control_record_play;

    reg         clk;
    reg         reset;
    reg  [7:0]  command;
    reg         command_strobe;
    reg         clear_status;
    reg  [1:0]  selected_message;
    reg  [3:0]  volume_setting;
    reg  [15:0] recorder_input_sample;
    reg         recorder_input_valid;
    reg         recorder_input_toggle;
    reg         playback_request_toggle;
    reg         ram_rdy;
    reg         ram_rd_data_pres;
    reg  [15:0] ram_data_out;
    reg  [25:0] ram_max_address;

    wire        command_done;
    wire        invalid_command;
    wire        busy;
    wire        recording;
    wire        playing;
    wire        paused;
    wire        deleting;
    wire        selected_msg_valid;
    wire        selected_msg_full;
    wire [25:0] selected_msg_start;
    wire [25:0] selected_msg_length;
    wire        any_empty_slot;
    wire        slot_plan_fits_ram;
    wire [2:0]  state_debug;
    wire [3:0]  latched_volume_setting;
    wire        playback_enable;
    wire [15:0] playback_sample_data;
    wire [25:0] ram_address;
    wire [15:0] ram_data_in;
    wire        ram_write_enable;
    wire        ram_read_request;
    wire        ram_read_ack;

    integer error_count;
    integer wait_count;

    localparam [7:0] CMD_PLAY         = 8'h01;
    localparam [7:0] CMD_RECORD       = 8'h02;
    localparam [7:0] CMD_DELETE       = 8'h03;
    localparam [7:0] CMD_DELETE_ALL   = 8'h04;
    localparam [7:0] CMD_VOLUME       = 8'h05;
    localparam [7:0] CMD_STOP         = 8'h06;

    localparam [2:0] STATE_IDLE      = 3'd0;
    localparam [2:0] STATE_RECORDING = 3'd1;
    localparam [2:0] STATE_PLAYING   = 3'd2;

    localparam [25:0] SLOT0_BASE = 26'd0;
    localparam [25:0] SLOT1_BASE = 26'd4194304;

    recorder_control dut (
        .clk(clk),
        .reset(reset),
        .command(command),
        .command_strobe(command_strobe),
        .clear_status(clear_status),
        .selected_message(selected_message),
        .volume_setting(volume_setting),
        .recorder_input_sample(recorder_input_sample),
        .recorder_input_valid(recorder_input_valid),
        .recorder_input_toggle(recorder_input_toggle),
        .playback_request_toggle(playback_request_toggle),
        .ram_rdy(ram_rdy),
        .ram_rd_data_pres(ram_rd_data_pres),
        .ram_data_out(ram_data_out),
        .ram_max_address(ram_max_address),
        .command_done(command_done),
        .invalid_command(invalid_command),
        .busy(busy),
        .recording(recording),
        .playing(playing),
        .paused(paused),
        .deleting(deleting),
        .selected_msg_valid(selected_msg_valid),
        .selected_msg_full(selected_msg_full),
        .selected_msg_start(selected_msg_start),
        .selected_msg_length(selected_msg_length),
        .any_empty_slot(any_empty_slot),
        .slot_plan_fits_ram(slot_plan_fits_ram),
        .state_debug(state_debug),
        .latched_volume_setting(latched_volume_setting),
        .playback_enable(playback_enable),
        .playback_sample_data(playback_sample_data),
        .ram_address(ram_address),
        .ram_data_in(ram_data_in),
        .ram_write_enable(ram_write_enable),
        .ram_read_request(ram_read_request),
        .ram_read_ack(ram_read_ack)
    );

    always #5 clk = ~clk;

    task tick;
        input integer cycle_count;
        integer idx;
        begin
            for (idx = 0; idx < cycle_count; idx = idx + 1)
                @(posedge clk);
        end
    endtask

    task clear_status_flags;
        begin
            clear_status = 1'b1;
            @(posedge clk);
            clear_status = 1'b0;
            @(posedge clk);
        end
    endtask

    task issue_command;
        input [7:0] cmd;
        begin
            command = cmd;
            command_strobe = 1'b1;
            @(posedge clk);
            command_strobe = 1'b0;
            command = 8'h00;
            @(posedge clk);
        end
    endtask

    task send_record_sample;
        input [15:0] sample_value;
        begin
            recorder_input_sample = sample_value;
            tick(1);
            recorder_input_toggle = ~recorder_input_toggle;
            tick(3);
        end
    endtask

    task send_record_sample_and_check_write;
        input [15:0] sample_value;
        input [25:0] expected_address;
        input [255:0] check_prefix;
        begin
            recorder_input_sample = sample_value;
            tick(1);
            recorder_input_toggle = ~recorder_input_toggle;
            wait_for_ram_write_enable({check_prefix, " write pulse"}, 50);
            if (ram_write_enable !== 1'b1)
                disable send_record_sample_and_check_write;
            check_equal_1bit(ram_write_enable, 1'b1, {check_prefix, " write pulse"});
            check_equal_26bit(ram_address, expected_address, {check_prefix, " write address"});
            check_equal_16bit(ram_data_in, sample_value, {check_prefix, " write data"});
            @(posedge clk);
        end
    endtask

    task request_playback_sample;
        begin
            playback_request_toggle = ~playback_request_toggle;
            tick(3);
        end
    endtask

    task wait_for_ram_write_enable;
        input [255:0] check_name;
        input integer max_cycles;
        begin
            wait_count = 0;
            while ((ram_write_enable !== 1'b1) && (wait_count < max_cycles)) begin
                @(posedge clk);
                wait_count = wait_count + 1;
            end

            if (ram_write_enable !== 1'b1) begin
                $display("ERROR: timeout waiting for %0s", check_name);
                error_count = error_count + 1;
            end
        end
    endtask

    task wait_for_ram_read_request;
        input [255:0] check_name;
        input integer max_cycles;
        begin
            wait_count = 0;
            while ((ram_read_request !== 1'b1) &&
                   (dut.playback_read_pending !== 1'b1) &&
                   (wait_count < max_cycles)) begin
                @(posedge clk);
                wait_count = wait_count + 1;
            end

            if ((ram_read_request !== 1'b1) &&
                (dut.playback_read_pending !== 1'b1)) begin
                $display("ERROR: timeout waiting for %0s", check_name);
                error_count = error_count + 1;
            end
        end
    endtask

    task wait_for_ram_read_ack;
        input [255:0] check_name;
        input integer max_cycles;
        begin
            wait_count = 0;
            while ((ram_read_ack !== 1'b1) && (wait_count < max_cycles)) begin
                @(posedge clk);
                wait_count = wait_count + 1;
            end

            if (ram_read_ack !== 1'b1) begin
                $display("ERROR: timeout waiting for %0s", check_name);
                error_count = error_count + 1;
            end
        end
    endtask

    task service_read_and_check;
        input [25:0] expected_address;
        input [15:0] returned_sample;
        begin
            wait_for_ram_read_request("ram_read_request", 50);
            if ((ram_read_request !== 1'b1) &&
                (dut.playback_read_pending !== 1'b1))
                disable service_read_and_check;

            if (ram_address !== expected_address) begin
                $display("ERROR: expected read address %0d, got %0d", expected_address, ram_address);
                error_count = error_count + 1;
            end
            ram_data_out = returned_sample;
            ram_rd_data_pres = 1'b1;
            @(posedge clk);
            ram_rd_data_pres = 1'b0;
            ram_data_out = 16'h0000;
            wait_for_ram_read_ack("ram_read_ack", 50);
            if (ram_read_ack !== 1'b1)
                disable service_read_and_check;
            @(posedge clk);
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

    task check_equal_16bit;
        input [15:0] actual_value;
        input [15:0] expected_value;
        input [255:0] check_name;
        begin
            if (actual_value !== expected_value) begin
                $display("ERROR: %0s expected 0x%0h, got 0x%0h", check_name, expected_value, actual_value);
                error_count = error_count + 1;
            end
        end
    endtask

    task check_equal_26bit;
        input [25:0] actual_value;
        input [25:0] expected_value;
        input [255:0] check_name;
        begin
            if (actual_value !== expected_value) begin
                $display("ERROR: %0s expected %0d, got %0d", check_name, expected_value, actual_value);
                error_count = error_count + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        command = 8'h00;
        command_strobe = 1'b0;
        clear_status = 1'b0;
        selected_message = 2'b00;
        volume_setting = 4'h8;
        recorder_input_sample = 16'h0000;
        recorder_input_valid = 1'b0;
        recorder_input_toggle = 1'b0;
        playback_request_toggle = 1'b0;
        ram_rdy = 1'b1;
        ram_rd_data_pres = 1'b0;
        ram_data_out = 16'h0000;
        ram_max_address = 26'h0FFFFFF;
        error_count = 0;

        tick(4);
        reset = 1'b0;
        tick(3);

        // S0: reset and idle sanity
        check_equal_26bit(selected_msg_length, 26'd0, "S0 selected_msg_length");
        check_equal_1bit(selected_msg_valid, 1'b0, "S0 selected_msg_valid");
        check_equal_1bit(command_done, 1'b0, "S0 command_done");
        check_equal_1bit(invalid_command, 1'b0, "S0 invalid_command");
        check_equal_1bit(slot_plan_fits_ram, 1'b1, "S0 slot_plan_fits_ram");
        if (state_debug !== STATE_IDLE) begin
            $display("ERROR: S0 expected STATE_IDLE, got %0d", state_debug);
            error_count = error_count + 1;
        end

        // S1: record two samples into slot 00
        clear_status_flags;
        selected_message = 2'b00;
        issue_command(CMD_RECORD);
        if (state_debug !== STATE_RECORDING) begin
            $display("ERROR: S1 expected STATE_RECORDING, got %0d", state_debug);
            error_count = error_count + 1;
        end

        send_record_sample_and_check_write(16'h1111, SLOT0_BASE, "S1 first");
        send_record_sample_and_check_write(16'h2222, SLOT0_BASE + 26'd1, "S1 second");

        issue_command(CMD_STOP);
        tick(3);
        if (state_debug !== STATE_IDLE) begin
            $display("ERROR: S1 expected return to STATE_IDLE, got %0d", state_debug);
            error_count = error_count + 1;
        end
        check_equal_1bit(command_done, 1'b1, "S1 command_done");
        check_equal_1bit(selected_msg_valid, 1'b1, "S1 slot00 valid");
        check_equal_26bit(selected_msg_length, 26'd2, "S1 slot00 length");

        // S2: record slot 00 while changing live slot input mid-operation
        clear_status_flags;
        selected_message = 2'b00;
        issue_command(CMD_RECORD);
        send_record_sample(16'h3333);
        selected_message = 2'b01;
        send_record_sample(16'h4444);
        issue_command(CMD_STOP);
        tick(3);

        selected_message = 2'b00;
        tick(2);
        check_equal_1bit(selected_msg_valid, 1'b1, "S2 slot00 valid");
        check_equal_26bit(selected_msg_length, 26'd2, "S2 slot00 length");

        selected_message = 2'b01;
        tick(2);
        check_equal_1bit(selected_msg_valid, 1'b0, "S2 slot01 untouched valid");
        check_equal_26bit(selected_msg_length, 26'd0, "S2 slot01 untouched length");

        // Prepare slot 01 for playback tests
        clear_status_flags;
        selected_message = 2'b01;
        issue_command(CMD_RECORD);
        send_record_sample(16'h5555);
        send_record_sample(16'h6666);
        issue_command(CMD_STOP);
        tick(3);

        selected_message = 2'b01;
        tick(2);
        check_equal_1bit(selected_msg_valid, 1'b1, "prep slot01 valid");
        check_equal_26bit(selected_msg_length, 26'd2, "prep slot01 length");

        // S3/S4/S5: playback slot 01, verify read addresses and latching
        clear_status_flags;
        selected_message = 2'b01;
        volume_setting = 4'h4;
        issue_command(CMD_PLAY);
        tick(2);

        if (state_debug !== STATE_PLAYING) begin
            $display("ERROR: S3 expected STATE_PLAYING, got %0d", state_debug);
            error_count = error_count + 1;
        end
        check_equal_4bit(latched_volume_setting, 4'h4, "S3 latched playback volume");

        selected_message = 2'b00;
        volume_setting = 4'h9;
        tick(2);
        check_equal_4bit(latched_volume_setting, 4'h4, "S4 latched volume unchanged without CMD_VOLUME");
        check_equal_1bit(selected_msg_valid, 1'b1, "S4 effective selected slot still valid during playback");
        check_equal_26bit(selected_msg_length, 26'd2, "S4 effective selected slot length during playback");

        service_read_and_check(SLOT1_BASE, 16'h0A0A);
        check_equal_16bit(playback_sample_data, 16'h0A0A, "S3 first staged playback sample");
        request_playback_sample;

        issue_command(CMD_VOLUME);
        tick(2);
        check_equal_4bit(latched_volume_setting, 4'h9, "S5 latched volume updated by CMD_VOLUME");

        service_read_and_check(SLOT1_BASE + 26'd1, 16'h0B0B);
        check_equal_16bit(playback_sample_data, 16'h0B0B, "S3 second staged playback sample");
        request_playback_sample;
        tick(3);

        if (state_debug !== STATE_IDLE) begin
            $display("ERROR: S3 expected playback to finish and return to idle, got %0d", state_debug);
            error_count = error_count + 1;
        end

        if (error_count == 0) begin
            $display("PASS: tb_recorder_control_record_play completed without errors.");
        end else begin
            $display("FAIL: tb_recorder_control_record_play completed with %0d error(s).", error_count);
        end

        $finish;
    end

endmodule
