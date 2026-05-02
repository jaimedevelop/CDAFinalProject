`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Stub for ram_interface_wrapper.
// Lives here at the TOP of the hierarchy — no parent above this module,
// so NgdBuild cannot infer pads from stub ports.
// box_type = "user_black_box" causes NgdBuild to substitute
// ram_interface_wrapper.ngc at translate time.
// ---------------------------------------------------------------------------
(* box_type = "user_black_box" *)
module ram_interface_wrapper (
    input  [29:0] ram_cmd_byte_addr,
    input  [31:0] wr_data_in,
    input  [3:0]  write_mask,
    output [31:0] ram_rd_bus,
    input         write_enable,
    input         read_request,
    input         read_ack,
    output        rdy,
    output [6:0]  c3_p0_rd_count,
    input         clk,
    input         reset,
    input         sys_clk,
    output        clkout,
    output        hw_ram_rasn,
    output        hw_ram_casn,
    output        hw_ram_wen,
    output [2:0]  hw_ram_ba,
    output        hw_ram_udqs_p,
    output        hw_ram_udqs_n,
    output        hw_ram_ldqs_p,
    output        hw_ram_ldqs_n,
    output        hw_ram_udm,
    output        hw_ram_ldm,
    output        hw_ram_ck,
    output        hw_ram_ckn,
    output        hw_ram_cke,
    output        hw_ram_odt,
    output [12:0] hw_ram_ad,
    inout  [15:0] hw_ram_dq,
    inout         hw_rzq_pin,
    inout         hw_zio_pin
);
endmodule

// ---------------------------------------------------------------------------
// Person 2 — Standalone test wrapper
// clk_100mhz -> RAMWrapper .clk only (its own IBUFG inside NGC)
// reset      -> RAMWrapper .reset only (its own IBUF inside NGC)
// clkout     -> BUFG -> sys_clk
// FSM resets on !rdy
// DISCARDED when Person 4 integrates the top module.
// ---------------------------------------------------------------------------
module memory_controller_top (
    input  wire        clk_100mhz,
    input  wire        reset,

    input  wire [2:0]  sw_cmd,
    input  wire [2:0]  sw_msg,

    output wire        led_busy,
    output wire        led_mem_full,
    output wire        led_no_msgs,
    output wire [2:0]  led_msg_count,
    output wire        led_rdy,

    output wire        hw_ram_rasn,
    output wire        hw_ram_casn,
    output wire        hw_ram_wen,
    output wire [2:0]  hw_ram_ba,
    output wire        hw_ram_udqs_p,
    output wire        hw_ram_udqs_n,
    output wire        hw_ram_ldqs_p,
    output wire        hw_ram_ldqs_n,
    output wire        hw_ram_udm,
    output wire        hw_ram_ldm,
    output wire        hw_ram_ck,
    output wire        hw_ram_ckn,
    output wire        hw_ram_cke,
    output wire        hw_ram_odt,
    output wire [12:0] hw_ram_ad,
    inout  wire [15:0] hw_ram_dq,
    inout  wire        hw_rzq_pin,
    inout  wire        hw_zio_pin
);

    // -----------------------------------------------------------------------
    // Clock path: RAMWrapper.clkout (unbuffered) -> BUFG -> sys_clk
    // -----------------------------------------------------------------------
    wire        clkout_raw;
    wire        sys_clk;
    wire        rdy;
    wire [6:0]  c3_p0_rd_count;

    BUFG u_sys_clk_buf (
        .I (clkout_raw),
        .O (sys_clk)
    );

    // -----------------------------------------------------------------------
    // Byte-select mux logic (DATA_BYTE_WIDTH=1 hardcoded)
    // Lives here so FSM in memory_controller has no wrapper dependency.
    // -----------------------------------------------------------------------
    wire [25:0] address;
    wire        write_enable;
    wire        read_request;
    wire        read_ack;
    wire [31:0] ram_rd_bus;

    wire [31:0] wr_data_in;
    wire [3:0]  write_mask;
    wire [29:0] ram_cmd_byte_addr;

    wire [7:0]  fake_audio;

    assign wr_data_in        = {fake_audio, fake_audio, fake_audio, fake_audio};
    assign write_mask        = address[0] ? (address[1] ? 4'b1110 : 4'b1011)
                                          : (address[1] ? 4'b1101 : 4'b0111);
    assign ram_cmd_byte_addr = {address[25:2], 2'b00};

    // -----------------------------------------------------------------------
    // RAMWrapper instantiation
    // -----------------------------------------------------------------------
    ram_interface_wrapper RAMWrapper (
        .clk              (clk_100mhz),
        .reset            (reset),
        .sys_clk          (sys_clk),
        .clkout           (clkout_raw),
        .rdy              (rdy),
        .c3_p0_rd_count   (c3_p0_rd_count),
        .ram_cmd_byte_addr(ram_cmd_byte_addr),
        .wr_data_in       (wr_data_in),
        .write_mask       (write_mask),
        .ram_rd_bus       (ram_rd_bus),
        .write_enable     (write_enable),
        .read_request     (read_request),
        .read_ack         (read_ack),
        .hw_ram_rasn      (hw_ram_rasn),
        .hw_ram_casn      (hw_ram_casn),
        .hw_ram_wen       (hw_ram_wen),
        .hw_ram_ba        (hw_ram_ba),
        .hw_ram_udqs_p    (hw_ram_udqs_p),
        .hw_ram_udqs_n    (hw_ram_udqs_n),
        .hw_ram_ldqs_p    (hw_ram_ldqs_p),
        .hw_ram_ldqs_n    (hw_ram_ldqs_n),
        .hw_ram_udm       (hw_ram_udm),
        .hw_ram_ldm       (hw_ram_ldm),
        .hw_ram_ck        (hw_ram_ck),
        .hw_ram_ckn       (hw_ram_ckn),
        .hw_ram_cke       (hw_ram_cke),
        .hw_ram_odt       (hw_ram_odt),
        .hw_ram_ad        (hw_ram_ad),
        .hw_ram_dq        (hw_ram_dq),
        .hw_rzq_pin       (hw_rzq_pin),
        .hw_zio_pin       (hw_zio_pin)
    );

    // -----------------------------------------------------------------------
    // Fake audio: counter increments every 1000 sys_clk cycles
    // -----------------------------------------------------------------------
    reg [9:0] sample_timer = 0;
    reg       sample_end_r = 0;
    reg       sample_req_r = 0;
    reg [7:0] fake_audio_r = 0;

    assign fake_audio = fake_audio_r;

    always @(posedge sys_clk) begin
        if (!rdy) begin
            sample_timer <= 0;
            sample_end_r <= 0;
            sample_req_r <= 0;
            fake_audio_r <= 0;
        end else begin
            sample_end_r <= 0;
            sample_req_r <= 0;
            if (sample_timer == 10'd999) begin
                sample_timer <= 0;
                sample_end_r <= 1;
                sample_req_r <= 1;
                fake_audio_r <= fake_audio_r + 1'b1;
            end else begin
                sample_timer <= sample_timer + 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Memory Controller FSM
    // -----------------------------------------------------------------------
    wire        busy;
    wire [2:0]  msg_count_out;
    wire        mem_full;
    wire        no_msgs;
    wire [7:0]  audio_out_nc;

    memory_controller u_mem_ctrl (
        .sys_clk       (sys_clk),
        .rdy           (rdy),
        .cmd           (sw_cmd),
        .msg_select    (sw_msg),
        .busy          (busy),
        .msg_count_out (msg_count_out),
        .mem_full      (mem_full),
        .no_msgs       (no_msgs),
        .audio_in      (fake_audio),
        .audio_out     (audio_out_nc),
        .sample_end    (sample_end_r),
        .sample_req    (sample_req_r),
        .address       (address),
        .write_enable  (write_enable),
        .read_request  (read_request),
        .read_ack      (read_ack),
        .ram_rd_bus    (ram_rd_bus),
        .c3_p0_rd_count(c3_p0_rd_count)
    );

    assign led_busy      = busy;
    assign led_mem_full  = mem_full;
    assign led_no_msgs   = no_msgs;
    assign led_msg_count = msg_count_out;
    assign led_rdy       = rdy;

endmodule