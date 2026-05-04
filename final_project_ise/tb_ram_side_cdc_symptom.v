`timescale 1ns / 1ps

// Pre/post bench for the current RAM-side CDC topology.
//
// This bench intentionally models the RAM side as a separate slower clock
// domain that only samples request/ack/data buses on its own clock edge.
// That means the current direct-crossing topology should fail, while a proper
// bridge/re-homing fix should make the same bench pass.

module tb_ram_side_cdc_symptom;

    reg         src_clk;
    reg         src_reset;
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
    wire [7:0]  bridge_command;
    wire        bridge_command_strobe;
    wire        bridge_clear_status;
    wire [1:0]  bridge_selected_message;
    wire [3:0]  bridge_volume_setting;
    wire        command_done_dst;
    wire        invalid_command_dst;
    wire        busy_dst;
    wire        recording_dst;
    wire        playing_dst;
    wire        paused_dst;
    wire        deleting_dst;

    reg         dst_clk;
    reg         ram_rd_data_pres;
    reg  [15:0] ram_data_out;

    reg [15:0] ram_model [0:31];
    reg        read_pending;
    reg [25:0] pending_read_address;
    reg        data_waiting_for_ack;
    reg [15:0] pending_read_data;

    integer error_count;
    integer idx;
    integer wait_count;

    localparam [7:0] CMD_PLAY   = 8'h01;
    localparam [7:0] CMD_RECORD = 8'h02;
    localparam [7:0] CMD_STOP   = 8'h06;

    localparam [2:0] STATE_IDLE      = 3'd0;
    localparam [2:0] STATE_RECORDING = 3'd1;
    localparam [2:0] STATE_PLAYING   = 3'd2;

    localparam [15:0] SAMPLE0 = 16'h1111;
    localparam [15:0] SAMPLE1 = 16'h2222;
    localparam [15:0] SAMPLE2 = 16'h3333;

    control_cdc_bridge bridge (
        .src_clk(src_clk),
        .src_reset(src_reset),
        .src_command(command),
        .src_command_strobe(command_strobe),
        .src_clear_status(clear_status),
        .src_selected_message(selected_message),
        .src_volume_setting(volume_setting),
        .dst_clk(dst_clk),
        .dst_reset(src_reset),
        .dst_command(bridge_command),
        .dst_command_strobe(bridge_command_strobe),
        .dst_clear_status(bridge_clear_status),
        .dst_selected_message(bridge_selected_message),
        .dst_volume_setting(bridge_volume_setting),
        .dst_busy(busy_dst),
        .dst_recording(recording_dst),
        .dst_playing(playing_dst),
        .dst_paused(paused_dst),
        .dst_invalid_command(invalid_command_dst),
        .dst_command_done(command_done_dst),
        .src_busy(busy),
        .src_recording(recording),
        .src_playing(playing),
        .src_paused(paused),
        .src_invalid_command(invalid_command),
        .src_command_done(command_done)
    );

    recorder_control dut (
        .clk(dst_clk),
        .reset(src_reset),
        .command(bridge_command),
        .command_strobe(bridge_command_strobe),
        .clear_status(bridge_clear_status),
        .selected_message(bridge_selected_message),
        .volume_setting(bridge_volume_setting),
        .recorder_input_sample(recorder_input_sample),
        .recorder_input_valid(recorder_input_valid),
        .recorder_input_toggle(recorder_input_toggle),
        .playback_request_toggle(playback_request_toggle),
        .ram_rdy(ram_rdy),
        .ram_rd_data_pres(ram_rd_data_pres),
        .ram_data_out(ram_data_out),
        .ram_max_address(ram_max_address),
        .command_done(command_done_dst),
        .invalid_command(invalid_command_dst),
        .busy(busy_dst),
        .recording(recording_dst),
        .playing(playing_dst),
        .paused(paused_dst),
        .deleting(deleting_dst),
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

    always #5 src_clk = ~src_clk;   // 100 MHz-like control domain
    initial begin
        dst_clk = 1'b0;
        #13;
        forever #15 dst_clk = ~dst_clk; // 33.3 MHz-like RAM user domain, phase-shifted
    end

    // Hostile RAM-side model:
    // - writes only when write_enable is high exactly on dst_clk edge
    // - read requests only seen when read_request is high exactly on dst_clk edge
    // - returned data persists until read_ack is seen on a dst_clk edge
    always @(posedge dst_clk) begin
        if (src_reset) begin
            ram_rd_data_pres     <= 1'b0;
            ram_data_out         <= 16'h0000;
            read_pending         <= 1'b0;
            pending_read_address <= 26'd0;
            data_waiting_for_ack <= 1'b0;
            pending_read_data    <= 16'h0000;
        end else begin
            if (ram_write_enable) begin
                ram_model[ram_address[4:0]] <= ram_data_in;
            end

            if (ram_read_request && !read_pending && !data_waiting_for_ack) begin
                read_pending         <= 1'b1;
                pending_read_address <= ram_address;
            end else if (read_pending) begin
                pending_read_data    <= ram_model[pending_read_address[4:0]];
                ram_data_out         <= ram_model[pending_read_address[4:0]];
                ram_rd_data_pres     <= 1'b1;
                data_waiting_for_ack <= 1'b1;
                read_pending         <= 1'b0;
            end

            if (data_waiting_for_ack && ram_read_ack) begin
                ram_rd_data_pres     <= 1'b0;
                data_waiting_for_ack <= 1'b0;
            end
        end
    end

    task tick_src;
        input integer cycles;
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1)
                @(posedge src_clk);
        end
    endtask

    task wait_for_state;
        input [2:0] expected_state;
        input [255:0] check_name;
        input integer max_cycles;
        begin
            wait_count = 0;
            while ((state_debug !== expected_state) && (wait_count < max_cycles)) begin
                @(posedge src_clk);
                wait_count = wait_count + 1;
            end
            if (state_debug !== expected_state) begin
                $display("ERROR: timeout waiting for %0s", check_name);
                error_count = error_count + 1;
            end
        end
    endtask

    task wait_for_state_dst;
        input [2:0] expected_state;
        input [255:0] check_name;
        input integer max_cycles;
        begin
            wait_count = 0;
            while ((state_debug !== expected_state) && (wait_count < max_cycles)) begin
                @(posedge dst_clk);
                wait_count = wait_count + 1;
            end
            if (state_debug !== expected_state) begin
                $display("ERROR: timeout waiting for %0s", check_name);
                error_count = error_count + 1;
            end
        end
    endtask

    task clear_status_flags;
        begin
            clear_status = 1'b1;
            @(posedge src_clk);
            clear_status = 1'b0;
            @(posedge src_clk);
        end
    endtask

    task issue_misaligned_command;
        input [7:0] cmd;
        begin
            @(posedge dst_clk);
            @(posedge src_clk);
            @(posedge src_clk);
            command = cmd;
            command_strobe = 1'b1;
            @(posedge src_clk);
            command_strobe = 1'b0;
            command = 8'h00;
            @(posedge src_clk);
        end
    endtask

    task send_record_sample_for_playback_test;
        input [15:0] sample_value;
        begin
            recorder_input_sample = sample_value;
            recorder_input_toggle = ~recorder_input_toggle;
            // Keep the sample value stable across multiple dst_clk edges so
            // this bench does not accidentally turn into a recorder-input CDC test.
            @(posedge dst_clk);
            @(posedge dst_clk);
            @(posedge dst_clk);
        end
    endtask

    initial begin
        src_clk = 1'b0;
        src_reset = 1'b1;
        command = 8'h00;
        command_strobe = 1'b0;
        clear_status = 1'b0;
        selected_message = 2'b00;
        volume_setting = 4'hF;
        recorder_input_sample = 16'h0000;
        recorder_input_valid = 1'b0;
        recorder_input_toggle = 1'b0;
        playback_request_toggle = 1'b0;
        ram_rdy = 1'b1;
        ram_max_address = 26'h0FFFFFF;
        ram_rd_data_pres = 1'b0;
        ram_data_out = 16'h0000;
        read_pending = 1'b0;
        pending_read_address = 26'd0;
        data_waiting_for_ack = 1'b0;
        pending_read_data = 16'h0000;
        error_count = 0;

        for (idx = 0; idx < 32; idx = idx + 1)
            ram_model[idx] = 16'h0000;

        tick_src(4);
        src_reset = 1'b0;
        tick_src(4);

        if (state_debug !== STATE_IDLE) begin
            $display("ERROR: expected idle after reset, got %0d", state_debug);
            error_count = error_count + 1;
        end

        clear_status_flags;
        issue_misaligned_command(CMD_RECORD);
        wait_for_state(STATE_RECORDING, "STATE_RECORDING", 20);

        send_record_sample_for_playback_test(SAMPLE0);
        send_record_sample_for_playback_test(SAMPLE1);
        send_record_sample_for_playback_test(SAMPLE2);

        issue_misaligned_command(CMD_STOP);
        wait_for_state(STATE_IDLE, "STATE_IDLE after record stop", 40);

        if (!selected_msg_valid) begin
            $display("ERROR: slot should look valid after recording");
            error_count = error_count + 1;
        end
        if (ram_model[0] !== SAMPLE0) begin
            $display("ERROR: recorded RAM sample 0 expected 0x%0h, got 0x%0h",
                     SAMPLE0, ram_model[0]);
            error_count = error_count + 1;
        end
        if (ram_model[1] !== SAMPLE1) begin
            $display("ERROR: recorded RAM sample 1 expected 0x%0h, got 0x%0h",
                     SAMPLE1, ram_model[1]);
            error_count = error_count + 1;
        end
        if (ram_model[2] !== SAMPLE2) begin
            $display("ERROR: recorded RAM sample 2 expected 0x%0h, got 0x%0h",
                     SAMPLE2, ram_model[2]);
            error_count = error_count + 1;
        end

        clear_status_flags;
        issue_misaligned_command(CMD_PLAY);

        // Contract:
        // With a correct RAM-side CDC fix, playback should still be able to
        // prime and produce the first recorded sample even when the RAM side
        // only samples requests on dst_clk.
        wait_for_state_dst(STATE_PLAYING, "STATE_PLAYING after misaligned play", 120);
        if (state_debug == STATE_PLAYING) begin
            if (playback_sample_data !== SAMPLE0) begin
                $display("ERROR: first playback sample expected 0x%0h, got 0x%0h",
                         SAMPLE0, playback_sample_data);
                error_count = error_count + 1;
            end
        end

        if (error_count == 0) begin
            $display("PASS: tb_ram_side_cdc_symptom completed without errors.");
        end else begin
            $display("FAIL: tb_ram_side_cdc_symptom completed with %0d error(s).", error_count);
        end

        $finish;
    end

endmodule
