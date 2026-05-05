`timescale 1ns / 1ps

// End-to-end digital testbench: audio_sample_path + recorder_control
// Covers: record three samples through sample path into RAM model,
//         then play them back and verify audio_output at each codec request.

module tb_audio_path_e2e;

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
reg         codec_end;          // sample_end: codec finished capturing
reg         codec_req;          // sample_req: codec requesting next output
reg  [15:0] adc_word;           // audio_input: raw ADC sample
reg         mon_en;             // monitor_enable
reg         tone_en;            // test_tone_enable
reg         ddr_rdy;
reg  [25:0] ddr_max_addr;

// ---------------------------------------------------------------------------
// Interconnect wires between audio_sample_path and recorder_control
// ---------------------------------------------------------------------------
wire [15:0] dac_word;           // audio_output
wire [15:0] path_sample;        // recorder_sample
wire        path_sample_valid;  // recorder_sample_valid
wire        path_sample_tog;    // recorder_sample_toggle
wire        spk_req_tog;        // playback_request_toggle

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
wire        spk_active;         // playback_enable
wire [15:0] spk_sample;         // playback_sample_data
wire [25:0] ddr_addr;
wire [15:0] ddr_wr_word;
wire        ddr_wr_en;
wire        ddr_rd_req;
wire        ddr_rd_ack;

// ---------------------------------------------------------------------------
// RAM model (behavioural — 64 entries)
// ---------------------------------------------------------------------------
reg         ddr_rd_avail;
reg  [15:0] ddr_rd_word;
reg  [15:0] mem [0:63];
reg         rd_in_flight;
reg  [25:0] rd_pend_addr;
reg  [1:0]  rd_latency;

// ---------------------------------------------------------------------------
// Test bookkeeping
// ---------------------------------------------------------------------------
integer fail_count;
integer poll_count;
integer mi;                     // loop index for mem init

// ---------------------------------------------------------------------------
// Opcode aliases
// ---------------------------------------------------------------------------
localparam [7:0] OP_PLAY   = 8'h01;
localparam [7:0] OP_RECORD = 8'h02;
localparam [7:0] OP_STOP   = 8'h06;

// ---------------------------------------------------------------------------
// FSM state aliases
// ---------------------------------------------------------------------------
localparam [2:0] ST_IDLE = 3'd0;
localparam [2:0] ST_REC  = 3'd1;
localparam [2:0] ST_PLAY = 3'd2;

// ---------------------------------------------------------------------------
// Fixed test samples
// ---------------------------------------------------------------------------
localparam [15:0] SMP_A = 16'h1234;
localparam [15:0] SMP_B = 16'hFEDC;
localparam [15:0] SMP_C = 16'h0A0A;

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
// Behavioural RAM model — write-through, 2-cycle read latency
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (reset) begin
        ddr_rd_avail  <= 1'b0;
        ddr_rd_word   <= 16'h0000;
        rd_in_flight  <= 1'b0;
        rd_pend_addr  <= 26'd0;
        rd_latency    <= 2'd0;
    end else begin
        ddr_rd_avail <= 1'b0;

        if (ddr_wr_en)
            mem[ddr_addr[5:0]] <= ddr_wr_word;

        if (ddr_rd_req && !rd_in_flight) begin
            rd_in_flight <= 1'b1;
            rd_pend_addr <= ddr_addr;
            rd_latency   <= 2'd2;
        end else if (rd_in_flight) begin
            if (rd_latency != 2'd0) begin
                rd_latency <= rd_latency - 2'd1;
            end else begin
                ddr_rd_word  <= mem[rd_pend_addr[5:0]];
                ddr_rd_avail <= 1'b1;
                if (ddr_rd_ack)
                    rd_in_flight <= 1'b0;
            end
        end
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

// Deliver one ADC sample via the codec_end strobe (mirrors send_input_sample)
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

task wait_for_spk_sample;
    input [15:0]  expected;
    input [255:0] label;
    input integer limit;
    begin
        poll_count = 0;
        while ((spk_sample !== expected) && (poll_count < limit)) begin
            @(posedge clk);
            poll_count = poll_count + 1;
        end
        if (spk_sample !== expected) begin
            $display("TIMEOUT waiting for spk_sample=0x%04h [%0s]", expected, label);
            fail_count = fail_count + 1;
        end
    end
endtask

// ---------------------------------------------------------------------------
// Tasks — assertions
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

// Request one output sample from the codec path and check dac_word
task pull_and_check;
    input [15:0]  expected;
    input [255:0] label;
    begin
        codec_req = 1'b1;
        @(posedge clk);
        codec_req = 1'b0;
        @(posedge clk);
        assert_16bit(dac_word, expected, label);
    end
endtask

// ---------------------------------------------------------------------------
// Stimulus
// ---------------------------------------------------------------------------
initial begin
    // --- initialise ---
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
    rd_latency   = 2'd0;
    fail_count   = 0;

    for (mi = 0; mi < 64; mi = mi + 1)
        mem[mi] = 16'h0000;

    advance(4);
    reset = 1'b0;
    advance(3);

    // -----------------------------------------------------------------------
    // Check idle after reset
    // -----------------------------------------------------------------------
    if (fsm_state !== ST_IDLE) begin
        $display("FAIL: expected ST_IDLE after reset, got %0d", fsm_state);
        fail_count = fail_count + 1;
    end

    // -----------------------------------------------------------------------
    // Record three samples
    // -----------------------------------------------------------------------
    deassert_flags;
    send_cmd(OP_RECORD);
    wait_for_fsm(ST_REC, "ST_REC", 20);

    push_adc_sample(SMP_A);
    push_adc_sample(SMP_B);
    push_adc_sample(SMP_C);

    send_cmd(OP_STOP);
    wait_for_fsm(ST_IDLE, "ST_IDLE after record", 20);

    assert_1bit (slot_valid, 1'b1,  "slot valid after record");
    assert_26bit(slot_len,   26'd3, "slot length after record");

    // Verify samples landed in the RAM model at the expected locations
    assert_16bit(mem[0], SMP_A, "mem[0] == SMP_A");
    assert_16bit(mem[1], SMP_B, "mem[1] == SMP_B");
    assert_16bit(mem[2], SMP_C, "mem[2] == SMP_C");

    // -----------------------------------------------------------------------
    // Play back and verify audio output at each codec request
    // -----------------------------------------------------------------------
    deassert_flags;
    send_cmd(OP_PLAY);
    wait_for_fsm(ST_PLAY, "ST_PLAY", 20);

    wait_for_spk_sample(SMP_A, "spk_sample staged SMP_A", 50);
    pull_and_check(SMP_A, "dac_word sample 0");

    wait_for_spk_sample(SMP_B, "spk_sample staged SMP_B", 50);
    pull_and_check(SMP_B, "dac_word sample 1");

    wait_for_spk_sample(SMP_C, "spk_sample staged SMP_C", 50);
    pull_and_check(SMP_C, "dac_word sample 2");

    wait_for_fsm(ST_IDLE, "ST_IDLE after playback", 50);

    assert_1bit(op_done,    1'b1, "op_done at playback end");
    assert_1bit(op_invalid, 1'b0, "op_invalid stays low throughout");

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