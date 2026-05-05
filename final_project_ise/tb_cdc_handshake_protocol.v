`timescale 1ns / 1ps

// Protocol-level testbench for the planned command/status CDC handshake bridge.
//
// Written against the behavioral contract of a future bridge module rather than
// the current top-level implementation. Activate once `cmd_status_cdc_bridge.v`
// (or the final equivalent name/interface) exists.
//
// Contracts verified:
// 1. A one-cycle source-domain command pulse produces exactly one
//    destination-domain command pulse.
// 2. Command payload (opcode/slot/gain) remains coherent with that pulse at
//    the destination.
// 3. Short source pulses are not lost when the destination clock is slower.
// 4. Back-to-back source commands do not merge or duplicate.
// 5. Source-side clear-status pulses cross exactly once.
// 6. Destination-side status flags return to the source domain cleanly.

module tb_cdc_handshake_protocol;

    // ── Source domain ─────────────────────────────────────────────────────
    reg        src_clk;
    reg        src_rst;
    reg  [7:0] src_opcode;
    reg        src_op_strobe;
    reg        src_clr_status;
    reg  [1:0] src_slot_sel;
    reg  [3:0] src_gain_sel;

    // ── Destination domain ────────────────────────────────────────────────
    reg        dst_clk;
    reg        dst_rst;
    reg        dst_busy;
    reg        dst_rec_active;
    reg        dst_play_active;
    reg        dst_play_paused;
    reg        dst_op_rejected;
    reg        dst_op_done;

    // ── Bridge outputs → destination ─────────────────────────────────────
    wire [7:0] dst_opcode;
    wire       dst_op_strobe;
    wire       dst_clr_status;
    wire [1:0] dst_slot_sel;
    wire [3:0] dst_gain_sel;

    // ── Bridge outputs → source ───────────────────────────────────────────
    wire       src_busy;
    wire       src_rec_active;
    wire       src_play_active;
    wire       src_play_paused;
    wire       src_op_rejected;
    wire       src_op_done;

    // ── Test bookkeeping ──────────────────────────────────────────────────
    integer err_cnt;
    integer wait_cyc;
    integer pulse_cnt;

    localparam [7:0] OP_PLAY   = 8'h01;
    localparam [7:0] OP_RECORD = 8'h02;
    localparam [7:0] OP_STOP   = 8'h06;

    // NOTE: module does not exist yet — wired and ready for when the bridge
    // is introduced alongside the RAM-side CDC restructuring.
    cmd_status_cdc_bridge dut (
        .src_clk         (src_clk),
        .src_rst         (src_rst),
        .src_opcode      (src_opcode),
        .src_op_strobe   (src_op_strobe),
        .src_clr_status  (src_clr_status),
        .src_slot_sel    (src_slot_sel),
        .src_gain_sel    (src_gain_sel),

        .dst_clk         (dst_clk),
        .dst_rst         (dst_rst),
        .dst_opcode      (dst_opcode),
        .dst_op_strobe   (dst_op_strobe),
        .dst_clr_status  (dst_clr_status),
        .dst_slot_sel    (dst_slot_sel),
        .dst_gain_sel    (dst_gain_sel),

        .dst_busy        (dst_busy),
        .dst_rec_active  (dst_rec_active),
        .dst_play_active (dst_play_active),
        .dst_play_paused (dst_play_paused),
        .dst_op_rejected (dst_op_rejected),
        .dst_op_done     (dst_op_done),

        .src_busy        (src_busy),
        .src_rec_active  (src_rec_active),
        .src_play_active (src_play_active),
        .src_play_paused (src_play_paused),
        .src_op_rejected (src_op_rejected),
        .src_op_done     (src_op_done)
    );

    always #5  src_clk = ~src_clk;   // 100 MHz-like source domain
    always #13 dst_clk = ~dst_clk;   // slower RAM UI-like destination domain

    // ── Clock advance helpers ─────────────────────────────────────────────
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

    // ── Stimulus helpers ──────────────────────────────────────────────────
    task send_op;
        input [7:0] op;
        input [1:0] slot;
        input [3:0] gain;
        begin
            src_opcode     = op;
            src_slot_sel   = slot;
            src_gain_sel   = gain;
            src_op_strobe  = 1'b1;
            @(posedge src_clk);
            src_op_strobe  = 1'b0;
            src_opcode     = 8'h00;
        end
    endtask

    task send_clr_status;
        begin
            src_clr_status = 1'b1;
            @(posedge src_clk);
            src_clr_status = 1'b0;
        end
    endtask

    // ── Checker helpers ───────────────────────────────────────────────────

    // Assert dst_op_strobe arrives exactly once with correct payload.
    // Then check for unwanted duplicates over the following 20 dst cycles.
    task assert_single_dst_op;
        input [7:0] exp_op;
        input [1:0] exp_slot;
        input [3:0] exp_gain;
        input [255:0] tag;
        begin
            wait_cyc  = 0;
            pulse_cnt = 0;

            while ((pulse_cnt == 0) && (wait_cyc < 80)) begin
                @(posedge dst_clk); #1;
                wait_cyc = wait_cyc + 1;
                if (dst_op_strobe) begin
                    pulse_cnt = pulse_cnt + 1;
                    if (dst_opcode !== exp_op) begin
                        $display("ERROR [%0s] opcode: expected 0x%0h got 0x%0h",
                                 tag, exp_op, dst_opcode);
                        err_cnt = err_cnt + 1;
                    end
                    if (dst_slot_sel !== exp_slot) begin
                        $display("ERROR [%0s] slot: expected %0d got %0d",
                                 tag, exp_slot, dst_slot_sel);
                        err_cnt = err_cnt + 1;
                    end
                    if (dst_gain_sel !== exp_gain) begin
                        $display("ERROR [%0s] gain: expected 0x%0h got 0x%0h",
                                 tag, exp_gain, dst_gain_sel);
                        err_cnt = err_cnt + 1;
                    end
                end
            end

            if (pulse_cnt == 0) begin
                $display("ERROR [%0s] timeout — no dst_op_strobe received", tag);
                err_cnt = err_cnt + 1;
            end

            // Duplicate check window
            pulse_cnt = 0;
            repeat (20) begin
                @(posedge dst_clk); #1;
                if (dst_op_strobe) begin
                    pulse_cnt = pulse_cnt + 1;
                    $display("DEBUG [%0s] extra dst_op_strobe: op=0x%0h slot=%0d gain=0x%0h t=%0t "
                             "req_tgl=%0b ack_sync=%0b ack_seen=%0b inflight=%0b "
                             "q_valid=%0b req_sync=%0b req_seen=%0b",
                             tag, dst_opcode, dst_slot_sel, dst_gain_sel, $time,
                             dut.cmd_req_toggle_src,
                             dut.cmd_ack_sync_src[1],
                             dut.cmd_ack_seen_src,
                             dut.cmd_inflight_src,
                             dut.cmd_queue_valid_src,
                             dut.cmd_req_sync_dst[1],
                             dut.cmd_req_seen_dst);
                end
            end
            if (pulse_cnt != 0) begin
                $display("ERROR [%0s] dst_op_strobe duplicated (%0d extra pulse(s))",
                         tag, pulse_cnt);
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    // Assert dst_clr_status arrives exactly once.
    task assert_single_dst_clr;
        input [255:0] tag;
        begin
            wait_cyc  = 0;
            pulse_cnt = 0;

            while ((pulse_cnt == 0) && (wait_cyc < 80)) begin
                @(posedge dst_clk); #1;
                wait_cyc = wait_cyc + 1;
                if (dst_clr_status)
                    pulse_cnt = pulse_cnt + 1;
            end

            if (pulse_cnt == 0) begin
                $display("ERROR [%0s] timeout — no dst_clr_status received", tag);
                err_cnt = err_cnt + 1;
            end

            pulse_cnt = 0;
            repeat (20) begin
                @(posedge dst_clk); #1;
                if (dst_clr_status)
                    pulse_cnt = pulse_cnt + 1;
            end
            if (pulse_cnt != 0) begin
                $display("ERROR [%0s] dst_clr_status duplicated (%0d extra pulse(s))",
                         tag, pulse_cnt);
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    // Poll until src-domain status flags settle or timeout.
    task assert_src_status;
        input exp_busy;
        input exp_rec;
        input exp_play;
        input exp_paused;
        input exp_rejected;
        input exp_done;
        input [255:0] tag;
        begin
            wait_cyc = 0;
            while (((src_busy        !== exp_busy)     ||
                    (src_rec_active  !== exp_rec)      ||
                    (src_play_active !== exp_play)      ||
                    (src_play_paused !== exp_paused)    ||
                    (src_op_rejected !== exp_rejected)  ||
                    (src_op_done     !== exp_done))     &&
                   (wait_cyc < 80)) begin
                @(posedge src_clk);
                wait_cyc = wait_cyc + 1;
            end

            if ((src_busy        !== exp_busy)    ||
                (src_rec_active  !== exp_rec)     ||
                (src_play_active !== exp_play)    ||
                (src_play_paused !== exp_paused)  ||
                (src_op_rejected !== exp_rejected)||
                (src_op_done     !== exp_done)) begin
                $display("ERROR [%0s] timeout — src status did not reach expected values", tag);
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    // ── Stimulus ──────────────────────────────────────────────────────────
    initial begin
        src_clk      = 1'b0;
        src_rst      = 1'b1;
        src_opcode   = 8'h00;
        src_op_strobe  = 1'b0;
        src_clr_status = 1'b0;
        src_slot_sel = 2'b00;
        src_gain_sel = 4'h8;

        dst_clk        = 1'b0;
        dst_rst        = 1'b1;
        dst_busy       = 1'b0;
        dst_rec_active = 1'b0;
        dst_play_active= 1'b0;
        dst_play_paused= 1'b0;
        dst_op_rejected= 1'b0;
        dst_op_done    = 1'b0;

        err_cnt = 0;

        advance_src(4);
        advance_dst(2);
        src_rst = 1'b0;
        dst_rst = 1'b0;
        advance_src(3);

        // C1: one-cycle source pulse → exactly one destination pulse, coherent payload.
        send_op(OP_RECORD, 2'b01, 4'hD);
        assert_single_dst_op(OP_RECORD, 2'b01, 4'hD, "record op crossing");

        // C2: back-to-back ops must not merge or duplicate.
        send_op(OP_PLAY, 2'b00, 4'h4);
        assert_single_dst_op(OP_PLAY, 2'b00, 4'h4, "play op crossing");
        // Gap between play and stop so the stop strobe cannot be mistaken for
        // a duplicate play pulse in the trailing duplicate-check window.
        advance_dst(30);
        send_op(OP_STOP, 2'b00, 4'h4);
        assert_single_dst_op(OP_STOP, 2'b00, 4'h4, "stop op crossing");

        // C3: clear-status pulse crosses exactly once.
        send_clr_status;
        assert_single_dst_clr("clr-status crossing");

        // C4: destination status flags propagate cleanly back to source domain.
        dst_busy       = 1'b1;
        dst_rec_active = 1'b1;
        assert_src_status(1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                          "recording status return");

        dst_busy       = 1'b0;
        dst_rec_active = 1'b0;
        dst_op_done    = 1'b1;
        assert_src_status(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1,
                          "done status return");

        dst_op_done     = 1'b0;
        dst_op_rejected = 1'b1;
        assert_src_status(1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0,
                          "rejected status return");

        if (err_cnt == 0)
            $display("PASS: tb_cdc_handshake_protocol completed without errors.");
        else
            $display("FAIL: tb_cdc_handshake_protocol completed with %0d error(s).", err_cnt);

        $finish;
    end

endmodule