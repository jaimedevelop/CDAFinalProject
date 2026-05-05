`timescale 1ns / 1ps

// CDC symptom testbench.
//
// Models the RAM side on a separate slower clock domain (dst_clk) that only
// samples request/ack/data buses on its own edge.  A direct-crossing topology
// should fail here; a correct bridge/re-homing fix should make it pass.

module tb_cdc_domain_cross;

// ---------------------------------------------------------------------------
// Control-domain (src_clk) inputs
// ---------------------------------------------------------------------------
reg         src_clk;
reg         src_reset;
reg  [7:0]  cmd_in;
reg         cmd_strobe;
reg         ack_status;
reg  [1:0]  slot_sel;
reg  [3:0]  vol_in;
reg  [15:0] mic_sample;
reg         mic_valid;
reg         mic_toggle;
reg         spk_req_tog;
reg         ddr_rdy;
reg  [25:0] ddr_max_addr;

// ---------------------------------------------------------------------------
// Bridge outputs (src domain view of recorder_control status)
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
// CDC bridge wires (src → dst crossing)
// ---------------------------------------------------------------------------
wire [7:0]  xbr_cmd;
wire        xbr_cmd_strobe;
wire        xbr_ack_status;
wire [1:0]  xbr_slot_sel;
wire [3:0]  xbr_vol_in;

// CDC bridge wires (dst → src crossing)
wire        xbr_op_done;
wire        xbr_op_invalid;
wire        xbr_busy;
wire        xbr_recording;
wire        xbr_playing;
wire        xbr_paused;

// ---------------------------------------------------------------------------
// RAM-domain (dst_clk) state
// ---------------------------------------------------------------------------
reg         dst_clk;
reg         ddr_rd_avail;
reg  [15:0] ddr_rd_word;

reg  [15:0] mem [0:31];
reg         rd_in_flight;
reg  [25:0] rd_pend_addr;
reg         rd_data_held;
reg  [15:0] rd_held_word;

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

localparam [15:0] WRD_0 = 16'h1111;
localparam [15:0] WRD_1 = 16'h2222;
localparam [15:0] WRD_2 = 16'h3333;

// ---------------------------------------------------------------------------
// CDC bridge instantiation
// ---------------------------------------------------------------------------
control_cdc_bridge bridge (
    .src_clk              (src_clk),
    .src_reset            (src_reset),
    .src_command          (cmd_in),
    .src_command_strobe   (cmd_strobe),
    .src_clear_status     (ack_status),
    .src_selected_message (slot_sel),
    .src_volume_setting   (vol_in),

    .dst_clk              (dst_clk),
    .dst_reset            (src_reset),
    .dst_command          (xbr_cmd),
    .dst_command_strobe   (xbr_cmd_strobe),
    .dst_clear_status     (xbr_ack_status),
    .dst_selected_message (xbr_slot_sel),
    .dst_volume_setting   (xbr_vol_in),

    .dst_busy             (xbr_busy),
    .dst_recording        (xbr_recording),
    .dst_playing          (xbr_playing),
    .dst_paused           (xbr_paused),
    .dst_invalid_command  (xbr_op_invalid),
    .dst_command_done     (xbr_op_done),

    .src_busy             (dev_busy),
    .src_recording        (dev_recording),
    .src_playing          (dev_playing),
    .src_paused           (dev_paused),
    .src_invalid_command  (op_invalid),
    .src_command_done     (op_done)
);

// ---------------------------------------------------------------------------
// recorder_control instantiation (runs on dst_clk)
// ---------------------------------------------------------------------------
recorder_control ctrl (
    .clk                    (dst_clk),
    .reset                  (src_reset),
    .command                (xbr_cmd),
    .command_strobe         (xbr_cmd_strobe),
    .clear_status           (xbr_ack_status),
    .selected_message       (xbr_slot_sel),
    .volume_setting         (xbr_vol_in),
    .recorder_input_sample  (mic_sample),
    .recorder_input_valid   (mic_valid),
    .recorder_input_toggle  (mic_toggle),
    .playback_request_toggle(spk_req_tog),
    .ram_rdy                (ddr_rdy),
    .ram_rd_data_pres       (ddr_rd_avail),
    .ram_data_out           (ddr_rd_word),
    .ram_max_address        (ddr_max_addr),
    .command_done           (xbr_op_done),
    .invalid_command        (xbr_op_invalid),
    .busy                   (xbr_busy),
    .recording              (xbr_recording),
    .playing                (xbr_playing),
    .paused                 (xbr_paused),
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
// Clocks: src = 100 MHz-like, dst = 33.3 MHz-like, phase-shifted
// ---------------------------------------------------------------------------
always #5  src_clk = ~src_clk;

initial begin
    dst_clk = 1'b0;
    #13;
    forever #15 dst_clk = ~dst_clk;
end

// ---------------------------------------------------------------------------
// Hostile RAM model — only samples buses on dst_clk edges
// ---------------------------------------------------------------------------
always @(posedge dst_clk) begin
    if (src_reset) begin
        ddr_rd_avail  <= 1'b0;
        ddr_rd_word   <= 16'h0000;
        rd_in_flight  <= 1'b0;
        rd_pend_addr  <= 26'd0;
        rd_data_held  <= 1'b0;
        rd_held_word  <= 16'h0000;
    end else begin
        // Write path — capture on dst_clk edge only
        if (ddr_wr_en)
            mem[ddr_addr[4:0]] <= ddr_wr_word;

        // Accept a new read request
        if (ddr_rd_req && !rd_in_flight && !rd_data_held) begin
            rd_in_flight <= 1'b1;
            rd_pend_addr <= ddr_addr;
        end

        // One-cycle read latency then hold until acked
        if (rd_in_flight) begin
            rd_held_word  <= mem[rd_pend_addr[4:0]];
            ddr_rd_word   <= mem[rd_pend_addr[4:0]];
            ddr_rd_avail  <= 1'b1;
            rd_data_held  <= 1'b1;
            rd_in_flight  <= 1'b0;
        end

        // Clear on ack
        if (rd_data_held && ddr_rd_ack) begin
            ddr_rd_avail <= 1'b0;
            rd_data_held <= 1'b0;
        end
    end
end

// ---------------------------------------------------------------------------
// Tasks — timing
// ---------------------------------------------------------------------------
task advance_src;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1)
            @(posedge src_clk);
    end
endtask

task advance_dst;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1)
            @(posedge dst_clk);
    end
endtask

// ---------------------------------------------------------------------------
// Tasks — control
// ---------------------------------------------------------------------------
task deassert_flags;
    begin
        ack_status = 1'b1;
        @(posedge src_clk);
        ack_status = 1'b0;
        @(posedge src_clk);
    end
endtask

// Issue a command deliberately misaligned to dst_clk — tests CDC path
task send_misaligned_cmd;
    input [7:0] op;
    begin
        @(posedge dst_clk);
        @(posedge src_clk);
        @(posedge src_clk);
        cmd_in     = op;
        cmd_strobe = 1'b1;
        @(posedge src_clk);
        cmd_strobe = 1'b0;
        cmd_in     = 8'h00;
        @(posedge src_clk);
    end
endtask

// Push a mic sample; hold stable across several dst_clk edges to avoid
// accidentally testing recorder-input CDC at the same time.
task push_mic_sample;
    input [15:0] val;
    begin
        mic_sample = val;
        mic_toggle = ~mic_toggle;
        advance_dst(3);
    end
endtask

// ---------------------------------------------------------------------------
// Tasks — polling
// ---------------------------------------------------------------------------
task wait_for_fsm_src;
    input [2:0]   target;
    input [255:0] label;
    input integer limit;
    begin
        poll_count = 0;
        while ((fsm_state !== target) && (poll_count < limit)) begin
            @(posedge src_clk);
            poll_count = poll_count + 1;
        end
        if (fsm_state !== target) begin
            $display("TIMEOUT waiting for FSM=%0d [%0s] (src_clk)", target, label);
            fail_count = fail_count + 1;
        end
    end
endtask

task wait_for_fsm_dst;
    input [2:0]   target;
    input [255:0] label;
    input integer limit;
    begin
        poll_count = 0;
        while ((fsm_state !== target) && (poll_count < limit)) begin
            @(posedge dst_clk);
            poll_count = poll_count + 1;
        end
        if (fsm_state !== target) begin
            $display("TIMEOUT waiting for FSM=%0d [%0s] (dst_clk)", target, label);
            fail_count = fail_count + 1;
        end
    end
endtask

// ---------------------------------------------------------------------------
// Stimulus
// ---------------------------------------------------------------------------
initial begin
    src_clk    = 1'b0;
    src_reset  = 1'b1;
    cmd_in     = 8'h00;
    cmd_strobe = 1'b0;
    ack_status = 1'b0;
    slot_sel   = 2'b00;
    vol_in     = 4'hF;
    mic_sample = 16'h0000;
    mic_valid  = 1'b0;
    mic_toggle = 1'b0;
    spk_req_tog = 1'b0;
    ddr_rdy    = 1'b1;
    ddr_max_addr = 26'h0FFFFFF;
    ddr_rd_avail = 1'b0;
    ddr_rd_word  = 16'h0000;
    rd_in_flight = 1'b0;
    rd_pend_addr = 26'd0;
    rd_data_held = 1'b0;
    rd_held_word = 16'h0000;
    fail_count   = 0;

    for (mi = 0; mi < 32; mi = mi + 1)
        mem[mi] = 16'h0000;

    advance_src(4);
    src_reset = 1'b0;
    advance_src(4);

    if (fsm_state !== ST_IDLE) begin
        $display("FAIL: expected ST_IDLE after reset, got %0d", fsm_state);
        fail_count = fail_count + 1;
    end

    // -----------------------------------------------------------------------
    // Record three samples through the CDC bridge
    // -----------------------------------------------------------------------
    deassert_flags;
    send_misaligned_cmd(OP_RECORD);
    wait_for_fsm_src(ST_REC, "ST_REC", 20);

    push_mic_sample(WRD_0);
    push_mic_sample(WRD_1);
    push_mic_sample(WRD_2);

    send_misaligned_cmd(OP_STOP);
    wait_for_fsm_src(ST_IDLE, "ST_IDLE after record stop", 40);

    // Verify slot metadata and RAM model contents
    if (!slot_valid) begin
        $display("FAIL: slot should be valid after recording");
        fail_count = fail_count + 1;
    end
    if (mem[0] !== WRD_0) begin
        $display("FAIL: mem[0] expected 0x%04h, got 0x%04h", WRD_0, mem[0]);
        fail_count = fail_count + 1;
    end
    if (mem[1] !== WRD_1) begin
        $display("FAIL: mem[1] expected 0x%04h, got 0x%04h", WRD_1, mem[1]);
        fail_count = fail_count + 1;
    end
    if (mem[2] !== WRD_2) begin
        $display("FAIL: mem[2] expected 0x%04h, got 0x%04h", WRD_2, mem[2]);
        fail_count = fail_count + 1;
    end

    // -----------------------------------------------------------------------
    // Play back — contract: with a correct CDC fix, the RAM-domain model must
    // still be able to prime the FIFO and return the first recorded sample
    // even though it only sees requests on dst_clk edges.
    // -----------------------------------------------------------------------
    deassert_flags;
    send_misaligned_cmd(OP_PLAY);
    wait_for_fsm_dst(ST_PLAY, "ST_PLAY after misaligned CMD_PLAY", 120);

    if (fsm_state == ST_PLAY) begin
        if (spk_sample !== WRD_0) begin
            $display("FAIL: first playback sample expected 0x%04h, got 0x%04h",
                     WRD_0, spk_sample);
            fail_count = fail_count + 1;
        end
    end

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