`timescale 1ns / 1ps

module tb_hw_input_decoder;

    // ── DUT ports ─────────────────────────────────────────────────────────
    reg        clk;
    reg        rst;
    reg        hw_test_en;
    reg  [3:0] slide_sw;
    reg  [7:0] dip_sw;
    reg  [2:0] btn_raw;
    reg        fsm_rec_active;
    reg        fsm_play_active;
    reg        fsm_play_paused;

    wire [2:0] btn_state;
    wire [2:0] btn_edge;
    wire [1:0] slot_idx;
    wire [3:0] gain_level;
    wire [7:0] op_out;
    wire       op_strobe;
    wire       clr_status_pulse;

    // ── Test bookkeeping ──────────────────────────────────────────────────
    integer    err_cnt;
    integer    strobe_cnt;
    reg  [7:0] last_op;

    // ── Op encoding (must match DUT parameters) ───────────────────────────
    localparam [7:0] OP_PLAY       = 8'h01;
    localparam [7:0] OP_RECORD     = 8'h02;
    localparam [7:0] OP_DEL_ONE    = 8'h03;
    localparam [7:0] OP_DEL_ALL    = 8'h04;
    localparam [7:0] OP_STOP       = 8'h06;
    localparam [7:0] OP_PAUSE_RES  = 8'h07;

    // ── DUT instantiation ─────────────────────────────────────────────────
    hw_input_decoder #(
        .DEBOUNCE_CLKS  (20'd3),
        .OP_PLAY        (OP_PLAY),
        .OP_RECORD      (OP_RECORD),
        .OP_DEL_ONE     (OP_DEL_ONE),
        .OP_DEL_ALL     (OP_DEL_ALL),
        .OP_STOP        (OP_STOP),
        .OP_PAUSE_RES   (OP_PAUSE_RES)
    ) dut (
        .clk            (clk),
        .rst            (rst),
        .hw_test_en     (hw_test_en),
        .slide_sw       (slide_sw),
        .dip_sw         (dip_sw),
        .btn_raw        (btn_raw),
        .fsm_rec_active (fsm_rec_active),
        .fsm_play_active(fsm_play_active),
        .fsm_play_paused(fsm_play_paused),
        .btn_state      (btn_state),
        .btn_edge       (btn_edge),
        .slot_idx       (slot_idx),
        .gain_level     (gain_level),
        .op_out         (op_out),
        .op_strobe      (op_strobe),
        .clr_status_pulse(clr_status_pulse)
    );

    always #5 clk = ~clk;

    // ── Strobe monitor ────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (op_strobe) begin
            strobe_cnt   <= strobe_cnt + 1;
            last_op      <= op_out;
        end
    end

    // ── Helpers ───────────────────────────────────────────────────────────
    task advance;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    task clear_observer;
        begin
            strobe_cnt = 0;
            last_op    = 8'h00;
        end
    endtask

    // Clean synchronous button press: hold for debounce window then release.
    task press_btn;
        input [2:0] mask;
        begin
            btn_raw = mask;
            advance(3);
            btn_raw = 3'b000;
            advance(6);
        end
    endtask

    // Asynchronous press — offset and width in ns, then settle for N cycles.
    task press_btn_async;
        input [2:0] mask;
        input integer offset_ns;
        input integer width_ns;
        input integer settle_cyc;
        begin
            #(offset_ns);
            btn_raw = mask;
            #(width_ns);
            btn_raw = 3'b000;
            advance(settle_cyc);
        end
    endtask

    // Simulate contact bounce before the button stabilises.
    task press_btn_bouncy;
        input [2:0] mask;
        begin
            #2  btn_raw = mask;
            #4  btn_raw = 3'b000;
            #3  btn_raw = mask;
            #4  btn_raw = 3'b000;
            #2  btn_raw = mask;
            #25 btn_raw = 3'b000;
            advance(8);
        end
    endtask

    // ── Assertion helpers ─────────────────────────────────────────────────
    task assert_one_op;
        input [7:0] exp_op;
        input [255:0] tag;
        begin
            if (strobe_cnt !== 1) begin
                $display("ERROR [%0s] expected 1 op_strobe, got %0d", tag, strobe_cnt);
                err_cnt = err_cnt + 1;
            end
            if (last_op !== exp_op) begin
                $display("ERROR [%0s] expected op 0x%0h, got 0x%0h", tag, exp_op, last_op);
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task assert_bit;
        input        actual;
        input        expected;
        input [255:0] tag;
        begin
            if (actual !== expected) begin
                $display("ERROR [%0s] expected %0d, got %0d", tag, expected, actual);
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task assert_2bit;
        input [1:0]   actual;
        input [1:0]   expected;
        input [255:0] tag;
        begin
            if (actual !== expected) begin
                $display("ERROR [%0s] expected %0d, got %0d", tag, expected, actual);
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task assert_4bit;
        input [3:0]   actual;
        input [3:0]   expected;
        input [255:0] tag;
        begin
            if (actual !== expected) begin
                $display("ERROR [%0s] expected 0x%0h, got 0x%0h", tag, expected, actual);
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task assert_8bit;
        input [7:0]   actual;
        input [7:0]   expected;
        input [255:0] tag;
        begin
            if (actual !== expected) begin
                $display("ERROR [%0s] expected 0x%0h, got 0x%0h", tag, expected, actual);
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    // ── Stimulus ──────────────────────────────────────────────────────────
    initial begin
        clk            = 1'b0;
        rst            = 1'b1;
        hw_test_en     = 1'b1;
        slide_sw       = 4'b0010;
        dip_sw         = 8'b00111001; // gain=1110, slot=01
        btn_raw        = 3'b000;
        fsm_rec_active = 1'b0;
        fsm_play_active= 1'b0;
        fsm_play_paused= 1'b0;
        err_cnt        = 0;
        strobe_cnt     = 0;
        last_op        = 8'h00;

        advance(4);
        rst = 1'b0;
        advance(3);

        // ── Idle decode checks ────────────────────────────────────────────
        assert_2bit(slot_idx,   2'b01, "slot_idx follows dip_sw[1:0]");
        assert_4bit(gain_level, 4'b1110, "gain_level follows dip_sw[5:2]");
        assert_bit(op_strobe,   1'b0,  "op_strobe low at idle");

        // ── BTN0: record / stop-while-recording ───────────────────────────
        clear_observer;
        press_btn(3'b001);
        assert_8bit(op_out,    OP_RECORD, "BTN0 produces record op");
        assert_bit(op_strobe,  1'b0,      "BTN0 op_strobe deasserts after press");
        assert_bit(clr_status_pulse, 1'b0,"BTN0 clr_status_pulse deasserts");
        assert_one_op(OP_RECORD, "BTN0 clean press");

        fsm_rec_active = 1'b1;
        clear_observer;
        press_btn(3'b001);
        assert_8bit(op_out, OP_STOP, "BTN0 produces stop while recording");
        assert_one_op(OP_STOP, "BTN0 stop-while-recording");
        fsm_rec_active = 1'b0;

        // ── BTN1: play / stop-while-playing ──────────────────────────────
        clear_observer;
        press_btn(3'b010);
        assert_8bit(op_out, OP_PLAY, "BTN1 produces play op");
        assert_one_op(OP_PLAY, "BTN1 clean press");

        fsm_play_active = 1'b1;
        clear_observer;
        press_btn(3'b010);
        assert_8bit(op_out, OP_STOP, "BTN1 produces stop while playing");
        assert_one_op(OP_STOP, "BTN1 stop-while-playing");
        fsm_play_active = 1'b0;

        // ── BTN2: pause-resume / delete modifiers ─────────────────────────
        clear_observer;
        press_btn(3'b100);
        assert_8bit(op_out, OP_PAUSE_RES, "BTN2 produces pause/resume op");
        assert_one_op(OP_PAUSE_RES, "BTN2 clean press");

        slide_sw[3] = 1'b1;
        slide_sw[2] = 1'b0;
        clear_observer;
        press_btn(3'b100);
        assert_8bit(op_out, OP_DEL_ONE, "BTN2+SW3 produces del-one op");
        assert_one_op(OP_DEL_ONE, "BTN2 delete modifier");

        slide_sw[2] = 1'b1;
        clear_observer;
        press_btn(3'b100);
        assert_8bit(op_out, OP_DEL_ALL, "BTN2+SW3+SW2 produces del-all op");
        assert_one_op(OP_DEL_ALL, "BTN2 delete-all modifier");

        // ── Long hold must produce exactly one op, not a stream ───────────
        clear_observer;
        btn_raw = 3'b001;
        advance(10);
        assert_bit(btn_edge[0], 1'b0, "long hold does not keep btn_edge asserted");
        btn_raw = 3'b000;
        advance(10);
        assert_one_op(OP_RECORD, "BTN0 long hold one-shot");

        // ── Asynchronous (off-edge) press ─────────────────────────────────
        slide_sw[3] = 1'b0;
        slide_sw[2] = 1'b0;
        clear_observer;
        press_btn_async(3'b001, 2, 23, 8);
        assert_one_op(OP_RECORD, "BTN0 async off-edge press");

        // ── Bouncy press must still produce exactly one op ────────────────
        clear_observer;
        press_btn_bouncy(3'b010);
        assert_one_op(OP_PLAY, "BTN1 bouncy press");

        // ── Near-threshold short tap must not duplicate ───────────────────
        clear_observer;
        press_btn_async(3'b100, 7, 9, 8);
        if (strobe_cnt > 1) begin
            $display("ERROR [BTN2 near-threshold tap] op_strobe fired %0d times (max 1)",
                     strobe_cnt);
            err_cnt = err_cnt + 1;
        end

        // ── Result ────────────────────────────────────────────────────────
        if (err_cnt == 0)
            $display("PASS: tb_hw_input_decoder completed without errors.");
        else
            $display("FAIL: tb_hw_input_decoder completed with %0d error(s).", err_cnt);

        $finish;
    end

endmodule