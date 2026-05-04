`timescale 1ns / 1ps

// Contract-level testbench for the planned control/status CDC bridge.
//
// This bench is intentionally written against the behavior contract of a
// future bridge module rather than the current top-level implementation. It is
// meant to be activated once `control_cdc_bridge.v` (or the final equivalent
// module name/interface) exists.
//
// Contract under test:
// 1. A one-cycle source-domain command pulse must become exactly one
//    destination-domain command pulse.
// 2. Command payload (command/slot/volume) must remain coherent with that
//    pulse at the destination.
// 3. Short source pulses must not be lost just because the destination clock is
//    slower.
// 4. Back-to-back source commands must not merge or duplicate.
// 5. Source-side clear-status pulses must cross exactly once.
// 6. Destination-side status flags must return to the source domain cleanly.

module tb_control_cdc_bridge_contract;

    reg         src_clk;
    reg         src_reset;
    reg  [7:0]  src_command;
    reg         src_command_strobe;
    reg         src_clear_status;
    reg  [1:0]  src_selected_message;
    reg  [3:0]  src_volume_setting;

    reg         dst_clk;
    reg         dst_reset;
    reg         dst_busy;
    reg         dst_recording;
    reg         dst_playing;
    reg         dst_paused;
    reg         dst_invalid_command;
    reg         dst_command_done;

    wire [7:0]  dst_command;
    wire        dst_command_strobe;
    wire        dst_clear_status;
    wire [1:0]  dst_selected_message;
    wire [3:0]  dst_volume_setting;

    wire        src_busy;
    wire        src_recording;
    wire        src_playing;
    wire        src_paused;
    wire        src_invalid_command;
    wire        src_command_done;

    integer error_count;
    integer wait_count;
    integer pulse_count;

    localparam [7:0] CMD_PLAY   = 8'h01;
    localparam [7:0] CMD_RECORD = 8'h02;
    localparam [7:0] CMD_STOP   = 8'h06;

    // NOTE:
    // This module does not exist yet. The bench is ready to be wired once the
    // RAM-side CDC restructuring introduces the bridge.
    control_cdc_bridge dut (
        .src_clk(src_clk),
        .src_reset(src_reset),
        .src_command(src_command),
        .src_command_strobe(src_command_strobe),
        .src_clear_status(src_clear_status),
        .src_selected_message(src_selected_message),
        .src_volume_setting(src_volume_setting),
        .dst_clk(dst_clk),
        .dst_reset(dst_reset),
        .dst_command(dst_command),
        .dst_command_strobe(dst_command_strobe),
        .dst_clear_status(dst_clear_status),
        .dst_selected_message(dst_selected_message),
        .dst_volume_setting(dst_volume_setting),
        .dst_busy(dst_busy),
        .dst_recording(dst_recording),
        .dst_playing(dst_playing),
        .dst_paused(dst_paused),
        .dst_invalid_command(dst_invalid_command),
        .dst_command_done(dst_command_done),
        .src_busy(src_busy),
        .src_recording(src_recording),
        .src_playing(src_playing),
        .src_paused(src_paused),
        .src_invalid_command(src_invalid_command),
        .src_command_done(src_command_done)
    );

    always #5 src_clk = ~src_clk;   // 100 MHz-like source domain
    always #13 dst_clk = ~dst_clk;  // slower RAM UI-like destination domain

    task tick_src;
        input integer cycles;
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1)
                @(posedge src_clk);
        end
    endtask

    task tick_dst;
        input integer cycles;
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1)
                @(posedge dst_clk);
        end
    endtask

    task issue_src_command;
        input [7:0] cmd;
        input [1:0] slot_id;
        input [3:0] volume_value;
        begin
            src_command          = cmd;
            src_selected_message = slot_id;
            src_volume_setting   = volume_value;
            src_command_strobe   = 1'b1;
            @(posedge src_clk);
            src_command_strobe   = 1'b0;
            src_command          = 8'h00;
        end
    endtask

    task pulse_src_clear_status;
        begin
            src_clear_status = 1'b1;
            @(posedge src_clk);
            src_clear_status = 1'b0;
        end
    endtask

    task wait_for_single_dst_command;
        input [7:0] expected_cmd;
        input [1:0] expected_slot;
        input [3:0] expected_volume;
        input [255:0] check_name;
        begin
            wait_count = 0;
            pulse_count = 0;

            while ((pulse_count == 0) && (wait_count < 80)) begin
                @(posedge dst_clk);
                #1;
                wait_count = wait_count + 1;
                if (dst_command_strobe) begin
                    pulse_count = pulse_count + 1;
                    if (dst_command !== expected_cmd) begin
                        $display("ERROR: %0s wrong command expected 0x%0h got 0x%0h",
                                 check_name, expected_cmd, dst_command);
                        error_count = error_count + 1;
                    end
                    if (dst_selected_message !== expected_slot) begin
                        $display("ERROR: %0s wrong slot expected %0d got %0d",
                                 check_name, expected_slot, dst_selected_message);
                        error_count = error_count + 1;
                    end
                    if (dst_volume_setting !== expected_volume) begin
                        $display("ERROR: %0s wrong volume expected 0x%0h got 0x%0h",
                                 check_name, expected_volume, dst_volume_setting);
                        error_count = error_count + 1;
                    end
                end
            end

            if (pulse_count == 0) begin
                $display("ERROR: timeout waiting for %0s", check_name);
                error_count = error_count + 1;
            end

            // Make sure the bridge does not duplicate the pulse later.
            pulse_count = 0;
            repeat (20) begin
                @(posedge dst_clk);
                #1;
                if (dst_command_strobe) begin
                    pulse_count = pulse_count + 1;
                    $display("DEBUG: extra dst command pulse during %0s: cmd=0x%0h slot=%0d vol=0x%0h t=%0t req_tgl=%0b ack_sync=%0b ack_seen=%0b inflight=%0b q_valid=%0b req_sync=%0b req_seen=%0b",
                             check_name, dst_command, dst_selected_message,
                             dst_volume_setting, $time,
                             dut.cmd_req_toggle_src,
                             dut.cmd_ack_sync_src[1],
                             dut.cmd_ack_seen_src,
                             dut.cmd_inflight_src,
                             dut.cmd_queue_valid_src,
                             dut.cmd_req_sync_dst[1],
                             dut.cmd_req_seen_dst);
                end
            end
            if (pulse_count != 0) begin
                $display("ERROR: %0s duplicated at destination (%0d extra pulse(s))",
                         check_name, pulse_count);
                error_count = error_count + 1;
            end
        end
    endtask

    task wait_for_single_dst_clear_status;
        input [255:0] check_name;
        begin
            wait_count = 0;
            pulse_count = 0;

            while ((pulse_count == 0) && (wait_count < 80)) begin
                @(posedge dst_clk);
                #1;
                wait_count = wait_count + 1;
                if (dst_clear_status)
                    pulse_count = pulse_count + 1;
            end

            if (pulse_count == 0) begin
                $display("ERROR: timeout waiting for %0s", check_name);
                error_count = error_count + 1;
            end

            pulse_count = 0;
            repeat (20) begin
                @(posedge dst_clk);
                #1;
                if (dst_clear_status)
                    pulse_count = pulse_count + 1;
            end
            if (pulse_count != 0) begin
                $display("ERROR: %0s duplicated at destination (%0d extra pulse(s))",
                         check_name, pulse_count);
                error_count = error_count + 1;
            end
        end
    endtask

    task wait_for_src_status;
        input expected_busy;
        input expected_recording;
        input expected_playing;
        input expected_paused;
        input expected_invalid;
        input expected_done;
        input [255:0] check_name;
        begin
            wait_count = 0;
            while (((src_busy !== expected_busy) ||
                    (src_recording !== expected_recording) ||
                    (src_playing !== expected_playing) ||
                    (src_paused !== expected_paused) ||
                    (src_invalid_command !== expected_invalid) ||
                    (src_command_done !== expected_done)) &&
                   (wait_count < 80)) begin
                @(posedge src_clk);
                wait_count = wait_count + 1;
            end

            if ((src_busy !== expected_busy) ||
                (src_recording !== expected_recording) ||
                (src_playing !== expected_playing) ||
                (src_paused !== expected_paused) ||
                (src_invalid_command !== expected_invalid) ||
                (src_command_done !== expected_done)) begin
                $display("ERROR: timeout waiting for %0s", check_name);
                error_count = error_count + 1;
            end
        end
    endtask

    initial begin
        src_clk = 1'b0;
        src_reset = 1'b1;
        src_command = 8'h00;
        src_command_strobe = 1'b0;
        src_clear_status = 1'b0;
        src_selected_message = 2'b00;
        src_volume_setting = 4'h8;

        dst_clk = 1'b0;
        dst_reset = 1'b1;
        dst_busy = 1'b0;
        dst_recording = 1'b0;
        dst_playing = 1'b0;
        dst_paused = 1'b0;
        dst_invalid_command = 1'b0;
        dst_command_done = 1'b0;

        error_count = 0;

        tick_src(4);
        tick_dst(2);
        src_reset = 1'b0;
        dst_reset = 1'b0;
        tick_src(3);

        // C1: short source-domain command pulse must arrive once with coherent payload.
        issue_src_command(CMD_RECORD, 2'b01, 4'hD);
        wait_for_single_dst_command(CMD_RECORD, 2'b01, 4'hD,
                                    "record command crossing");

        // C2: back-to-back commands must not merge or duplicate.
        issue_src_command(CMD_PLAY, 2'b00, 4'h4);
        wait_for_single_dst_command(CMD_PLAY, 2'b00, 4'h4,
                                    "play command crossing");
        // Diagnostic separation: leave a destination-domain gap so the
        // "no extra pulses" window for PLAY cannot accidentally count the
        // later STOP command as a duplicate PLAY pulse.
        tick_dst(30);
        issue_src_command(CMD_STOP, 2'b00, 4'h4);
        wait_for_single_dst_command(CMD_STOP, 2'b00, 4'h4,
                                    "stop command crossing");

        // C3: clear-status pulse must cross exactly once.
        pulse_src_clear_status;
        wait_for_single_dst_clear_status("clear-status crossing");

        // C4: destination status must return cleanly to the source domain.
        dst_busy = 1'b1;
        dst_recording = 1'b1;
        dst_playing = 1'b0;
        dst_paused = 1'b0;
        dst_invalid_command = 1'b0;
        dst_command_done = 1'b0;
        wait_for_src_status(1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                            "recording status return");

        dst_busy = 1'b0;
        dst_recording = 1'b0;
        dst_playing = 1'b0;
        dst_paused = 1'b0;
        dst_invalid_command = 1'b0;
        dst_command_done = 1'b1;
        wait_for_src_status(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1,
                            "done status return");

        dst_command_done = 1'b0;
        dst_invalid_command = 1'b1;
        wait_for_src_status(1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0,
                            "invalid status return");

        if (error_count == 0) begin
            $display("PASS: tb_control_cdc_bridge_contract completed without errors.");
        end else begin
            $display("FAIL: tb_control_cdc_bridge_contract completed with %0d error(s).", error_count);
        end

        $finish;
    end

endmodule
