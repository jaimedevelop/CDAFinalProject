`timescale 1ns / 1ps
// Person 2 — Memory & Storage Controller
// CDA 4203/4203L Spring 2026

module memory_controller #(
    parameter MAX_MESSAGES       = 8,
    parameter MAX_RECORD_SAMPLES = 32768
)(
    // Clocks / calibration
    input  wire        sys_clk,
    input  wire        rdy,

    // picoBlaze / Person 4 interface
    input  wire [2:0]  cmd,
    input  wire [2:0]  msg_select,
    output reg         busy,
    output reg  [2:0]  msg_count_out,
    output reg         mem_full,
    output reg         no_msgs,

    // Codec / Person 1 interface
    input  wire [7:0]  audio_in,
    output reg  [7:0]  audio_out,
    input  wire        sample_end,
    input  wire        sample_req,

    // RAM interface (connects to RAMWrapper in top)
    output reg  [25:0] address,
    output reg         write_enable,
    output reg         read_request,
    output reg         read_ack,
    input  wire [31:0] ram_rd_bus,
    input  wire [6:0]  c3_p0_rd_count
);

    // -----------------------------------------------------------------------
    // CMD encoding
    // -----------------------------------------------------------------------
    localparam CMD_IDLE    = 3'b000;
    localparam CMD_RECORD  = 3'b001;
    localparam CMD_PLAY    = 3'b010;
    localparam CMD_PAUSE   = 3'b011;
    localparam CMD_DEL_ONE = 3'b100;
    localparam CMD_DEL_ALL = 3'b101;
    localparam CMD_STOP    = 3'b110;

    // -----------------------------------------------------------------------
    // FSM states
    // -----------------------------------------------------------------------
    localparam ST_IDLE       = 4'd0;
    localparam ST_REC_WRITE  = 4'd1;
    localparam ST_REC_DONE   = 4'd2;
    localparam ST_PLAY_REQ   = 4'd3;
    localparam ST_PLAY_WAIT  = 4'd4;
    localparam ST_PLAY_DATA  = 4'd5;
    localparam ST_PLAY_PAUSE = 4'd6;
    localparam ST_DEL_ONE    = 4'd7;
    localparam ST_DEL_ALL    = 4'd8;

    reg [3:0] state;

    // -----------------------------------------------------------------------
    // Message table
    // -----------------------------------------------------------------------
    reg [25:0] msg_start [0:MAX_MESSAGES-1];
    reg [25:0] msg_end   [0:MAX_MESSAGES-1];
    reg        msg_valid [0:MAX_MESSAGES-1];

    reg [25:0] next_free_addr;
    reg [25:0] play_addr;
    reg [25:0] rec_addr;
    reg [25:0] play_end;

    // max_ram_address for DATA_BYTE_WIDTH=1
    localparam [25:0] MAX_RAM_ADDRESS = 26'h1FFFFFF;

    // rd_data_pres derived from raw count — no logic inside wrapper
    wire rd_data_pres = (c3_p0_rd_count > 7'd0);

    // Byte-select mux — DATA_BYTE_WIDTH=1 hardcoded
    wire [7:0] data_out_byte;
    assign data_out_byte = address[0] ? (address[1] ? ram_rd_bus[7:0]  : ram_rd_bus[23:16])
                                      : (address[1] ? ram_rd_bus[15:8] : ram_rd_bus[31:24]);

    // -----------------------------------------------------------------------
    // Status outputs (combinational)
    // -----------------------------------------------------------------------
    integer i;
    reg [2:0] msg_count;

    always @(*) begin
        msg_count     = 0;
        for (i = 0; i < MAX_MESSAGES; i = i + 1)
            if (msg_valid[i]) msg_count = msg_count + 1'b1;
        msg_count_out = msg_count;
        no_msgs       = (msg_count == 0);
        mem_full      = (next_free_addr >= MAX_RAM_ADDRESS - MAX_RECORD_SAMPLES);
    end

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    integer s;
    reg     slot_found;
    reg [3:0] free_slot;

    always @(posedge sys_clk) begin

        write_enable <= 1'b0;
        read_request <= 1'b0;
        read_ack     <= 1'b0;

        if (!rdy) begin
            state          <= ST_IDLE;
            busy           <= 1'b0;
            next_free_addr <= 26'd0;
            play_addr      <= 26'd0;
            rec_addr       <= 26'd0;
            play_end       <= 26'd0;
            audio_out      <= 8'd0;
            address        <= 26'd0;
            for (i = 0; i < MAX_MESSAGES; i = i + 1) begin
                msg_start[i] <= 26'd0;
                msg_end[i]   <= 26'd0;
                msg_valid[i] <= 1'b0;
            end
        end
        else begin

            case (state)

            ST_IDLE: begin
                busy <= 1'b0;
                case (cmd)
                    CMD_RECORD: begin
                        if (!mem_full && msg_count < MAX_MESSAGES) begin
                            rec_addr <= next_free_addr;
                            busy     <= 1'b1;
                            state    <= ST_REC_WRITE;
                        end
                    end
                    CMD_PLAY: begin
                        if (msg_valid[msg_select]) begin
                            play_addr <= msg_start[msg_select];
                            play_end  <= msg_end[msg_select];
                            busy      <= 1'b1;
                            state     <= ST_PLAY_REQ;
                        end
                    end
                    CMD_DEL_ONE: begin
                        if (msg_valid[msg_select]) begin
                            busy  <= 1'b1;
                            state <= ST_DEL_ONE;
                        end
                    end
                    CMD_DEL_ALL: begin
                        busy  <= 1'b1;
                        state <= ST_DEL_ALL;
                    end
                    default: state <= ST_IDLE;
                endcase
            end

            ST_REC_WRITE: begin
                if (cmd == CMD_STOP) begin
                    state <= ST_REC_DONE;
                end
                else if (sample_end) begin
                    if (rec_addr < next_free_addr + MAX_RECORD_SAMPLES
                        && rec_addr <= MAX_RAM_ADDRESS) begin
                        address      <= rec_addr;
                        write_enable <= 1'b1;
                        rec_addr     <= rec_addr + 1'b1;
                    end
                    else begin
                        state <= ST_REC_DONE;
                    end
                end
            end

            ST_REC_DONE: begin
                slot_found = 1'b0;
                free_slot  = 4'd0;
                for (s = 0; s < MAX_MESSAGES; s = s + 1) begin
                    if (!msg_valid[s] && !slot_found) begin
                        free_slot  = s[3:0];
                        slot_found = 1'b1;
                    end
                end
                if (slot_found) begin
                    msg_start[free_slot] <= next_free_addr;
                    msg_end[free_slot]   <= rec_addr - 1'b1;
                    msg_valid[free_slot] <= 1'b1;
                end
                next_free_addr <= rec_addr;
                busy           <= 1'b0;
                state          <= ST_IDLE;
            end

            ST_PLAY_REQ: begin
                if (cmd == CMD_STOP) begin
                    busy  <= 1'b0;
                    state <= ST_IDLE;
                end
                else if (cmd == CMD_PAUSE) begin
                    state <= ST_PLAY_PAUSE;
                end
                else if (sample_req) begin
                    address      <= play_addr;
                    read_request <= 1'b1;
                    state        <= ST_PLAY_WAIT;
                end
            end

            ST_PLAY_WAIT: begin
                if (rd_data_pres) begin
                    audio_out <= data_out_byte;
                    read_ack  <= 1'b1;
                    state     <= ST_PLAY_DATA;
                end
            end

            ST_PLAY_DATA: begin
                read_ack <= 1'b0;
                if (play_addr >= play_end) begin
                    busy  <= 1'b0;
                    state <= ST_IDLE;
                end
                else begin
                    play_addr <= play_addr + 1'b1;
                    state     <= ST_PLAY_REQ;
                end
            end

            ST_PLAY_PAUSE: begin
                if (cmd == CMD_PLAY) state <= ST_PLAY_REQ;
                if (cmd == CMD_STOP) begin
                    busy  <= 1'b0;
                    state <= ST_IDLE;
                end
            end

            ST_DEL_ONE: begin
                msg_valid[msg_select] <= 1'b0;
                if (msg_end[msg_select] + 1'b1 == next_free_addr)
                    next_free_addr <= msg_start[msg_select];
                busy  <= 1'b0;
                state <= ST_IDLE;
            end

            ST_DEL_ALL: begin
                for (i = 0; i < MAX_MESSAGES; i = i + 1) begin
                    msg_valid[i] <= 1'b0;
                    msg_start[i] <= 26'd0;
                    msg_end[i]   <= 26'd0;
                end
                next_free_addr <= 26'd0;
                busy           <= 1'b0;
                state          <= ST_IDLE;
            end

            default: state <= ST_IDLE;
            endcase
        end
    end

endmodule