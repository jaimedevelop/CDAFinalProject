`timescale 1ns / 1ps

// Combined recorder/playback control skeleton.
// This module now owns:
// - command acceptance / rejection
// - fixed-slot message metadata
// - high-level control state
// - RAM-backed record and playback control
//
// Playback uses a small FIFO so audio output does not start until samples have
// been prefetched from DDR and so stop/restart leaves the read path clean.

module recorder_control (
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

reg        msg_valid [0:3];
reg [25:0] msg_start [0:3];
reg [25:0] msg_length[0:3];
reg [2:0]  state_reg;
reg        delete_all_pending;
reg [25:0] record_sample_index;
reg [25:0] ram_address_reg;
reg [15:0] ram_data_in_reg;
reg        ram_write_enable_reg;
reg        ram_read_request_reg;
reg        ram_read_ack_reg;
reg [15:0] playback_sample_reg;
reg [1:0]  recorder_toggle_sync;
reg        recorder_toggle_seen;
reg [15:0] recorder_sample_latched;
reg        recorder_sample_pending;
reg        stop_pending;
reg [25:0] playback_read_index;
reg [25:0] playback_samples_consumed;
reg        playback_read_pending;
reg [1:0]  playback_toggle_sync;
reg        playback_toggle_seen;
reg [1:0]  active_selected_message;
reg [3:0]  active_volume_setting;
reg [15:0] playback_fifo [0:7];
reg [2:0]  playback_fifo_wr_ptr;
reg [2:0]  playback_fifo_rd_ptr;
reg [3:0]  playback_fifo_count;
reg        playback_current_valid;

localparam [7:0] CMD_PLAY         = 8'h01;
localparam [7:0] CMD_RECORD       = 8'h02;
localparam [7:0] CMD_DELETE       = 8'h03;
localparam [7:0] CMD_DELETE_ALL   = 8'h04;
localparam [7:0] CMD_VOLUME       = 8'h05;
localparam [7:0] CMD_STOP         = 8'h06;
localparam [7:0] CMD_PAUSE_RESUME = 8'h07;

localparam [25:0] SLOT_SIZE_SAMPLES = 26'd4194304;
localparam [25:0] SLOT0_BASE        = 26'd0;
localparam [25:0] SLOT1_BASE        = 26'd4194304;
localparam [25:0] SLOT2_BASE        = 26'd8388608;
localparam [25:0] SLOT3_BASE        = 26'd12582912;
localparam [25:0] SLOT3_LAST_SAMPLE = SLOT3_BASE + SLOT_SIZE_SAMPLES - 26'd1;

localparam [2:0] STATE_IDLE       = 3'd0;
localparam [2:0] STATE_RECORDING  = 3'd1;
localparam [2:0] STATE_PLAYING    = 3'd2;
localparam [2:0] STATE_PAUSED     = 3'd3;
localparam [2:0] STATE_DELETING   = 3'd4;
localparam [2:0] STATE_PLAY_PRIME = 3'd5;

localparam [3:0] PLAYBACK_FIFO_DEPTH = 4'd8;
localparam [3:0] PLAYBACK_START_LEVEL = 4'd2;

wire [1:0] effective_selected_message;
wire [25:0] effective_msg_length;

assign effective_selected_message = (state_reg == STATE_IDLE) ? selected_message
                                                              : active_selected_message;

assign selected_msg_valid  = msg_valid[effective_selected_message];
assign selected_msg_start  = msg_start[effective_selected_message];
assign selected_msg_length = msg_length[effective_selected_message];
assign selected_msg_full   = (msg_length[effective_selected_message] >= SLOT_SIZE_SAMPLES);
assign any_empty_slot      = ~(msg_valid[0] & msg_valid[1] & msg_valid[2] & msg_valid[3]);
assign slot_plan_fits_ram  = (SLOT3_LAST_SAMPLE <= ram_max_address);
assign latched_volume_setting = active_volume_setting;

assign busy      = (state_reg != STATE_IDLE);
assign recording = (state_reg == STATE_RECORDING);
assign playing   = (state_reg == STATE_PLAYING);
assign paused    = (state_reg == STATE_PAUSED);
assign deleting  = (state_reg == STATE_DELETING);
assign state_debug = state_reg;

assign playback_enable      = (state_reg == STATE_PLAYING) && playback_current_valid;
assign playback_sample_data = playback_sample_reg;
assign ram_address          = ram_address_reg;
assign ram_data_in          = ram_data_in_reg;
assign ram_write_enable     = ram_write_enable_reg;
assign ram_read_request     = ram_read_request_reg;
assign ram_read_ack         = ram_read_ack_reg;
assign effective_msg_length = msg_length[active_selected_message];

integer slot_idx;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        command_done            <= 1'b0;
        invalid_command         <= 1'b0;
        state_reg               <= STATE_IDLE;
        delete_all_pending      <= 1'b0;
        record_sample_index     <= 26'd0;
        ram_address_reg         <= 26'd0;
        ram_data_in_reg         <= 16'd0;
        ram_write_enable_reg    <= 1'b0;
        ram_read_request_reg    <= 1'b0;
        ram_read_ack_reg        <= 1'b0;
        playback_sample_reg     <= 16'd0;
        recorder_toggle_sync    <= 2'b00;
        recorder_toggle_seen    <= 1'b0;
        recorder_sample_latched <= 16'd0;
        recorder_sample_pending <= 1'b0;
        stop_pending            <= 1'b0;
        playback_read_index     <= 26'd0;
        playback_samples_consumed <= 26'd0;
        playback_read_pending   <= 1'b0;
        playback_toggle_sync    <= 2'b00;
        playback_toggle_seen    <= 1'b0;
        active_selected_message <= 2'b00;
        active_volume_setting   <= 4'h8;
        playback_fifo_wr_ptr    <= 3'd0;
        playback_fifo_rd_ptr    <= 3'd0;
        playback_fifo_count     <= 4'd0;
        playback_current_valid  <= 1'b0;
        msg_valid[0]            <= 1'b0;
        msg_valid[1]            <= 1'b0;
        msg_valid[2]            <= 1'b0;
        msg_valid[3]            <= 1'b0;
        msg_start[0]            <= SLOT0_BASE;
        msg_start[1]            <= SLOT1_BASE;
        msg_start[2]            <= SLOT2_BASE;
        msg_start[3]            <= SLOT3_BASE;
        msg_length[0]           <= 26'd0;
        msg_length[1]           <= 26'd0;
        msg_length[2]           <= 26'd0;
        msg_length[3]           <= 26'd0;
    end else begin
        recorder_toggle_sync <= {recorder_toggle_sync[0], recorder_input_toggle};
        playback_toggle_sync <= {playback_toggle_sync[0], playback_request_toggle};

        if (recorder_toggle_sync[1] != recorder_toggle_seen) begin
            recorder_toggle_seen    <= recorder_toggle_sync[1];
            recorder_sample_latched <= recorder_input_sample;
            recorder_sample_pending <= 1'b1;
        end

        ram_write_enable_reg <= 1'b0;
        ram_read_request_reg <= 1'b0;
        ram_read_ack_reg     <= 1'b0;

        if (clear_status) begin
            command_done    <= 1'b0;
            invalid_command <= 1'b0;
        end

        case (state_reg)
            STATE_IDLE: begin
                delete_all_pending       <= 1'b0;
                stop_pending             <= 1'b0;
                record_sample_index      <= msg_length[selected_message];
                playback_read_index      <= 26'd0;
                playback_samples_consumed <= 26'd0;
                playback_read_pending    <= 1'b0;
                playback_sample_reg      <= 16'd0;
                playback_fifo_wr_ptr     <= 3'd0;
                playback_fifo_rd_ptr     <= 3'd0;
                playback_fifo_count      <= 4'd0;
                playback_current_valid   <= 1'b0;

                // Drain any stale unread DDR read data left behind by an earlier
                // stop/restart so the next playback attempt starts cleanly.
                if (ram_rd_data_pres) begin
                    ram_read_ack_reg <= 1'b1;
                end

                if (command_strobe) begin
                    command_done    <= 1'b0;
                    invalid_command <= 1'b0;

                    case (command)
                        CMD_PLAY: begin
                            if (!ram_rdy || !msg_valid[selected_message]) begin
                                invalid_command <= 1'b1;
                            end else begin
                                active_selected_message <= selected_message;
                                active_volume_setting   <= volume_setting;
                                playback_read_index     <= 26'd0;
                                playback_samples_consumed <= 26'd0;
                                playback_read_pending   <= 1'b0;
                                playback_fifo_wr_ptr    <= 3'd0;
                                playback_fifo_rd_ptr    <= 3'd0;
                                playback_fifo_count     <= 4'd0;
                                playback_current_valid  <= 1'b0;
                                playback_sample_reg     <= 16'd0;
                                state_reg               <= STATE_PLAY_PRIME;
                            end
                        end

                        CMD_RECORD: begin
                            if (!ram_rdy || (msg_length[selected_message] >= SLOT_SIZE_SAMPLES)) begin
                                invalid_command <= 1'b1;
                            end else begin
                                active_selected_message     <= selected_message;
                                active_volume_setting       <= volume_setting;
                                msg_valid[selected_message] <= 1'b0;
                                msg_length[selected_message] <= 26'd0;
                                record_sample_index         <= 26'd0;
                                state_reg                   <= STATE_RECORDING;
                            end
                        end

                        CMD_DELETE: begin
                            active_selected_message <= selected_message;
                            state_reg <= STATE_DELETING;
                        end

                        CMD_DELETE_ALL: begin
                            active_selected_message <= selected_message;
                            delete_all_pending <= 1'b1;
                            state_reg          <= STATE_DELETING;
                        end

                        CMD_VOLUME: begin
                            active_volume_setting <= volume_setting;
                            command_done <= 1'b1;
                        end

                        CMD_STOP,
                        CMD_PAUSE_RESUME: begin
                            invalid_command <= 1'b1;
                        end

                        default: begin
                            invalid_command <= 1'b1;
                        end
                    endcase
                end

                if (recorder_sample_pending) begin
                    recorder_sample_pending <= 1'b0;
                end
            end

            STATE_RECORDING: begin
                if (command_strobe && (command == CMD_STOP)) begin
                    stop_pending <= 1'b1;
                end else if (command_strobe && (command == CMD_VOLUME)) begin
                    invalid_command <= 1'b1;
                end else if (command_strobe) begin
                    invalid_command <= 1'b1;
                end

                if (recorder_sample_pending) begin
                    ram_address_reg         <= msg_start[active_selected_message] + record_sample_index;
                    ram_data_in_reg         <= recorder_sample_latched;
                    ram_write_enable_reg    <= 1'b1;
                    recorder_sample_pending <= 1'b0;
                    record_sample_index     <= record_sample_index + 26'd1;
                    msg_length[active_selected_message] <= record_sample_index + 26'd1;

                    if (stop_pending || ((record_sample_index + 26'd1) >= SLOT_SIZE_SAMPLES)) begin
                        msg_valid[active_selected_message] <= 1'b1;
                        command_done <= 1'b1;
                        stop_pending <= 1'b0;
                        state_reg    <= STATE_IDLE;
                    end
                end else if (stop_pending) begin
                    msg_valid[active_selected_message]  <= (record_sample_index != 26'd0);
                    msg_length[active_selected_message] <= record_sample_index;
                    command_done <= 1'b1;
                    stop_pending <= 1'b0;
                    state_reg    <= STATE_IDLE;
                end
            end

            STATE_PLAY_PRIME: begin
                if (command_strobe && (command == CMD_STOP)) begin
                    playback_sample_reg    <= 16'd0;
                    playback_current_valid <= 1'b0;
                    playback_read_pending  <= 1'b0;
                    playback_fifo_wr_ptr   <= 3'd0;
                    playback_fifo_rd_ptr   <= 3'd0;
                    playback_fifo_count    <= 4'd0;
                    command_done           <= 1'b1;
                    state_reg              <= STATE_IDLE;
                end else if (command_strobe && (command == CMD_VOLUME)) begin
                    active_volume_setting <= volume_setting;
                    command_done <= 1'b1;
                end else if (command_strobe) begin
                    invalid_command <= 1'b1;
                end

                if (!playback_read_pending &&
                    (playback_read_index < effective_msg_length) &&
                    (playback_fifo_count < PLAYBACK_FIFO_DEPTH)) begin
                    ram_address_reg       <= msg_start[active_selected_message] + playback_read_index;
                    ram_read_request_reg  <= 1'b1;
                    playback_read_pending <= 1'b1;
                    playback_read_index   <= playback_read_index + 26'd1;
                end

                if (playback_read_pending && ram_rd_data_pres) begin
                    ram_read_ack_reg <= 1'b1;
                    playback_fifo[playback_fifo_wr_ptr] <= ram_data_out;
                    playback_fifo_wr_ptr  <= playback_fifo_wr_ptr + 3'd1;
                    playback_fifo_count   <= playback_fifo_count + 4'd1;
                    playback_read_pending <= 1'b0;
                end

                if ((playback_fifo_count >= PLAYBACK_START_LEVEL) ||
                    ((playback_read_index >= effective_msg_length) &&
                     (playback_fifo_count != 4'd0) &&
                     !playback_read_pending)) begin
                    playback_sample_reg    <= playback_fifo[playback_fifo_rd_ptr];
                    playback_fifo_rd_ptr   <= playback_fifo_rd_ptr + 3'd1;
                    playback_fifo_count    <= playback_fifo_count - 4'd1;
                    playback_current_valid <= 1'b1;
                    state_reg              <= STATE_PLAYING;
                end
            end

            STATE_PLAYING: begin
                if (command_strobe && (command == CMD_STOP)) begin
                    playback_sample_reg    <= 16'd0;
                    playback_current_valid <= 1'b0;
                    playback_read_pending  <= 1'b0;
                    playback_fifo_wr_ptr   <= 3'd0;
                    playback_fifo_rd_ptr   <= 3'd0;
                    playback_fifo_count    <= 4'd0;
                    command_done           <= 1'b1;
                    state_reg              <= STATE_IDLE;
                end else if (command_strobe && (command == CMD_PAUSE_RESUME)) begin
                    command_done <= 1'b1;
                    state_reg    <= STATE_PAUSED;
                end else if (command_strobe && (command == CMD_VOLUME)) begin
                    active_volume_setting <= volume_setting;
                    command_done <= 1'b1;
                end else if (command_strobe) begin
                    invalid_command <= 1'b1;
                end

                if (!playback_read_pending &&
                    (playback_read_index < effective_msg_length) &&
                    (playback_fifo_count < PLAYBACK_FIFO_DEPTH)) begin
                    ram_address_reg       <= msg_start[active_selected_message] + playback_read_index;
                    ram_read_request_reg  <= 1'b1;
                    playback_read_pending <= 1'b1;
                    playback_read_index   <= playback_read_index + 26'd1;
                end

                if (playback_read_pending && ram_rd_data_pres) begin
                    ram_read_ack_reg <= 1'b1;
                    playback_fifo[playback_fifo_wr_ptr] <= ram_data_out;
                    playback_fifo_wr_ptr  <= playback_fifo_wr_ptr + 3'd1;
                    playback_fifo_count   <= playback_fifo_count + 4'd1;
                    playback_read_pending <= 1'b0;
                end

                if (playback_toggle_sync[1] != playback_toggle_seen) begin
                    playback_toggle_seen <= playback_toggle_sync[1];

                    if (playback_current_valid) begin
                        if ((playback_samples_consumed + 26'd1) >= effective_msg_length) begin
                            playback_sample_reg     <= 16'd0;
                            playback_current_valid  <= 1'b0;
                            playback_samples_consumed <= playback_samples_consumed + 26'd1;
                            command_done            <= 1'b1;
                            state_reg               <= STATE_IDLE;
                        end else if (playback_fifo_count != 4'd0) begin
                            playback_sample_reg      <= playback_fifo[playback_fifo_rd_ptr];
                            playback_fifo_rd_ptr     <= playback_fifo_rd_ptr + 3'd1;
                            playback_fifo_count      <= playback_fifo_count - 4'd1;
                            playback_samples_consumed <= playback_samples_consumed + 26'd1;
                        end else begin
                            playback_sample_reg      <= 16'd0;
                            playback_current_valid   <= 1'b0;
                            playback_samples_consumed <= playback_samples_consumed + 26'd1;
                            state_reg                <= STATE_PLAY_PRIME;
                        end
                    end
                end
            end

            STATE_PAUSED: begin
                if (playback_read_pending && ram_rd_data_pres) begin
                    ram_read_ack_reg <= 1'b1;
                    playback_fifo[playback_fifo_wr_ptr] <= ram_data_out;
                    playback_fifo_wr_ptr  <= playback_fifo_wr_ptr + 3'd1;
                    playback_fifo_count   <= playback_fifo_count + 4'd1;
                    playback_read_pending <= 1'b0;
                end

                if (!playback_read_pending &&
                    (playback_read_index < effective_msg_length) &&
                    (playback_fifo_count < PLAYBACK_FIFO_DEPTH)) begin
                    ram_address_reg       <= msg_start[active_selected_message] + playback_read_index;
                    ram_read_request_reg  <= 1'b1;
                    playback_read_pending <= 1'b1;
                    playback_read_index   <= playback_read_index + 26'd1;
                end

                if (command_strobe && (command == CMD_PAUSE_RESUME)) begin
                    command_done <= 1'b1;
                    state_reg    <= STATE_PLAYING;
                end else if (command_strobe && (command == CMD_STOP)) begin
                    playback_sample_reg    <= 16'd0;
                    playback_current_valid <= 1'b0;
                    playback_read_pending  <= 1'b0;
                    playback_fifo_wr_ptr   <= 3'd0;
                    playback_fifo_rd_ptr   <= 3'd0;
                    playback_fifo_count    <= 4'd0;
                    command_done           <= 1'b1;
                    state_reg              <= STATE_IDLE;
                end else if (command_strobe && (command == CMD_VOLUME)) begin
                    active_volume_setting <= volume_setting;
                    command_done <= 1'b1;
                end else if (command_strobe) begin
                    invalid_command <= 1'b1;
                end
            end

            STATE_DELETING: begin
                if (command_strobe) begin
                    invalid_command <= 1'b1;
                end

                if (delete_all_pending) begin
                    for (slot_idx = 0; slot_idx < 4; slot_idx = slot_idx + 1) begin
                        msg_valid[slot_idx]  <= 1'b0;
                        msg_length[slot_idx] <= 26'd0;
                    end
                end else begin
                    msg_valid[active_selected_message]  <= 1'b0;
                    msg_length[active_selected_message] <= 26'd0;
                end

                command_done <= 1'b1;
                state_reg    <= STATE_IDLE;
            end

            default: begin
                state_reg <= STATE_IDLE;
            end
        endcase
    end
end

endmodule
