`timescale 1ns / 1ps

module tb_record_play_digital_e2e;

    reg         clk;
    reg         reset;
    reg  [7:0]  command;
    reg         command_strobe;
    reg         clear_status;
    reg  [1:0]  selected_message;
    reg  [3:0]  volume_setting;
    reg         sample_end;
    reg         sample_req;
    reg  [15:0] audio_input;
    reg         monitor_enable;
    reg         test_tone_enable;
    reg         ram_rdy;
    reg  [25:0] ram_max_address;

    wire [15:0] audio_output;
    wire [15:0] recorder_sample;
    wire        recorder_sample_valid;
    wire        recorder_sample_toggle;
    wire        playback_request_toggle;

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

    reg         ram_rd_data_pres;
    reg  [15:0] ram_data_out;

    reg  [15:0] ram_model [0:63];
    reg         read_pending;
    reg  [25:0] pending_read_address;
    reg  [1:0]  read_latency_count;

    integer error_count;
    integer idx;
    integer wait_count;

    localparam [7:0] CMD_PLAY   = 8'h01;
    localparam [7:0] CMD_RECORD = 8'h02;
    localparam [7:0] CMD_STOP   = 8'h06;

    localparam [2:0] STATE_IDLE      = 3'd0;
    localparam [2:0] STATE_RECORDING = 3'd1;
    localparam [2:0] STATE_PLAYING   = 3'd2;

    localparam [15:0] SAMPLE0 = 16'h1234;
    localparam [15:0] SAMPLE1 = 16'hFEDC;
    localparam [15:0] SAMPLE2 = 16'h0A0A;

    audio_sample_path sample_path (
        .clk(clk),
        .reset(reset),
        .sample_end(sample_end),
        .sample_req(sample_req),
        .audio_input(audio_input),
        .playback_enable(playback_enable),
        .monitor_enable(monitor_enable),
        .test_tone_enable(test_tone_enable),
        .playback_sample(playback_sample_data),
        .volume_setting(latched_volume_setting),
        .audio_output(audio_output),
        .recorder_sample(recorder_sample),
        .recorder_sample_valid(recorder_sample_valid),
        .recorder_sample_toggle(recorder_sample_toggle),
        .playback_request_toggle(playback_request_toggle)
    );

    recorder_control control (
        .clk(clk),
        .reset(reset),
        .command(command),
        .command_strobe(command_strobe),
        .clear_status(clear_status),
        .selected_message(selected_message),
        .volume_setting(volume_setting),
        .recorder_input_sample(recorder_sample),
        .recorder_input_valid(recorder_sample_valid),
        .recorder_input_toggle(recorder_sample_toggle),
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

    always @(posedge clk) begin
        if (reset) begin
            ram_rd_data_pres    <= 1'b0;
            ram_data_out        <= 16'h0000;
            read_pending        <= 1'b0;
            pending_read_address <= 26'd0;
            read_latency_count  <= 2'd0;
        end else begin
            ram_rd_data_pres <= 1'b0;

            if (ram_write_enable) begin
                ram_model[ram_address[5:0]] <= ram_data_in;
            end

            if (ram_read_request && !read_pending) begin
                read_pending         <= 1'b1;
                pending_read_address <= ram_address;
                read_latency_count   <= 2'd2;
            end else if (read_pending) begin
                if (read_latency_count != 2'd0) begin
                    read_latency_count <= read_latency_count - 2'd1;
                end else begin
                    ram_data_out     <= ram_model[pending_read_address[5:0]];
                    ram_rd_data_pres <= 1'b1;
                    if (ram_read_ack) begin
                        read_pending <= 1'b0;
                    end
                end
            end
        end
    end

    task tick;
        input integer cycle_count;
        integer j;
        begin
            for (j = 0; j < cycle_count; j = j + 1)
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

    task send_input_sample;
        input [15:0] sample_value;
        begin
            audio_input = sample_value;
            sample_end = 1'b1;
            @(posedge clk);
            sample_end = 1'b0;
            tick(4);
        end
    endtask

    task wait_for_state;
        input [2:0] expected_state;
        input [255:0] check_name;
        input integer max_cycles;
        begin
            wait_count = 0;
            while ((state_debug !== expected_state) && (wait_count < max_cycles)) begin
                @(posedge clk);
                wait_count = wait_count + 1;
            end
            if (state_debug !== expected_state) begin
                $display("ERROR: timeout waiting for %0s", check_name);
                error_count = error_count + 1;
            end
        end
    endtask

    task wait_for_playback_sample;
        input [15:0] expected_sample;
        input [255:0] check_name;
        input integer max_cycles;
        begin
            wait_count = 0;
            while ((playback_sample_data !== expected_sample) && (wait_count < max_cycles)) begin
                @(posedge clk);
                wait_count = wait_count + 1;
            end
            if (playback_sample_data !== expected_sample) begin
                $display("ERROR: timeout waiting for %0s", check_name);
                error_count = error_count + 1;
            end
        end
    endtask

    task request_output_sample_and_check;
        input [15:0] expected_sample;
        input [255:0] check_name;
        begin
            sample_req = 1'b1;
            @(posedge clk);
            sample_req = 1'b0;
            @(posedge clk);
            if (audio_output !== expected_sample) begin
                $display("ERROR: %0s expected 0x%0h, got 0x%0h", check_name, expected_sample, audio_output);
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
        volume_setting = 4'hF;
        sample_end = 1'b0;
        sample_req = 1'b0;
        audio_input = 16'h0000;
        monitor_enable = 1'b0;
        test_tone_enable = 1'b0;
        ram_rdy = 1'b1;
        ram_max_address = 26'h0FFFFFF;
        ram_rd_data_pres = 1'b0;
        ram_data_out = 16'h0000;
        read_pending = 1'b0;
        pending_read_address = 26'd0;
        read_latency_count = 2'd0;
        error_count = 0;

        for (idx = 0; idx < 64; idx = idx + 1)
            ram_model[idx] = 16'h0000;

        tick(4);
        reset = 1'b0;
        tick(3);

        if (state_debug !== STATE_IDLE) begin
            $display("ERROR: expected idle after reset, got %0d", state_debug);
            error_count = error_count + 1;
        end

        clear_status_flags;
        issue_command(CMD_RECORD);
        wait_for_state(STATE_RECORDING, "STATE_RECORDING", 20);

        send_input_sample(SAMPLE0);
        send_input_sample(SAMPLE1);
        send_input_sample(SAMPLE2);

        issue_command(CMD_STOP);
        wait_for_state(STATE_IDLE, "STATE_IDLE after record stop", 20);

        if (!selected_msg_valid) begin
            $display("ERROR: selected slot should be valid after recording");
            error_count = error_count + 1;
        end
        if (selected_msg_length !== 26'd3) begin
            $display("ERROR: recorded length expected 3, got %0d", selected_msg_length);
            error_count = error_count + 1;
        end

        if (ram_model[0] !== SAMPLE0) begin
            $display("ERROR: RAM sample 0 expected 0x%0h, got 0x%0h", SAMPLE0, ram_model[0]);
            error_count = error_count + 1;
        end
        if (ram_model[1] !== SAMPLE1) begin
            $display("ERROR: RAM sample 1 expected 0x%0h, got 0x%0h", SAMPLE1, ram_model[1]);
            error_count = error_count + 1;
        end
        if (ram_model[2] !== SAMPLE2) begin
            $display("ERROR: RAM sample 2 expected 0x%0h, got 0x%0h", SAMPLE2, ram_model[2]);
            error_count = error_count + 1;
        end

        clear_status_flags;
        issue_command(CMD_PLAY);
        wait_for_state(STATE_PLAYING, "STATE_PLAYING", 20);

        wait_for_playback_sample(SAMPLE0, "first playback sample staged", 50);
        request_output_sample_and_check(SAMPLE0, "playback output sample 0");

        wait_for_playback_sample(SAMPLE1, "second playback sample staged", 50);
        request_output_sample_and_check(SAMPLE1, "playback output sample 1");

        wait_for_playback_sample(SAMPLE2, "third playback sample staged", 50);
        request_output_sample_and_check(SAMPLE2, "playback output sample 2");

        wait_for_state(STATE_IDLE, "STATE_IDLE after playback", 50);

        if (command_done !== 1'b1) begin
            $display("ERROR: command_done should assert at playback completion");
            error_count = error_count + 1;
        end
        if (invalid_command !== 1'b0) begin
            $display("ERROR: invalid_command should remain low during e2e record/play");
            error_count = error_count + 1;
        end

        if (error_count == 0) begin
            $display("PASS: tb_record_play_digital_e2e completed without errors.");
        end else begin
            $display("FAIL: tb_record_play_digital_e2e completed with %0d error(s).", error_count);
        end

        $finish;
    end

endmodule
