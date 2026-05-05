`timescale 1ns / 1ps

// Testbench: recorder_control — record and playback scenarios
// Covers: reset/idle sanity, two-sample record, mid-operation slot change,
//         slot preparation, playback with read servicing, and volume latching.

module tb_msg_store_record_play;

// ---------------------------------------------------------------------------
// DUT inputs
// ---------------------------------------------------------------------------
reg         clk;
reg         reset;
reg  [7:0]  cmd_in;
reg         cmd_strobe;
reg         ack_status;
reg  [1:0]  slot_sel;
reg  [3:0]  vol_in;
reg  [15:0] mic_sample;
reg         mic_valid;
reg         mic_toggle;
reg         spk_toggle;
reg         ddr_rdy;
reg         ddr_rd_avail;
reg  [15:0] ddr_rd_word;
reg  [25:0] ddr_max_addr;

// ---------------------------------------------------------------------------
// DUT outputs
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
// Test bookkeeping
// ---------------------------------------------------------------------------
integer fail_count;
integer poll_count;

// ---------------------------------------------------------------------------
// Opcode aliases (match recorder_control.v OP_* values)
// ---------------------------------------------------------------------------
localparam [7:0] OP_PLAY       = 8'h01;
localparam [7:0] OP_RECORD     = 8'h02;
localparam [7:0] OP_DELETE     = 8'h03;
localparam [7:0] OP_DELETE_ALL = 8'h04;
localparam [7:0] OP_VOLUME     = 8'h05;
localparam [7:0] OP_STOP       = 8'h06;

// ---------------------------------------------------------------------------
// FSM state aliases
// ---------------------------------------------------------------------------
localparam [2:0] ST_IDLE = 3'd0;
localparam [2:0] ST_REC  = 3'd1;
localparam [2:0] ST_PLAY = 3'd2;

// ---------------------------------------------------------------------------
// Slot base addresses
// ---------------------------------------------------------------------------
localparam [25:0] BASE_S0 = 26'd0;
localparam [25:0] BASE_S1 = 26'd4194304;

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
recorder_control dut (
    .clk                    (clk),
    .reset                  (reset),
    .command                (cmd_in),
    .command_strobe         (cmd_strobe),
    .clear_status           (ack_status),
    .selected_message       (slot_sel),
    .volume_setting         (vol_in),
    .recorder_input_sample  (mic_sample),
    .recorder_input_valid   (mic_valid),
    .recorder_input_toggle  (mic_toggle),
    .playback_request_toggle(spk_toggle),
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
// Utility tasks
// ---------------------------------------------------------------------------

// Advance N rising edges
task advance;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1)
            @(posedge clk);
    end
endtask

// Pulse clear_status for one cycle
task deassert_flags;
    begin
        ack_status = 1'b1;
        @(posedge clk);
        ack_status = 1'b0;
        @(posedge clk);
    end
endtask

// Issue a one-cycle command strobe
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

// Toggle mic_toggle to deliver a sample (no write check)
task deliver_sample;
    input [15:0] val;
    begin
        mic_sample = val;
        advance(1);
        mic_toggle = ~mic_toggle;
        advance(3);
    end
endtask

// Toggle mic_toggle and verify the resulting DDR write
task deliver_and_verify_write;
    input [15:0] val;
    input [25:0] exp_addr;
    input [255:0] label;
    begin
        mic_sample = val;
        advance(1);
        mic_toggle = ~mic_toggle;
        poll_for_write({label, " wr_en"}, 50);
        if (ddr_wr_en !== 1'b1) disable deliver_and_verify_write;
        assert_1bit(ddr_wr_en,   1'b1, {label, " wr_en"});
        assert_26bit(ddr_addr,   exp_addr, {label, " addr"});
        assert_16bit(ddr_wr_word, val,     {label, " data"});
        @(posedge clk);
    end
endtask

// Toggle spk_toggle to consume a playback sample
task consume_sample;
    begin
        spk_toggle = ~spk_toggle;
        advance(3);
    end
endtask

// ---------------------------------------------------------------------------
// Polling helpers
// ---------------------------------------------------------------------------

task poll_for_write;
    input [255:0] label;
    input integer limit;
    begin
        poll_count = 0;
        while ((ddr_wr_en !== 1'b1) && (poll_count < limit)) begin
            @(posedge clk);
            poll_count = poll_count + 1;
        end
        if (ddr_wr_en !== 1'b1) begin
            $display("TIMEOUT: %0s (write_enable)", label);
            fail_count = fail_count + 1;
        end
    end
endtask

task poll_for_read_req;
    input [255:0] label;
    input integer limit;
    begin
        poll_count = 0;
        while ((ddr_rd_req !== 1'b1) &&
               (dut.pb_fetch_pending !== 1'b1) &&
               (poll_count < limit)) begin
            @(posedge clk);
            poll_count = poll_count + 1;
        end
        if ((ddr_rd_req !== 1'b1) && (dut.pb_fetch_pending !== 1'b1)) begin
            $display("TIMEOUT: %0s (read_request)", label);
            fail_count = fail_count + 1;
        end
    end
endtask

task poll_for_read_ack;
    input [255:0] label;
    input integer limit;
    begin
        poll_count = 0;
        while ((ddr_rd_ack !== 1'b1) && (poll_count < limit)) begin
            @(posedge clk);
            poll_count = poll_count + 1;
        end
        if (ddr_rd_ack !== 1'b1) begin
            $display("TIMEOUT: %0s (read_ack)", label);
            fail_count = fail_count + 1;
        end
    end
endtask

// Feed one DDR read response and verify the request address
task feed_read_response;
    input [25:0] exp_addr;
    input [15:0] sample;
    begin
        poll_for_read_req("read_request", 50);
        if ((ddr_rd_req !== 1'b1) && (dut.pb_fetch_pending !== 1'b1))
            disable feed_read_response;
        if (ddr_addr !== exp_addr) begin
            $display("ERROR: read addr expected %0d got %0d", exp_addr, ddr_addr);
            fail_count = fail_count + 1;
        end
        ddr_rd_word  = sample;
        ddr_rd_avail = 1'b1;
        @(posedge clk);
        ddr_rd_avail = 1'b0;
        ddr_rd_word  = 16'h0000;
        poll_for_read_ack("read_ack", 50);
        if (ddr_rd_ack !== 1'b1)
            disable feed_read_response;
        @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// Assertion tasks
// ---------------------------------------------------------------------------

task assert_1bit;
    input        actual;
    input        expected;
    input [255:0] label;
    begin
        if (actual !== expected) begin
            $display("FAIL [%0s]: expected %0b, got %0b", label, expected, actual);
            fail_count = fail_count + 1;
        end
    end
endtask

task assert_4bit;
    input [3:0]  actual;
    input [3:0]  expected;
    input [255:0] label;
    begin
        if (actual !== expected) begin
            $display("FAIL [%0s]: expected 0x%0h, got 0x%0h", label, expected, actual);
            fail_count = fail_count + 1;
        end
    end
endtask

task assert_16bit;
    input [15:0] actual;
    input [15:0] expected;
    input [255:0] label;
    begin
        if (actual !== expected) begin
            $display("FAIL [%0s]: expected 0x%04h, got 0x%04h", label, expected, actual);
            fail_count = fail_count + 1;
        end
    end
endtask

task assert_26bit;
    input [25:0] actual;
    input [25:0] expected;
    input [255:0] label;
    begin
        if (actual !== expected) begin
            $display("FAIL [%0s]: expected %0d, got %0d", label, expected, actual);
            fail_count = fail_count + 1;
        end
    end
endtask

task assert_fsm;
    input [2:0]  actual;
    input [2:0]  expected;
    input [255:0] label;
    begin
        if (actual !== expected) begin
            $display("FAIL [%0s]: expected FSM state %0d, got %0d", label, expected, actual);
            fail_count = fail_count + 1;
        end
    end
endtask

// ---------------------------------------------------------------------------
// Test stimulus
// ---------------------------------------------------------------------------
initial begin
    // --- initialise all inputs ---
    clk          = 1'b0;
    reset        = 1'b1;
    cmd_in       = 8'h00;
    cmd_strobe   = 1'b0;
    ack_status   = 1'b0;
    slot_sel     = 2'b00;
    vol_in       = 4'h8;
    mic_sample   = 16'h0000;
    mic_valid    = 1'b0;
    mic_toggle   = 1'b0;
    spk_toggle   = 1'b0;
    ddr_rdy      = 1'b1;
    ddr_rd_avail = 1'b0;
    ddr_rd_word  = 16'h0000;
    ddr_max_addr = 26'h0FFFFFF;
    fail_count   = 0;

    advance(4);
    reset = 1'b0;
    advance(3);

    // -----------------------------------------------------------------------
    // S0 — reset / idle sanity
    // -----------------------------------------------------------------------
    assert_26bit(slot_len,   26'd0,  "S0 slot_len after reset");
    assert_1bit (slot_valid, 1'b0,   "S0 slot_valid after reset");
    assert_1bit (op_done,    1'b0,   "S0 op_done after reset");
    assert_1bit (op_invalid, 1'b0,   "S0 op_invalid after reset");
    assert_1bit (layout_fits, 1'b1,  "S0 layout_fits");
    assert_fsm  (fsm_state, ST_IDLE, "S0 idle");

    // -----------------------------------------------------------------------
    // S1 — record two samples into slot 0, verify write strobes
    // -----------------------------------------------------------------------
    deassert_flags;
    slot_sel = 2'b00;
    send_cmd(OP_RECORD);
    assert_fsm(fsm_state, ST_REC, "S1 entered REC");

    deliver_and_verify_write(16'h1111, BASE_S0,          "S1 sample0");
    deliver_and_verify_write(16'h2222, BASE_S0 + 26'd1,  "S1 sample1");

    send_cmd(OP_STOP);
    advance(3);
    assert_fsm  (fsm_state,  ST_IDLE, "S1 returned IDLE after STOP");
    assert_1bit (op_done,    1'b1,    "S1 op_done");
    assert_1bit (slot_valid, 1'b1,    "S1 slot0 now valid");
    assert_26bit(slot_len,   26'd2,   "S1 slot0 length");

    // -----------------------------------------------------------------------
    // S2 — re-record slot 0; confirm active slot does not follow slot_sel
    // -----------------------------------------------------------------------
    deassert_flags;
    slot_sel = 2'b00;
    send_cmd(OP_RECORD);

    deliver_sample(16'h3333);
    slot_sel = 2'b01;           // switch selector mid-recording — should be ignored
    deliver_sample(16'h4444);
    send_cmd(OP_STOP);
    advance(3);

    // slot 0 should have 2 new samples
    slot_sel = 2'b00;
    advance(2);
    assert_1bit (slot_valid, 1'b1,  "S2 slot0 valid");
    assert_26bit(slot_len,   26'd2, "S2 slot0 length");

    // slot 1 must remain empty
    slot_sel = 2'b01;
    advance(2);
    assert_1bit (slot_valid, 1'b0,  "S2 slot1 untouched valid");
    assert_26bit(slot_len,   26'd0, "S2 slot1 untouched length");

    // -----------------------------------------------------------------------
    // Prep — record two samples into slot 1 for playback tests
    // -----------------------------------------------------------------------
    deassert_flags;
    slot_sel = 2'b01;
    send_cmd(OP_RECORD);
    deliver_sample(16'h5555);
    deliver_sample(16'h6666);
    send_cmd(OP_STOP);
    advance(3);

    slot_sel = 2'b01;
    advance(2);
    assert_1bit (slot_valid, 1'b1,  "prep slot1 valid");
    assert_26bit(slot_len,   26'd2, "prep slot1 length");

    // -----------------------------------------------------------------------
    // S3 / S4 / S5 — playback slot 1; verify read addresses, sample latching,
    //                 and volume update via CMD_VOLUME
    // -----------------------------------------------------------------------
    deassert_flags;
    slot_sel = 2'b01;
    vol_in   = 4'h4;
    send_cmd(OP_PLAY);
    advance(2);

    assert_fsm (fsm_state,   ST_PLAY, "S3 entered PLAY");
    assert_4bit(vol_latched, 4'h4,    "S3 volume latched at play start");

    // Switching slot_sel while playing must not affect active slot view
    slot_sel = 2'b00;
    vol_in   = 4'h9;
    advance(2);
    assert_4bit (vol_latched, 4'h4,  "S4 vol unchanged without CMD_VOLUME");
    assert_1bit (slot_valid,  1'b1,  "S4 active slot still valid");
    assert_26bit(slot_len,    26'd2, "S4 active slot length unchanged");

    // Service first DDR read and verify sample is staged
    feed_read_response(BASE_S1, 16'h0A0A);
    assert_16bit(spk_sample, 16'h0A0A, "S3 first sample staged");
    consume_sample;

    // Update volume mid-playback
    send_cmd(OP_VOLUME);
    advance(2);
    assert_4bit(vol_latched, 4'h9, "S5 volume updated by CMD_VOLUME");

    // Service second DDR read and verify sample; playback should then end
    feed_read_response(BASE_S1 + 26'd1, 16'h0B0B);
    assert_16bit(spk_sample, 16'h0B0B, "S3 second sample staged");
    consume_sample;
    advance(3);

    assert_fsm(fsm_state, ST_IDLE, "S3 returned IDLE after last sample");

    // -----------------------------------------------------------------------
    // Result
    // -----------------------------------------------------------------------
    if (fail_count == 0)
        $display("PASS: all checks passed.");
    else
        $display("FAIL: %0d check(s) failed.", fail_count);

    $finish;
end

endmodule