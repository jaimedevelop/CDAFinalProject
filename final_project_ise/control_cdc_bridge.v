`timescale 1ns / 1ps

module control_cdc_bridge (
    input         src_clk,
    input         src_reset,
    input  [7:0]  src_command,
    input         src_command_strobe,
    input         src_clear_status,
    input  [1:0]  src_selected_message,
    input  [3:0]  src_volume_setting,

    input         dst_clk,
    input         dst_reset,
    output reg [7:0]  dst_command,
    output reg        dst_command_strobe,
    output reg        dst_clear_status,
    output reg [1:0]  dst_selected_message,
    output reg [3:0]  dst_volume_setting,

    input         dst_busy,
    input         dst_recording,
    input         dst_playing,
    input         dst_paused,
    input         dst_invalid_command,
    input         dst_command_done,
    output        src_busy,
    output        src_recording,
    output        src_playing,
    output        src_paused,
    output        src_invalid_command,
    output        src_command_done
);

reg        cmd_req_toggle_src;
reg [7:0]  cmd_hold_src;
reg [1:0]  cmd_slot_hold_src;
reg [3:0]  cmd_volume_hold_src;
reg        cmd_queue_valid_src;
reg [7:0]  cmd_queue_src;
reg [1:0]  cmd_slot_queue_src;
reg [3:0]  cmd_volume_queue_src;
reg [1:0]  cmd_ack_sync_src;
reg        cmd_inflight_src;
reg        cmd_ack_seen_src;

reg        clr_req_toggle_src;
reg        clr_queue_valid_src;
reg [1:0]  clr_ack_sync_src;
reg        clr_inflight_src;
reg        clr_ack_seen_src;

reg        cfg_req_toggle_src;
reg [1:0]  cfg_slot_hold_src;
reg [3:0]  cfg_volume_hold_src;
reg        cfg_queue_valid_src;
reg [1:0]  cfg_slot_queue_src;
reg [3:0]  cfg_volume_queue_src;
reg [1:0]  cfg_ack_sync_src;
reg [1:0]  cfg_seen_slot_src;
reg [3:0]  cfg_seen_volume_src;
reg        cfg_inflight_src;
reg        cfg_ack_seen_src;

reg [1:0]  cmd_req_sync_dst;
reg        cmd_req_seen_dst;
reg        cmd_ack_toggle_dst;

reg [1:0]  clr_req_sync_dst;
reg        clr_req_seen_dst;
reg        clr_ack_toggle_dst;

reg [1:0]  cfg_req_sync_dst;
reg        cfg_req_seen_dst;
reg        cfg_ack_toggle_dst;

reg [1:0]  busy_sync_src;
reg [1:0]  recording_sync_src;
reg [1:0]  playing_sync_src;
reg [1:0]  paused_sync_src;
reg [1:0]  invalid_sync_src;
reg [1:0]  done_sync_src;

assign src_busy            = busy_sync_src[1];
assign src_recording       = recording_sync_src[1];
assign src_playing         = playing_sync_src[1];
assign src_paused          = paused_sync_src[1];
assign src_invalid_command = invalid_sync_src[1];
assign src_command_done    = done_sync_src[1];

always @(posedge src_clk or posedge src_reset) begin
    if (src_reset) begin
        cmd_req_toggle_src   <= 1'b0;
        cmd_hold_src         <= 8'h00;
        cmd_slot_hold_src    <= 2'b00;
        cmd_volume_hold_src  <= 4'h8;
        cmd_queue_valid_src  <= 1'b0;
        cmd_queue_src        <= 8'h00;
        cmd_slot_queue_src   <= 2'b00;
        cmd_volume_queue_src <= 4'h8;
        cmd_ack_sync_src     <= 2'b00;
        cmd_inflight_src     <= 1'b0;
        cmd_ack_seen_src     <= 1'b0;

        clr_req_toggle_src   <= 1'b0;
        clr_queue_valid_src  <= 1'b0;
        clr_ack_sync_src     <= 2'b00;
        clr_inflight_src     <= 1'b0;
        clr_ack_seen_src     <= 1'b0;

        cfg_req_toggle_src    <= 1'b0;
        cfg_slot_hold_src     <= 2'b00;
        cfg_volume_hold_src   <= 4'h8;
        cfg_queue_valid_src   <= 1'b0;
        cfg_slot_queue_src    <= 2'b00;
        cfg_volume_queue_src  <= 4'h8;
        cfg_ack_sync_src      <= 2'b00;
        cfg_seen_slot_src     <= 2'b00;
        cfg_seen_volume_src   <= 4'h8;
        cfg_inflight_src      <= 1'b0;
        cfg_ack_seen_src      <= 1'b0;

        busy_sync_src       <= 2'b00;
        recording_sync_src  <= 2'b00;
        playing_sync_src    <= 2'b00;
        paused_sync_src     <= 2'b00;
        invalid_sync_src    <= 2'b00;
        done_sync_src       <= 2'b00;
    end else begin
        cmd_ack_sync_src <= {cmd_ack_sync_src[0], cmd_ack_toggle_dst};
        clr_ack_sync_src <= {clr_ack_sync_src[0], clr_ack_toggle_dst};
        cfg_ack_sync_src <= {cfg_ack_sync_src[0], cfg_ack_toggle_dst};

        busy_sync_src      <= {busy_sync_src[0], dst_busy};
        recording_sync_src <= {recording_sync_src[0], dst_recording};
        playing_sync_src   <= {playing_sync_src[0], dst_playing};
        paused_sync_src    <= {paused_sync_src[0], dst_paused};
        invalid_sync_src   <= {invalid_sync_src[0], dst_invalid_command};
        done_sync_src      <= {done_sync_src[0], dst_command_done};

        if (cmd_ack_sync_src[1] != cmd_ack_seen_src) begin
            cmd_ack_seen_src <= cmd_ack_sync_src[1];
            if (cmd_inflight_src && cmd_queue_valid_src) begin
                cmd_hold_src        <= cmd_queue_src;
                cmd_slot_hold_src   <= cmd_slot_queue_src;
                cmd_volume_hold_src <= cmd_volume_queue_src;
                cmd_req_toggle_src  <= ~cmd_req_toggle_src;
                cmd_queue_valid_src <= 1'b0;
                cmd_inflight_src    <= 1'b1;
            end else if (cmd_inflight_src) begin
                cmd_inflight_src <= 1'b0;
            end
        end

        if (src_command_strobe) begin
            if (!cmd_inflight_src) begin
                cmd_hold_src        <= src_command;
                cmd_slot_hold_src   <= src_selected_message;
                cmd_volume_hold_src <= src_volume_setting;
                cmd_req_toggle_src  <= ~cmd_req_toggle_src;
                cmd_inflight_src    <= 1'b1;
                cmd_queue_valid_src <= 1'b0;
            end else begin
                cmd_queue_valid_src  <= 1'b1;
                cmd_queue_src        <= src_command;
                cmd_slot_queue_src   <= src_selected_message;
                cmd_volume_queue_src <= src_volume_setting;
            end
        end

        if (clr_ack_sync_src[1] != clr_ack_seen_src) begin
            clr_ack_seen_src <= clr_ack_sync_src[1];
            if (clr_inflight_src && clr_queue_valid_src) begin
                clr_req_toggle_src  <= ~clr_req_toggle_src;
                clr_queue_valid_src <= 1'b0;
                clr_inflight_src    <= 1'b1;
            end else if (clr_inflight_src) begin
                clr_inflight_src <= 1'b0;
            end
        end

        if (src_clear_status) begin
            if (!clr_inflight_src) begin
                clr_req_toggle_src  <= ~clr_req_toggle_src;
                clr_inflight_src    <= 1'b1;
                clr_queue_valid_src <= 1'b0;
            end else begin
                clr_queue_valid_src <= 1'b1;
            end
        end

        if ((src_selected_message != cfg_seen_slot_src) ||
            (src_volume_setting != cfg_seen_volume_src)) begin
            cfg_seen_slot_src   <= src_selected_message;
            cfg_seen_volume_src <= src_volume_setting;
            if (!cfg_inflight_src) begin
                cfg_slot_hold_src    <= src_selected_message;
                cfg_volume_hold_src  <= src_volume_setting;
                cfg_req_toggle_src   <= ~cfg_req_toggle_src;
                cfg_inflight_src     <= 1'b1;
                cfg_queue_valid_src  <= 1'b0;
            end else begin
                cfg_queue_valid_src  <= 1'b1;
                cfg_slot_queue_src   <= src_selected_message;
                cfg_volume_queue_src <= src_volume_setting;
            end
        end

        if (cfg_ack_sync_src[1] != cfg_ack_seen_src) begin
            cfg_ack_seen_src <= cfg_ack_sync_src[1];
            if (cfg_inflight_src && cfg_queue_valid_src) begin
                cfg_slot_hold_src    <= cfg_slot_queue_src;
                cfg_volume_hold_src  <= cfg_volume_queue_src;
                cfg_req_toggle_src   <= ~cfg_req_toggle_src;
                cfg_queue_valid_src  <= 1'b0;
                cfg_inflight_src     <= 1'b1;
            end else if (cfg_inflight_src) begin
                cfg_inflight_src <= 1'b0;
            end
        end
    end
end

always @(posedge dst_clk or posedge dst_reset) begin
    if (dst_reset) begin
        dst_command          <= 8'h00;
        dst_command_strobe   <= 1'b0;
        dst_clear_status     <= 1'b0;
        dst_selected_message <= 2'b00;
        dst_volume_setting   <= 4'h8;

        cmd_req_sync_dst     <= 2'b00;
        cmd_req_seen_dst     <= 1'b0;
        cmd_ack_toggle_dst   <= 1'b0;

        clr_req_sync_dst     <= 2'b00;
        clr_req_seen_dst     <= 1'b0;
        clr_ack_toggle_dst   <= 1'b0;

        cfg_req_sync_dst     <= 2'b00;
        cfg_req_seen_dst     <= 1'b0;
        cfg_ack_toggle_dst   <= 1'b0;
    end else begin
        dst_command_strobe <= 1'b0;
        dst_clear_status   <= 1'b0;

        cmd_req_sync_dst <= {cmd_req_sync_dst[0], cmd_req_toggle_src};
        clr_req_sync_dst <= {clr_req_sync_dst[0], clr_req_toggle_src};
        cfg_req_sync_dst <= {cfg_req_sync_dst[0], cfg_req_toggle_src};

        if (cfg_req_sync_dst[1] != cfg_req_seen_dst) begin
            dst_selected_message <= cfg_slot_hold_src;
            dst_volume_setting   <= cfg_volume_hold_src;
            cfg_req_seen_dst     <= cfg_req_sync_dst[1];
            cfg_ack_toggle_dst   <= cfg_req_sync_dst[1];
        end

        if (cmd_req_sync_dst[1] != cmd_req_seen_dst) begin
            dst_command          <= cmd_hold_src;
            dst_selected_message <= cmd_slot_hold_src;
            dst_volume_setting   <= cmd_volume_hold_src;
            dst_command_strobe   <= 1'b1;
            cmd_req_seen_dst     <= cmd_req_sync_dst[1];
            cmd_ack_toggle_dst   <= cmd_req_sync_dst[1];
        end

        if (clr_req_sync_dst[1] != clr_req_seen_dst) begin
            dst_clear_status   <= 1'b1;
            clr_req_seen_dst   <= clr_req_sync_dst[1];
            clr_ack_toggle_dst <= clr_req_sync_dst[1];
        end
    end
end

endmodule
