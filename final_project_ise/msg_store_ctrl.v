`timescale 1ns / 1ps

// Audio message store/retrieve controller.
// Manages up to four fixed-size message slots in DDR2 RAM.
// Handles record, playback (with prefetch FIFO), pause/resume,
// per-slot delete, and delete-all operations.

module msg_store_ctrl (
    input         clk,
    input         reset,
    input  [7:0]  command,
    input         command_strobe,
    input         clear_status,
    input  [1:0]  selected_message,
    input  [3:0]  volume_setting,
    input  [15:0] recorder_input_sample,
    input         recorder_input_valid,
    input         recorder_input_toggle,
    input         playback_request_toggle,
    input         ram_rdy,
    input         ram_rd_data_pres,
    input  [15:0] ram_data_out,
    input  [25:0] ram_max_address,
    output reg        command_done,
    output reg        invalid_command,
    output            busy,
    output            recording,
    output            playing,
    output            paused,
    output            deleting,
    output            selected_msg_valid,
    output            selected_msg_full,
    output [25:0]     selected_msg_start,
    output [25:0]     selected_msg_length,
    output            any_empty_slot,
    output            slot_plan_fits_ram,
    output [2:0]      state_debug,
    output [3:0]      latched_volume_setting,
    output            playback_enable,
    output [15:0]     playback_sample_data,
    output [25:0]     ram_address,
    output [15:0]     ram_data_in,
    output            ram_write_enable,
    output            ram_read_request,
    output            ram_read_ack
);

// -----------------------------------------------------------------------
// Command opcodes
// -----------------------------------------------------------------------
localparam [7:0] OP_PLAY         = 8'h01;
localparam [7:0] OP_RECORD       = 8'h02;
localparam [7:0] OP_DELETE       = 8'h03;
localparam [7:0] OP_DELETE_ALL   = 8'h04;
localparam [7:0] OP_VOLUME       = 8'h05;
localparam [7:0] OP_STOP         = 8'h06;
localparam [7:0] OP_PAUSE_RESUME = 8'h07;

// -----------------------------------------------------------------------
// Slot layout — four equal-sized regions in DDR2
// -----------------------------------------------------------------------
localparam [25:0] SAMPLES_PER_SLOT  = 26'd4194304;
localparam [25:0] BASE_SLOT0        = 26'd0;
localparam [25:0] BASE_SLOT1        = 26'd4194304;
localparam [25:0] BASE_SLOT2        = 26'd8388608;
localparam [25:0] BASE_SLOT3        = 26'd12582912;
localparam [25:0] LAST_VALID_ADDR   = BASE_SLOT3 + SAMPLES_PER_SLOT - 26'd1;

// -----------------------------------------------------------------------
// FSM encoding
// -----------------------------------------------------------------------
localparam [2:0] ST_IDLE      = 3'd0;
localparam [2:0] ST_REC       = 3'd1;
localparam [2:0] ST_PLAY      = 3'd2;
localparam [2:0] ST_PAUSE     = 3'd3;
localparam [2:0] ST_DEL       = 3'd4;
localparam [2:0] ST_PREFETCH  = 3'd5;

// -----------------------------------------------------------------------
// Playback FIFO sizing
// -----------------------------------------------------------------------
localparam [3:0] FIFO_DEPTH   = 4'd8;
localparam [3:0] PRIME_LEVEL  = 4'd2;   // samples buffered before play starts

// -----------------------------------------------------------------------
// Slot metadata
// -----------------------------------------------------------------------
reg        slot_occupied [0:3];
reg [25:0] slot_base     [0:3];
reg [25:0] slot_used     [0:3];   // number of samples written to this slot

// -----------------------------------------------------------------------
// FSM and control registers
// -----------------------------------------------------------------------
reg [2:0]  fsm;
reg [1:0]  active_slot;
reg [3:0]  active_vol;
reg        wipe_all;
reg        halt_after_sample;       // stop has been requested during record

// -----------------------------------------------------------------------
// Record path
// -----------------------------------------------------------------------
reg [25:0] rec_count;               // samples captured so far this recording
reg [1:0]  rec_tog_pipe;            // two-stage sync for recorder_input_toggle
reg        rec_tog_edge;            // last seen toggle value
reg [15:0] rec_sample_hold;         // latched sample from codec
reg        rec_sample_rdy;          // a new sample is waiting to be written

// -----------------------------------------------------------------------
// RAM bus registers
// -----------------------------------------------------------------------
reg [25:0] bus_addr;
reg [15:0] bus_wdata;
reg        bus_wen;
reg        bus_rreq;
reg        bus_rack;

// -----------------------------------------------------------------------
// Playback path
// -----------------------------------------------------------------------
reg [25:0] pb_fetch_idx;            // next DDR address to fetch (relative to slot base)
reg [25:0] pb_consume_idx;          // samples handed to the codec so far
reg        pb_fetch_pending;        // a read_request is in flight
reg [15:0] pb_out_reg;              // sample currently presented to codec
reg        pb_out_valid;            // pb_out_reg holds a real sample

reg [1:0]  pb_tog_pipe;             // two-stage sync for playback_request_toggle
reg        pb_tog_edge;

// Prefetch FIFO (simple circular buffer, power-of-two depth)
reg [15:0] pb_fifo      [0:7];
reg [2:0]  pb_fifo_wr;
reg [2:0]  pb_fifo_rd;
reg [3:0]  pb_fifo_cnt;

// -----------------------------------------------------------------------
// Convenience wires
// -----------------------------------------------------------------------
wire [1:0]  view_slot;              // slot whose metadata drives the outputs
wire [25:0] active_slot_len;

assign view_slot       = (fsm == ST_IDLE) ? selected_message : active_slot;
assign active_slot_len = slot_used[active_slot];

assign selected_msg_valid  = slot_occupied[view_slot];
assign selected_msg_start  = slot_base[view_slot];
assign selected_msg_length = slot_used[view_slot];
assign selected_msg_full   = (slot_used[view_slot] >= SAMPLES_PER_SLOT);
assign any_empty_slot      = ~(slot_occupied[0] & slot_occupied[1] &
                                slot_occupied[2] & slot_occupied[3]);
assign slot_plan_fits_ram  = (LAST_VALID_ADDR <= ram_max_address);

assign busy      = (fsm != ST_IDLE);
assign recording = (fsm == ST_REC);
assign playing   = (fsm == ST_PLAY);
assign paused    = (fsm == ST_PAUSE);
assign deleting  = (fsm == ST_DEL);
assign state_debug = fsm;

assign latched_volume_setting = active_vol;

assign playback_enable      = (fsm == ST_PLAY) && pb_out_valid;
assign playback_sample_data = pb_out_reg;

assign ram_address     = bus_addr;
assign ram_data_in     = bus_wdata;
assign ram_write_enable = bus_wen;
assign ram_read_request = bus_rreq;
assign ram_read_ack     = bus_rack;

// -----------------------------------------------------------------------
// Helper: reset playback FIFO to empty state
// -----------------------------------------------------------------------
task clear_pb_fifo;
begin
    pb_fifo_wr    <= 3'd0;
    pb_fifo_rd    <= 3'd0;
    pb_fifo_cnt   <= 4'd0;
    pb_out_reg    <= 16'd0;
    pb_out_valid  <= 1'b0;
    pb_fetch_idx  <= 26'd0;
    pb_consume_idx <= 26'd0;
    pb_fetch_pending <= 1'b0;
end
endtask

integer si;

// -----------------------------------------------------------------------
// Main sequential block
// -----------------------------------------------------------------------
always @(posedge clk or posedge reset) begin
    if (reset) begin
        // --- status outputs ---
        command_done    <= 1'b0;
        invalid_command <= 1'b0;

        // --- FSM ---
        fsm             <= ST_IDLE;
        active_slot     <= 2'b00;
        active_vol      <= 4'h8;
        wipe_all        <= 1'b0;
        halt_after_sample <= 1'b0;

        // --- record path ---
        rec_count       <= 26'd0;
        rec_tog_pipe    <= 2'b00;
        rec_tog_edge    <= 1'b0;
        rec_sample_hold <= 16'd0;
        rec_sample_rdy  <= 1'b0;

        // --- RAM bus ---
        bus_addr  <= 26'd0;
        bus_wdata <= 16'd0;
        bus_wen   <= 1'b0;
        bus_rreq  <= 1'b0;
        bus_rack  <= 1'b0;

        // --- playback path ---
        pb_fetch_idx     <= 26'd0;
        pb_consume_idx   <= 26'd0;
        pb_fetch_pending <= 1'b0;
        pb_out_reg       <= 16'd0;
        pb_out_valid     <= 1'b0;
        pb_tog_pipe      <= 2'b00;
        pb_tog_edge      <= 1'b0;
        pb_fifo_wr       <= 3'd0;
        pb_fifo_rd       <= 3'd0;
        pb_fifo_cnt      <= 4'd0;

        // --- slot metadata ---
        slot_occupied[0] <= 1'b0; slot_occupied[1] <= 1'b0;
        slot_occupied[2] <= 1'b0; slot_occupied[3] <= 1'b0;
        slot_base[0]     <= BASE_SLOT0; slot_base[1] <= BASE_SLOT1;
        slot_base[2]     <= BASE_SLOT2; slot_base[3] <= BASE_SLOT3;
        slot_used[0]     <= 26'd0; slot_used[1] <= 26'd0;
        slot_used[2]     <= 26'd0; slot_used[3] <= 26'd0;

    end else begin

        // ---- Synchronise toggle inputs ----
        rec_tog_pipe <= {rec_tog_pipe[0], recorder_input_toggle};
        pb_tog_pipe  <= {pb_tog_pipe[0],  playback_request_toggle};

        // Detect a new codec sample arriving
        if (rec_tog_pipe[1] != rec_tog_edge) begin
            rec_tog_edge    <= rec_tog_pipe[1];
            rec_sample_hold <= recorder_input_sample;
            rec_sample_rdy  <= 1'b1;
        end

        // ---- Default: de-assert single-cycle RAM strobes ----
        bus_wen  <= 1'b0;
        bus_rreq <= 1'b0;
        bus_rack <= 1'b0;

        // ---- Clear status flags when acknowledged ----
        if (clear_status) begin
            command_done    <= 1'b0;
            invalid_command <= 1'b0;
        end

        // ====================================================================
        case (fsm)
        // ====================================================================

        // --------------------------------------------------------------------
        ST_IDLE: begin
        // --------------------------------------------------------------------
            wipe_all          <= 1'b0;
            halt_after_sample <= 1'b0;
            rec_count         <= 26'd0;

            // Reset playback pointers so they are ready for the next command
            pb_fetch_idx      <= 26'd0;
            pb_consume_idx    <= 26'd0;
            pb_fetch_pending  <= 1'b0;
            pb_out_reg        <= 16'd0;
            pb_out_valid      <= 1'b0;
            pb_fifo_wr        <= 3'd0;
            pb_fifo_rd        <= 3'd0;
            pb_fifo_cnt       <= 4'd0;

            // Drain any stale DDR read data left from a previous stop
            if (ram_rd_data_pres)
                bus_rack <= 1'b1;

            if (rec_sample_rdy)
                rec_sample_rdy <= 1'b0;

            if (command_strobe) begin
                command_done    <= 1'b0;
                invalid_command <= 1'b0;

                case (command)

                    OP_PLAY: begin
                        if (!ram_rdy || !slot_occupied[selected_message]) begin
                            invalid_command <= 1'b1;
                        end else begin
                            active_slot    <= selected_message;
                            active_vol     <= volume_setting;
                            // Playback registers already reset above; go prefetch
                            fsm <= ST_PREFETCH;
                        end
                    end

                    OP_RECORD: begin
                        if (!ram_rdy || (slot_used[selected_message] >= SAMPLES_PER_SLOT)) begin
                            invalid_command <= 1'b1;
                        end else begin
                            active_slot                    <= selected_message;
                            active_vol                     <= volume_setting;
                            slot_occupied[selected_message] <= 1'b0;
                            slot_used[selected_message]     <= 26'd0;
                            rec_count                      <= 26'd0;
                            fsm <= ST_REC;
                        end
                    end

                    OP_DELETE: begin
                        active_slot <= selected_message;
                        fsm <= ST_DEL;
                    end

                    OP_DELETE_ALL: begin
                        active_slot <= selected_message;
                        wipe_all    <= 1'b1;
                        fsm <= ST_DEL;
                    end

                    OP_VOLUME: begin
                        active_vol   <= volume_setting;
                        command_done <= 1'b1;
                    end

                    OP_STOP, OP_PAUSE_RESUME:
                        invalid_command <= 1'b1;

                    default:
                        invalid_command <= 1'b1;

                endcase
            end
        end // ST_IDLE

        // --------------------------------------------------------------------
        ST_REC: begin
        // --------------------------------------------------------------------
            // Accept STOP; reject everything else
            if (command_strobe) begin
                if (command == OP_STOP)
                    halt_after_sample <= 1'b1;
                else
                    invalid_command <= 1'b1;
            end

            if (rec_sample_rdy) begin
                // Write this sample to DDR
                bus_addr  <= slot_base[active_slot] + rec_count;
                bus_wdata <= rec_sample_hold;
                bus_wen   <= 1'b1;

                rec_sample_rdy <= 1'b0;
                rec_count      <= rec_count + 26'd1;
                slot_used[active_slot] <= rec_count + 26'd1;

                // Finish when stop requested or slot is full
                if (halt_after_sample || ((rec_count + 26'd1) >= SAMPLES_PER_SLOT)) begin
                    slot_occupied[active_slot] <= 1'b1;
                    command_done  <= 1'b1;
                    halt_after_sample <= 1'b0;
                    fsm <= ST_IDLE;
                end

            end else if (halt_after_sample) begin
                // Stop arrived but we have not yet received even one new sample —
                // finalise with however many were written
                slot_occupied[active_slot] <= (rec_count != 26'd0);
                slot_used[active_slot]     <= rec_count;
                command_done    <= 1'b1;
                halt_after_sample <= 1'b0;
                fsm <= ST_IDLE;
            end
        end // ST_REC

        // --------------------------------------------------------------------
        ST_PREFETCH: begin
        // --------------------------------------------------------------------
            // Accept STOP or VOLUME while buffering
            if (command_strobe) begin
                case (command)
                    OP_STOP: begin
                        clear_pb_fifo;
                        command_done <= 1'b1;
                        fsm <= ST_IDLE;
                    end
                    OP_VOLUME: begin
                        active_vol   <= volume_setting;
                        command_done <= 1'b1;
                    end
                    default: invalid_command <= 1'b1;
                endcase
            end

            // Issue fetch if FIFO has room and there are samples left to fetch
            if (!pb_fetch_pending &&
                (pb_fetch_idx < active_slot_len) &&
                (pb_fifo_cnt < FIFO_DEPTH)) begin
                bus_addr         <= slot_base[active_slot] + pb_fetch_idx;
                bus_rreq         <= 1'b1;
                pb_fetch_pending <= 1'b1;
                pb_fetch_idx     <= pb_fetch_idx + 26'd1;
            end

            // Receive a returned sample into the FIFO
            if (pb_fetch_pending && ram_rd_data_pres) begin
                bus_rack                    <= 1'b1;
                pb_fifo[pb_fifo_wr]         <= ram_data_out;
                pb_fifo_wr                  <= pb_fifo_wr + 3'd1;
                pb_fifo_cnt                 <= pb_fifo_cnt + 4'd1;
                pb_fetch_pending            <= 1'b0;
            end

            // Transition to PLAY once we have enough samples buffered,
            // or the message is shorter than PRIME_LEVEL and all samples are in
            if ((pb_fifo_cnt >= PRIME_LEVEL) ||
                ((pb_fetch_idx >= active_slot_len) &&
                 (pb_fifo_cnt != 4'd0) &&
                 !pb_fetch_pending)) begin
                // Pop the first sample out ready for the codec
                pb_out_reg   <= pb_fifo[pb_fifo_rd];
                pb_fifo_rd   <= pb_fifo_rd + 3'd1;
                pb_fifo_cnt  <= pb_fifo_cnt - 4'd1;
                pb_out_valid <= 1'b1;
                fsm <= ST_PLAY;
            end
        end // ST_PREFETCH

        // --------------------------------------------------------------------
        ST_PLAY: begin
        // --------------------------------------------------------------------
            // Command handling
            if (command_strobe) begin
                case (command)
                    OP_STOP: begin
                        clear_pb_fifo;
                        command_done <= 1'b1;
                        fsm <= ST_IDLE;
                    end
                    OP_PAUSE_RESUME: begin
                        command_done <= 1'b1;
                        fsm <= ST_PAUSE;
                    end
                    OP_VOLUME: begin
                        active_vol   <= volume_setting;
                        command_done <= 1'b1;
                    end
                    default: invalid_command <= 1'b1;
                endcase
            end

            // Keep FIFO topped up while playing
            if (!pb_fetch_pending &&
                (pb_fetch_idx < active_slot_len) &&
                (pb_fifo_cnt < FIFO_DEPTH)) begin
                bus_addr         <= slot_base[active_slot] + pb_fetch_idx;
                bus_rreq         <= 1'b1;
                pb_fetch_pending <= 1'b1;
                pb_fetch_idx     <= pb_fetch_idx + 26'd1;
            end

            if (pb_fetch_pending && ram_rd_data_pres) begin
                bus_rack            <= 1'b1;
                pb_fifo[pb_fifo_wr] <= ram_data_out;
                pb_fifo_wr          <= pb_fifo_wr + 3'd1;
                pb_fifo_cnt         <= pb_fifo_cnt + 4'd1;
                pb_fetch_pending    <= 1'b0;
            end

            // Advance on codec request toggle
            if (pb_tog_pipe[1] != pb_tog_edge) begin
                pb_tog_edge <= pb_tog_pipe[1];

                if (pb_out_valid) begin
                    if ((pb_consume_idx + 26'd1) >= active_slot_len) begin
                        // Last sample consumed — playback complete
                        pb_out_reg     <= 16'd0;
                        pb_out_valid   <= 1'b0;
                        pb_consume_idx <= pb_consume_idx + 26'd1;
                        command_done   <= 1'b1;
                        fsm <= ST_IDLE;

                    end else if (pb_fifo_cnt != 4'd0) begin
                        // Normal advance: pop next sample from FIFO
                        pb_out_reg     <= pb_fifo[pb_fifo_rd];
                        pb_fifo_rd     <= pb_fifo_rd + 3'd1;
                        pb_fifo_cnt    <= pb_fifo_cnt - 4'd1;
                        pb_consume_idx <= pb_consume_idx + 26'd1;

                    end else begin
                        // FIFO underrun — stall and re-prime
                        pb_out_reg     <= 16'd0;
                        pb_out_valid   <= 1'b0;
                        pb_consume_idx <= pb_consume_idx + 26'd1;
                        fsm <= ST_PREFETCH;
                    end
                end
            end
        end // ST_PLAY

        // --------------------------------------------------------------------
        ST_PAUSE: begin
        // --------------------------------------------------------------------
            // Continue filling the FIFO silently while paused
            if (pb_fetch_pending && ram_rd_data_pres) begin
                bus_rack            <= 1'b1;
                pb_fifo[pb_fifo_wr] <= ram_data_out;
                pb_fifo_wr          <= pb_fifo_wr + 3'd1;
                pb_fifo_cnt         <= pb_fifo_cnt + 4'd1;
                pb_fetch_pending    <= 1'b0;
            end

            if (!pb_fetch_pending &&
                (pb_fetch_idx < active_slot_len) &&
                (pb_fifo_cnt < FIFO_DEPTH)) begin
                bus_addr         <= slot_base[active_slot] + pb_fetch_idx;
                bus_rreq         <= 1'b1;
                pb_fetch_pending <= 1'b1;
                pb_fetch_idx     <= pb_fetch_idx + 26'd1;
            end

            // Command handling
            if (command_strobe) begin
                case (command)
                    OP_PAUSE_RESUME: begin
                        command_done <= 1'b1;
                        fsm <= ST_PLAY;
                    end
                    OP_STOP: begin
                        clear_pb_fifo;
                        command_done <= 1'b1;
                        fsm <= ST_IDLE;
                    end
                    OP_VOLUME: begin
                        active_vol   <= volume_setting;
                        command_done <= 1'b1;
                    end
                    default: invalid_command <= 1'b1;
                endcase
            end
        end // ST_PAUSE

        // --------------------------------------------------------------------
        ST_DEL: begin
        // --------------------------------------------------------------------
            if (command_strobe)
                invalid_command <= 1'b1;

            if (wipe_all) begin
                for (si = 0; si < 4; si = si + 1) begin
                    slot_occupied[si] <= 1'b0;
                    slot_used[si]     <= 26'd0;
                end
            end else begin
                slot_occupied[active_slot] <= 1'b0;
                slot_used[active_slot]     <= 26'd0;
            end

            command_done <= 1'b1;
            fsm <= ST_IDLE;
        end // ST_DEL

        default: fsm <= ST_IDLE;

        endcase
    end
end

endmodule