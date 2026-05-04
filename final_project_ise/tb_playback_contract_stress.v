`timescale 1ns / 1ps

module tb_playback_contract_stress;

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

    reg  [15:0] ram_model [0:127];
    reg         read_pending;
    reg  [25:0] pending_read_address;
    reg  [2:0]  pending_read_latency;
    reg         data_waiting_for_ack;
    reg  [15:0] pending_read_data;
    reg  [2:0]  latency_pattern_idx;

    integer error_count;
    integer idx;
    integer wait_count;

    localparam [7:0] CMD_PLAY   = 8'h01;
    localparam [7:0] CMD_RECORD = 8'h02;
    localparam [7:0] CMD_STOP   = 8'h06;

    localparam [2:0] STATE_IDLE      = 3'd0;
    localparam [2:0] STATE_RECORDING = 3'd1;
    localparam [2:0] STATE_PLAYING   = 3'd2;

    localparam [15:0] SLOT0_A0 = 16'h1111;
    localparam [15:0] SLOT0_A1 = 16'h2222;
    localparam [15:0] SLOT0_A2 = 16'h3333;
    localparam [15:0] SLOT1_B0 = 16'h4444;
    localparam [15:0] SLOT1_B1 = 16'h5555;
    localparam [15:0] SLOT1_B2 = 16'h6666;
    localparam [25:0] SLOT1_BASE = 26'd4194304;

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

    function [2:0] next_latency;
        input [2:0] pattern_idx;
        begin
            case (pattern_idx)
                3'd0: next_latency = 3'd4;
                3'd1: next_latency = 3'd1;
                3'd2: next_latency = 3'd3;
                3'd3: next_latency = 3'd2;
                3'd4: next_latency = 3'd5;
                default: next_latency = 3'd2;
            endcase
        end
    endfunction

    function [6:0] ram_model_index;
        input [25:0] logical_address;
        begin
            if (logical_address >= SLOT1_BASE)
                ram_model_index = 7'd64 + logical_address[5:0];
            else
                ram_model_index = {1'b0, logical_address[5:0]};
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            ram_rd_data_pres      <= 1'b0;
            ram_data_out          <= 16'h0000;
            read_pending          <= 1'b0;
            pending_read_address  <= 26'd0;
            pending_read_latency  <= 3'd0;
            data_waiting_for_ack  <= 1'b0;
            pending_read_data     <= 16'h0000;
            latency_pattern_idx   <= 3'd0;
        end else begin
            ram_rd_data_pres <= data_waiting_for_ack;
            if (data_waiting_for_ack)
                ram_data_out <= pending_read_data;

            if (ram_write_enable) begin
                ram_model[ram_model_index(ram_address)] <= ram_data_in;
            end

            if (ram_read_request && !read_pending && !data_waiting_for_ack) begin
                read_pending         <= 1'b1;
                pending_read_address <= ram_address;
                pending_read_latency <= next_latency(latency_pattern_idx);
                latency_pattern_idx  <= latency_pattern_idx + 3'd1;
            end

            if (read_pending) begin
                if (pending_read_latency != 3'd0) begin
                    pending_read_latency <= pending_read_latency - 3'd1;
                end else begin
                    pending_read_data    <= ram_model[ram_model_index(pending_read_address)];
                    data_waiting_for_ack <= 1'b1;
                    read_pending         <= 1'b0;
                end
            end

            if (data_waiting_for_ack && ram_read_ack) begin
                data_waiting_for_ack <= 1'b0;
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

    task record_three_samples;
        input [1:0] slot_id;
        input [15:0] s0;
        input [15:0] s1;
        input [15:0] s2;
        begin
            selected_message = slot_id;
            clear_status_flags;
            issue_command(CMD_RECORD);
            wait_for_state(STATE_RECORDING, "STATE_RECORDING", 20);
            send_input_sample(s0);
            send_input_sample(s1);
            send_input_sample(s2);
            issue_command(CMD_STOP);
            wait_for_state(STATE_IDLE, "STATE_IDLE after record stop", 30);
            clear_status_flags;
        end
    endtask

    task check_first_sample_after_play;
        input [15:0] expected_first_sample;
        input [255:0] check_name;
        begin
            clear_status_flags;
            issue_command(CMD_PLAY);
            wait_for_state(STATE_PLAYING, "STATE_PLAYING", 20);
            request_output_sample_and_check(expected_first_sample, check_name);
            issue_command(CMD_STOP);
            wait_for_state(STATE_IDLE, "STATE_IDLE after stop", 30);
            clear_status_flags;
        end
    endtask

    task stop_mid_read_then_restart_and_check;
        input [1:0] slot_id;
        input [15:0] expected_first_sample;
        input [255:0] check_name;
        begin
            selected_message = slot_id;
            clear_status_flags;
            issue_command(CMD_PLAY);
            wait_for_state(STATE_PLAYING, "STATE_PLAYING for stop/restart", 20);

            // Stop while a DDR read is still in flight and before the first
            // returned sample has been acknowledged through the playback path.
            tick(1);
            issue_command(CMD_STOP);
            wait_for_state(STATE_IDLE, "STATE_IDLE after mid-read stop", 30);
            clear_status_flags;

            issue_command(CMD_PLAY);
            wait_for_state(STATE_PLAYING, "STATE_PLAYING after restart", 20);
            request_output_sample_and_check(expected_first_sample, check_name);
            issue_command(CMD_STOP);
            wait_for_state(STATE_IDLE, "STATE_IDLE after restart stop", 30);
            clear_status_flags;
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
        pending_read_latency = 3'd0;
        data_waiting_for_ack = 1'b0;
        pending_read_data = 16'h0000;
        latency_pattern_idx = 3'd0;
        error_count = 0;

        for (idx = 0; idx < 128; idx = idx + 1)
            ram_model[idx] = 16'h0000;

        tick(4);
        reset = 1'b0;
        tick(3);

        if (state_debug !== STATE_IDLE) begin
            $display("ERROR: expected idle after reset, got %0d", state_debug);
            error_count = error_count + 1;
        end

        record_three_samples(2'b00, SLOT0_A0, SLOT0_A1, SLOT0_A2);
        record_three_samples(2'b01, SLOT1_B0, SLOT1_B1, SLOT1_B2);

        // Contract check 1:
        // The first output sample produced after playback starts should be the
        // first recorded sample of the clip, not zero/stale data.
        selected_message = 2'b00;
        check_first_sample_after_play(SLOT0_A0, "slot0 first sample after play");

        // Contract check 2:
        // Stopping mid-read must not contaminate the next playback attempt.
        stop_mid_read_then_restart_and_check(2'b00, SLOT0_A0,
                                             "slot0 restart first sample");

        // Contract check 3:
        // A nonzero slot must behave the same way.
        stop_mid_read_then_restart_and_check(2'b01, SLOT1_B0,
                                             "slot1 restart first sample");

        if (error_count == 0) begin
            $display("PASS: tb_playback_contract_stress completed without errors.");
        end else begin
            $display("FAIL: tb_playback_contract_stress completed with %0d error(s).", error_count);
        end

        $finish;
    end

endmodule
