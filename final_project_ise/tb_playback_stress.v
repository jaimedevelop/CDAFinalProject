`timescale 1ns / 1ps

// Stress testbench: playback contract under variable DDR read latency.
// Verifies that (1) the first output sample after CMD_PLAY is always the
// first recorded sample, and (2) a mid-read STOP does not contaminate the
// next playback attempt.  Tests both slot 0 and a nonzero slot.

module tb_playback_stress;

// ---------------------------------------------------------------------------
// DUT / sub-module inputs
// ---------------------------------------------------------------------------
reg         clk;
reg         reset;
reg  [7:0]  cmd_in;
reg         cmd_strobe;
reg         ack_status;
reg  [1:0]  slot_sel;
reg  [3:0]  vol_in;
reg         codec_end;
reg         codec_req;
reg  [15:0] adc_word;
reg         mon_en;
reg         tone_en;
reg         ddr_rdy;
reg  [25:0] ddr_max_addr;

// ---------------------------------------------------------------------------
// Interconnect
// ---------------------------------------------------------------------------
wire [15:0] dac_word;
wire [15:0] path_sample;
wire        path_sample_valid;
wire        path_sample_tog;
wire        spk_req_tog;

// ---------------------------------------------------------------------------
// recorder_control outputs
// ---------------------------------------------------------------------------
wire        op_done;
wire        op_invalid;
wire        dev_busy;
wire        dev_recording;
wire        dev_playing;
wire        dev_paused;
wire        dev_deleting;
wire        slot_valid;
wire        slot_full;
wire [25:0] slot_start;
wire [25:0] slot_len;
wire        has_free_slot;
wire        layout_fits;
wire [2:0]  fsm_state;
wire [3:0]  vol_latched;
wire        spk_active;
wire [15:0] spk_sample;
wire [25:0] ddr_addr;
wire [15:0] ddr_wr_word;
wire        ddr_wr_en;
wire        ddr_rd_req;
wire        ddr_rd_ack;

// ---------------------------------------------------------------------------
// RAM model — 128 entries, variable-latency read path
// ---------------------------------------------------------------------------
reg         ddr_rd_avail;
reg  [15:0] ddr_rd_word;

reg  [15:0] mem [0:127];
reg         rd_in_flight;
reg  [25:0] rd_pend_addr;
reg  [2:0]  rd_countdown;
reg         rd_data_held;       // data_waiting_for_ack
reg  [15:0] rd_held_word;       // pending_read_data
reg  [2:0]  lat_idx;            // latency_pattern_idx

// ---------------------------------------------------------------------------
// Test bookkeeping
// ---------------------------------------------------------------------------
integer fail_count;
integer poll_count;
integer mi;

// ---------------------------------------------------------------------------
// Opcode / state / sample aliases
// ---------------------------------------------------------------------------
localparam [7:0] OP_PLAY   = 8'h01;
localparam [7:0] OP_RECORD = 8'h02;
localparam [7:0] OP_STOP   = 8'h06;

localparam [2:0] ST_IDLE = 3'd0;
localparam [2:0] ST_REC  = 3'd1;
localparam [2:0] ST_PLAY = 3'd2;

localparam [15:0] S0_W0 = 16'h1111;
localparam [15:0] S0_W1 = 16'h2222;
localparam [15:0] S0_W2 = 16'h3333;
localparam [15:0] S1_W0 = 16'h4444;
localparam [15:0] S1_W1 = 16'h5555;
localparam [15:0] S1_W2 = 16'h6666;

localparam [25:0] BASE_S1 = 26'd4194304;

// ---------------------------------------------------------------------------
// Sub-module instantiation
// ---------------------------------------------------------------------------
audio_sample_path sample_path (
    .clk                    (clk),
    .reset                  (reset),
    .sample_end             (codec_end),
    .sample_req             (codec_req),
    .audio_input            (adc_word),
    .playback_enable        (spk_active),
    .monitor_enable         (mon_en),
    .test_tone_enable       (tone_en),
    .playback_sample        (spk_sample),
    .volume_setting         (vol_latched),
    .audio_output           (dac_word),
    .recorder_sample        (path_sample),
    .recorder_sample_valid  (path_sample_valid),
    .recorder_sample_toggle (path_sample_tog),
    .playback_request_toggle(spk_req_tog)
);

recorder_control ctrl (
    .clk                    (clk),
    .reset                  (reset),
    .command                (cmd_in),
    .command_strobe         (cmd_strobe),
    .clear_status           (ack_status),
    .selected_message       (slot_sel),
    .volume_setting         (vol_in),
    .recorder_input_sample  (path_sample),
    .recorder_input_valid   (path_sample_valid),
    .recorder_input_toggle  (path_sample_tog),
    .playback_request_toggle(spk_req_tog),
    .ram_rdy                (ddr_rdy),
    .ram_rd_data_pres       (ddr_rd_avail),
    .ram_data_out           (ddr_rd_word),
    .ram_max_address        (ddr_max_addr),
    .command_done           (op_done),
    .invalid_command        (op_invalid),
    .busy                   (dev_busy),
    .recording              (dev_recording),
    .playing                (dev_playing),
    .paused                 (dev_paused),
    .deleting               (dev_deleting),
    .selected_msg_valid     (slot_valid),
    .selected_msg_full      (slot_full),
    .selected_msg_start     (slot_start),
    .selected_msg_length    (slot_len),
    .any_empty_slot         (has_free_slot),
    .slot_plan_fits_ram     (layout_fits),
    .state_debug            (fsm_state),
    .latched_volume_setting (vol_latched),
    .playback_enable        (spk_active),
    .playback_sample_data   (spk_sample),
    .ram_address            (ddr_addr),
    .ram_data_in            (ddr_wr_word),
    .ram_write_enable       (ddr_wr_en),
    .ram_read_request       (ddr_rd_req),
    .ram_read_ack           (ddr_rd_ack)
);

// ---------------------------------------------------------------------------
// 100 MHz clock
// ---------------------------------------------------------------------------
always #5 clk = ~clk;

// ---------------------------------------------------------------------------
// Variable-latency RAM model
// Latency cycles rotate through the pattern {4,1,3,2,5} per transaction.
// ---------------------------------------------------------------------------
function [2:0] pick_latency;
    input [2:0] idx;
    begin
        case (idx)
            3'd0:    pick_latency = 3'd4;
            3'd1:    pick_latency = 3'd1;
            3'd2:    pick_latency = 3'd3;
            3'd3:    pick_latency = 3'd2;
            3'd4:    pick_latency = 3'd5;
            default: pick_latency = 3'd2;
        endcase
    end
endfunction

// Map a logical DDR address to a mem[] index.
// Slot 1 addresses (>= BASE_S1) land in the upper half of the array.
function [6:0] mem_idx;
    input [25:0] logical_addr;
    begin
        if (logical_addr >= BASE_S1)
            mem_idx = 7'd64 + logical_addr[5:0];
        else
            mem_idx = {1'b0, logical_addr[5:0]};
    end
endfunction

always @(posedge clk) begin
    if (reset) begin
        ddr_rd_avail  <= 1'b0;
        ddr_rd_word   <= 16'h0000;
        rd_in_flight  <= 1'b0;
        rd_pend_addr  <= 26'd0;
        rd_countdown  <= 3'd0;
        rd_data_held  <= 1'b0;
        rd_held_word  <= 16'h0000;
        lat_idx       <= 3'd0;
    end else begin
        // Hold rd_data_pres high until ack
        ddr_rd_avail <= rd_data_held;
        if (rd_data_held)
            ddr_rd_word <= rd_held_word;

        // Write path
        if (ddr_wr_en)
            mem[mem_idx(ddr_addr)] <= ddr_wr_word;

        // Accept a new read only when the bus is fully clear
        if (ddr_rd_req && !rd_in_flight && !rd_data_held) begin
            rd_in_flight <= 1'b1;
            rd_pend_addr <= ddr_addr;
            rd_countdown <= pick_latency(lat_idx);
            lat_idx      <= lat_idx + 3'd1;
        end

        // Count down then present data
        if (rd_in_flight) begin
            if (rd_countdown != 3'd0) begin
                rd_countdown <= rd_countdown - 3'd1;
            end else begin
                rd_held_word <= mem[mem_idx(rd_pend_addr)];
                rd_data_held <= 1'b1;
                rd_in_flight <= 1'b0;
            end
        end

        // Clear held data once acked
        if (rd_data_held && ddr_rd_ack)
            rd_data_held <= 1'b0;
    end
end

// ---------------------------------------------------------------------------
// Tasks — timing
// ---------------------------------------------------------------------------
task advance;
    input integer n;
    integer j;
    begin
        for (j = 0; j < n; j = j + 1)
            @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// Tasks — control
// ---------------------------------------------------------------------------
task deassert_flags;
    begin
        ack_status = 1'b1;
        @(posedge clk);
        ack_status = 1'b0;
        @(posedge clk);
    end
endtask

task send_cmd;
    input [7:0] op;
    begin
        cmd_in     = op;
        cmd_strobe = 1'b1;
        @(posedge clk);
        cmd_strobe = 1'b0;
        cmd_in     = 8'h00;
        @(posedge clk);
    end
endtask

task push_adc_sample;
    input [15:0] val;
    begin
        adc_word  = val;
        codec_end = 1'b1;
        @(posedge clk);
        codec_end = 1'b0;
        advance(4);
    end
endtask

// ---------------------------------------------------------------------------
// Tasks — polling
// ---------------------------------------------------------------------------
task wait_for_fsm;
    input [2:0]   target;
    input [255:0] label;
    input integer limit;
    begin
        poll_count = 0;
        while ((fsm_state !== target) && (poll_count < limit)) begin
            @(posedge clk);
            poll_count = poll_count + 1;
        end
        if (fsm_state !== target) begin
            $display("TIMEOUT waiting for FSM=%0d [%0s]", target, label);
            fail_count = fail_count + 1;
        end
    end
endtask

// ---------------------------------------------------------------------------
// Tasks — assertion + output check
// ---------------------------------------------------------------------------
task pull_and_check;
    input [15:0]  expected;
    input [255:0] label;
    begin
        codec_req = 1'b1;
        @(posedge clk);
        codec_req = 1'b0;
        @(posedge clk);
        if (dac_word !== expected) begin
            $display("FAIL [%0s]: expected 0x%04h, got 0x%04h", label, expected, dac_word);
            fail_count = fail_count + 1;
        end
    end
endtask

// ---------------------------------------------------------------------------
// Compound tasks
// ---------------------------------------------------------------------------

// Record three samples into the given slot, then return to idle.
task record_clip;
    input [1:0]  tgt_slot;
    input [15:0] w0;
    input [15:0] w1;
    input [15:0] w2;
    begin
        slot_sel = tgt_slot;
        deassert_flags;
        send_cmd(OP_RECORD);
        wait_for_fsm(ST_REC, "ST_REC", 20);
        push_adc_sample(w0);
        push_adc_sample(w1);
        push_adc_sample(w2);
        send_cmd(OP_STOP);
        wait_for_fsm(ST_IDLE, "ST_IDLE after record", 30);
        deassert_flags;
    end
endtask

// Play a slot, verify the first output sample, then stop.
task play_and_check_first;
    input [15:0]  exp_first;
    input [255:0] label;
    begin
        deassert_flags;
        send_cmd(OP_PLAY);
        wait_for_fsm(ST_PLAY, "ST_PLAY", 20);
        pull_and_check(exp_first, label);
        send_cmd(OP_STOP);
        wait_for_fsm(ST_IDLE, "ST_IDLE after play+stop", 30);
        deassert_flags;
    end
endtask

// Stop mid-read, then restart and verify the first output sample is clean.
task stop_restart_check;
    input [1:0]   tgt_slot;
    input [15:0]  exp_first;
    input [255:0] label;
    begin
        slot_sel = tgt_slot;
        deassert_flags;
        send_cmd(OP_PLAY);
        wait_for_fsm(ST_PLAY, "ST_PLAY for stop/restart", 20);

        // Interrupt while a DDR read is likely still in flight
        advance(1);
        send_cmd(OP_STOP);
        wait_for_fsm(ST_IDLE, "ST_IDLE after mid-read stop", 30);
        deassert_flags;

        // Restart — first sample must still be the recorded first word
        send_cmd(OP_PLAY);
        wait_for_fsm(ST_PLAY, "ST_PLAY after restart", 20);
        pull_and_check(exp_first, label);
        send_cmd(OP_STOP);
        wait_for_fsm(ST_IDLE, "ST_IDLE after restart stop", 30);
        deassert_flags;
    end
endtask

// ---------------------------------------------------------------------------
// Stimulus
// ---------------------------------------------------------------------------
initial begin
    clk          = 1'b0;
    reset        = 1'b1;
    cmd_in       = 8'h00;
    cmd_strobe   = 1'b0;
    ack_status   = 1'b0;
    slot_sel     = 2'b00;
    vol_in       = 4'hF;
    codec_end    = 1'b0;
    codec_req    = 1'b0;
    adc_word     = 16'h0000;
    mon_en       = 1'b0;
    tone_en      = 1'b0;
    ddr_rdy      = 1'b1;
    ddr_max_addr = 26'h0FFFFFF;
    ddr_rd_avail = 1'b0;
    ddr_rd_word  = 16'h0000;
    rd_in_flight = 1'b0;
    rd_pend_addr = 26'd0;
    rd_countdown = 3'd0;
    rd_data_held = 1'b0;
    rd_held_word = 16'h0000;
    lat_idx      = 3'd0;
    fail_count   = 0;

    for (mi = 0; mi < 128; mi = mi + 1)
        mem[mi] = 16'h0000;

    advance(4);
    reset = 1'b0;
    advance(3);

    if (fsm_state !== ST_IDLE) begin
        $display("FAIL: expected ST_IDLE after reset, got %0d", fsm_state);
        fail_count = fail_count + 1;
    end

    // --- Populate both slots ---
    record_clip(2'b00, S0_W0, S0_W1, S0_W2);
    record_clip(2'b01, S1_W0, S1_W1, S1_W2);

    // --- Contract 1: first output sample must match first recorded word ---
    slot_sel = 2'b00;
    play_and_check_first(S0_W0, "slot0 first sample after clean play");

    // --- Contract 2: mid-read STOP must not corrupt next playback ---
    stop_restart_check(2'b00, S0_W0, "slot0 first sample after stop/restart");

    // --- Contract 3: same guarantee for a nonzero slot ---
    stop_restart_check(2'b01, S1_W0, "slot1 first sample after stop/restart");

    if (fail_count == 0)
        $display("PASS: all checks passed.");
    else
        $display("FAIL: %0d check(s) failed.", fail_count);

    $finish;
end

endmodule