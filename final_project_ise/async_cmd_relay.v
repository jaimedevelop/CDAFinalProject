`timescale 1ns / 1ps

module async_cmd_relay (
    input         fast_clk,
    input         fast_rst,
    input  [7:0]  fast_cmd_in,
    input         fast_cmd_pulse,
    input         fast_clr_pulse,
    input  [1:0]  fast_slot_sel,
    input  [3:0]  fast_vol_in,

    input         slow_clk,
    input         slow_rst,
    output reg [7:0]  slow_cmd_out,
    output reg        slow_cmd_pulse,
    output reg        slow_clr_pulse,
    output reg [1:0]  slow_slot_sel,
    output reg [3:0]  slow_vol_out,

    input         slow_busy,
    input         slow_rec,
    input         slow_play,
    input         slow_pause,
    input         slow_invalid,
    input         slow_done,
    output        fast_busy,
    output        fast_rec,
    output        fast_play,
    output        fast_pause,
    output        fast_invalid,
    output        fast_done
);

// Command crossing - source (fast) domain state
reg        cmd_tx_tog;
reg [7:0]  cmd_tx_data;
reg [1:0]  cmd_tx_slot;
reg [3:0]  cmd_tx_vol;
reg        cmd_q_vld;
reg [7:0]  cmd_q_data;
reg [1:0]  cmd_q_slot;
reg [3:0]  cmd_q_vol;
reg [1:0]  cmd_ack_sync;
reg        cmd_pending;
reg        cmd_ack_lat;

// Clear-status crossing - source (fast) domain state
reg        clr_tx_tog;
reg        clr_q_vld;
reg [1:0]  clr_ack_sync;
reg        clr_pending;
reg        clr_ack_lat;

// Config crossing - source (fast) domain state
reg        cfg_tx_tog;
reg [1:0]  cfg_tx_slot;
reg [3:0]  cfg_tx_vol;
reg        cfg_q_vld;
reg [1:0]  cfg_q_slot;
reg [3:0]  cfg_q_vol;
reg [1:0]  cfg_ack_sync;
reg [1:0]  cfg_lat_slot;
reg [3:0]  cfg_lat_vol;
reg        cfg_pending;
reg        cfg_ack_lat;

// Command crossing - destination (slow) domain state
reg [1:0]  cmd_rx_sync;
reg        cmd_rx_lat;
reg        cmd_ack_tog;

// Clear crossing - destination (slow) domain state
reg [1:0]  clr_rx_sync;
reg        clr_rx_lat;
reg        clr_ack_tog;

// Config crossing - destination (slow) domain state
reg [1:0]  cfg_rx_sync;
reg        cfg_rx_lat;
reg        cfg_ack_tog;

// Status synchronizers - fast domain
reg [1:0]  busy_sync;
reg [1:0]  rec_sync;
reg [1:0]  play_sync;
reg [1:0]  pause_sync;
reg [1:0]  inv_sync;
reg [1:0]  done_sync;

assign fast_busy    = busy_sync[1];
assign fast_rec     = rec_sync[1];
assign fast_play    = play_sync[1];
assign fast_pause   = pause_sync[1];
assign fast_invalid = inv_sync[1];
assign fast_done    = done_sync[1];

always @(posedge fast_clk or posedge fast_rst) begin
    if (fast_rst) begin
        cmd_tx_tog   <= 1'b0;
        cmd_tx_data  <= 8'h00;
        cmd_tx_slot  <= 2'b00;
        cmd_tx_vol   <= 4'h8;
        cmd_q_vld    <= 1'b0;
        cmd_q_data   <= 8'h00;
        cmd_q_slot   <= 2'b00;
        cmd_q_vol    <= 4'h8;
        cmd_ack_sync <= 2'b00;
        cmd_pending  <= 1'b0;
        cmd_ack_lat  <= 1'b0;

        clr_tx_tog   <= 1'b0;
        clr_q_vld    <= 1'b0;
        clr_ack_sync <= 2'b00;
        clr_pending  <= 1'b0;
        clr_ack_lat  <= 1'b0;

        cfg_tx_tog   <= 1'b0;
        cfg_tx_slot  <= 2'b00;
        cfg_tx_vol   <= 4'h8;
        cfg_q_vld    <= 1'b0;
        cfg_q_slot   <= 2'b00;
        cfg_q_vol    <= 4'h8;
        cfg_ack_sync <= 2'b00;
        cfg_lat_slot <= 2'b00;
        cfg_lat_vol  <= 4'h8;
        cfg_pending  <= 1'b0;
        cfg_ack_lat  <= 1'b0;

        busy_sync    <= 2'b00;
        rec_sync     <= 2'b00;
        play_sync    <= 2'b00;
        pause_sync   <= 2'b00;
        inv_sync     <= 2'b00;
        done_sync    <= 2'b00;
    end else begin
        cmd_ack_sync <= {cmd_ack_sync[0], cmd_ack_tog};
        clr_ack_sync <= {clr_ack_sync[0], clr_ack_tog};
        cfg_ack_sync <= {cfg_ack_sync[0], cfg_ack_tog};

        busy_sync  <= {busy_sync[0], slow_busy};
        rec_sync   <= {rec_sync[0], slow_rec};
        play_sync  <= {play_sync[0], slow_play};
        pause_sync <= {pause_sync[0], slow_pause};
        inv_sync   <= {inv_sync[0], slow_invalid};
        done_sync  <= {done_sync[0], slow_done};

        if (cmd_ack_sync[1] != cmd_ack_lat) begin
            cmd_ack_lat <= cmd_ack_sync[1];
            if (cmd_pending && cmd_q_vld) begin
                cmd_tx_data <= cmd_q_data;
                cmd_tx_slot <= cmd_q_slot;
                cmd_tx_vol  <= cmd_q_vol;
                cmd_tx_tog  <= ~cmd_tx_tog;
                cmd_q_vld   <= 1'b0;
                cmd_pending <= 1'b1;
            end else if (cmd_pending) begin
                cmd_pending <= 1'b0;
            end
        end

        if (fast_cmd_pulse) begin
            if (!cmd_pending) begin
                cmd_tx_data <= fast_cmd_in;
                cmd_tx_slot <= fast_slot_sel;
                cmd_tx_vol  <= fast_vol_in;
                cmd_tx_tog  <= ~cmd_tx_tog;
                cmd_pending <= 1'b1;
                cmd_q_vld   <= 1'b0;
            end else begin
                cmd_q_vld  <= 1'b1;
                cmd_q_data <= fast_cmd_in;
                cmd_q_slot <= fast_slot_sel;
                cmd_q_vol  <= fast_vol_in;
            end
        end

        if (clr_ack_sync[1] != clr_ack_lat) begin
            clr_ack_lat <= clr_ack_sync[1];
            if (clr_pending && clr_q_vld) begin
                clr_tx_tog  <= ~clr_tx_tog;
                clr_q_vld   <= 1'b0;
                clr_pending <= 1'b1;
            end else if (clr_pending) begin
                clr_pending <= 1'b0;
            end
        end

        if (fast_clr_pulse) begin
            if (!clr_pending) begin
                clr_tx_tog  <= ~clr_tx_tog;
                clr_pending <= 1'b1;
                clr_q_vld   <= 1'b0;
            end else begin
                clr_q_vld <= 1'b1;
            end
        end

        if ((fast_slot_sel != cfg_lat_slot) ||
            (fast_vol_in   != cfg_lat_vol)) begin
            cfg_lat_slot <= fast_slot_sel;
            cfg_lat_vol  <= fast_vol_in;
            if (!cfg_pending) begin
                cfg_tx_slot <= fast_slot_sel;
                cfg_tx_vol  <= fast_vol_in;
                cfg_tx_tog  <= ~cfg_tx_tog;
                cfg_pending <= 1'b1;
                cfg_q_vld   <= 1'b0;
            end else begin
                cfg_q_vld  <= 1'b1;
                cfg_q_slot <= fast_slot_sel;
                cfg_q_vol  <= fast_vol_in;
            end
        end

        if (cfg_ack_sync[1] != cfg_ack_lat) begin
            cfg_ack_lat <= cfg_ack_sync[1];
            if (cfg_pending && cfg_q_vld) begin
                cfg_tx_slot <= cfg_q_slot;
                cfg_tx_vol  <= cfg_q_vol;
                cfg_tx_tog  <= ~cfg_tx_tog;
                cfg_q_vld   <= 1'b0;
                cfg_pending <= 1'b1;
            end else if (cfg_pending) begin
                cfg_pending <= 1'b0;
            end
        end
    end
end

always @(posedge slow_clk or posedge slow_rst) begin
    if (slow_rst) begin
        slow_cmd_out  <= 8'h00;
        slow_cmd_pulse <= 1'b0;
        slow_clr_pulse <= 1'b0;
        slow_slot_sel <= 2'b00;
        slow_vol_out  <= 4'h8;

        cmd_rx_sync  <= 2'b00;
        cmd_rx_lat   <= 1'b0;
        cmd_ack_tog  <= 1'b0;

        clr_rx_sync  <= 2'b00;
        clr_rx_lat   <= 1'b0;
        clr_ack_tog  <= 1'b0;

        cfg_rx_sync  <= 2'b00;
        cfg_rx_lat   <= 1'b0;
        cfg_ack_tog  <= 1'b0;
    end else begin
        slow_cmd_pulse <= 1'b0;
        slow_clr_pulse <= 1'b0;

        cmd_rx_sync <= {cmd_rx_sync[0], cmd_tx_tog};
        clr_rx_sync <= {clr_rx_sync[0], clr_tx_tog};
        cfg_rx_sync <= {cfg_rx_sync[0], cfg_tx_tog};

        if (cfg_rx_sync[1] != cfg_rx_lat) begin
            slow_slot_sel <= cfg_tx_slot;
            slow_vol_out  <= cfg_tx_vol;
            cfg_rx_lat    <= cfg_rx_sync[1];
            cfg_ack_tog   <= cfg_rx_sync[1];
        end

        if (cmd_rx_sync[1] != cmd_rx_lat) begin
            slow_cmd_out  <= cmd_tx_data;
            slow_slot_sel <= cmd_tx_slot;
            slow_vol_out  <= cmd_tx_vol;
            slow_cmd_pulse <= 1'b1;
            cmd_rx_lat    <= cmd_rx_sync[1];
            cmd_ack_tog   <= cmd_rx_sync[1];
        end

        if (clr_rx_sync[1] != clr_rx_lat) begin
            slow_clr_pulse <= 1'b1;
            clr_rx_lat     <= clr_rx_sync[1];
            clr_ack_tog    <= clr_rx_sync[1];
        end
    end
end

endmodule
