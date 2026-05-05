`timescale 1ns / 1ps

// DDR2 RAM interface wrapper.
// Translates a simple single-sample read/write interface into the
// 32-bit MIG port protocol.  Byte-lane selection and address alignment
// are handled here based on DATA_BYTE_WIDTH.

module ram_interface_wrapper #(
    parameter DATA_BYTE_WIDTH = 1
)(
    // Clock and reset
    input         clk,          // 100 MHz input clock  → MIG sys_clk
    input         sys_clk,      // 37.5 MHz system clock → all FIFO ports
    input         reset,

    // Logical read/write interface
    input  [25:0] address,
    input  [DATA_BYTE_WIDTH*8-1:0] data_in,
    input         write_enable,
    input         read_request,
    input         read_ack,
    output [DATA_BYTE_WIDTH*8-1:0] data_out,

    // Status
    output        rdy,
    output        rd_data_pres,
    output [25:0] max_ram_address,
    output reg    ledRAM,

    // Derived clock output from MIG
    output        clkout,

    // DDR2 physical pins
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

// -----------------------------------------------------------------------
// Internal wires
// -----------------------------------------------------------------------
wire [31:0] mig_wr_data;        // 32-bit word presented to MIG write port
wire [31:0] mig_rd_data;        // 32-bit word returned from MIG read port
wire [3:0]  mig_wr_mask;        // byte-enable mask (active-low)
wire [29:0] mig_byte_addr;      // byte-aligned address for MIG command port

wire [6:0]  rd_fifo_count;      // number of words waiting in MIG read FIFO
wire [6:0]  wr_fifo_count;      // number of words in MIG write FIFO
wire        calib_complete;     // MIG calibration done flag

// Unused MIG status outputs — declared to keep ISE happy
wire c3_p0_cmd_empty, c3_p0_cmd_full;
wire c3_p0_wr_full,   c3_p0_wr_empty;
wire c3_p0_wr_underrun, c3_p0_wr_error;
wire c3_p0_rd_full,   c3_p0_rd_empty;
wire c3_p0_rd_overflow, c3_p0_rd_error;

// -----------------------------------------------------------------------
// LED indicator — lights when address 1 is first written
// -----------------------------------------------------------------------
always @(posedge sys_clk) begin
    if (write_enable && (address == 26'd1))
        ledRAM <= 1'b1;
end

// -----------------------------------------------------------------------
// Byte-lane mux — parameterised on DATA_BYTE_WIDTH
// -----------------------------------------------------------------------
generate
    if (DATA_BYTE_WIDTH == 1) begin : LANE_8BIT
        // Replicate the 8-bit sample across all four byte lanes
        assign mig_wr_data  = {data_in, data_in, data_in, data_in};

        // Select which byte lane to mask out (active-low enable)
        // addr[1:0]: 00→lane3, 01→lane2, 10→lane1, 11→lane0
        assign mig_wr_mask  = (address[0]) ? ((address[1]) ? 4'b1110 : 4'b1011)
                                           : ((address[1]) ? 4'b1101 : 4'b0111);

        // Extract the correct byte from the returned 32-bit word
        assign data_out     = (address[0]) ? ((address[1]) ? mig_rd_data[7:0]  : mig_rd_data[23:16])
                                           : ((address[1]) ? mig_rd_data[15:8] : mig_rd_data[31:24]);

        assign max_ram_address = 26'h1FFFFFF;
        assign mig_byte_addr   = {4'h0, address[25:2], 2'b00};
    end

    else if (DATA_BYTE_WIDTH == 2) begin : LANE_16BIT
        // Replicate the 16-bit sample across both halfwords
        assign mig_wr_data  = {data_in, data_in};

        // Upper or lower halfword depending on address LSB
        assign mig_wr_mask  = address[0] ? 4'b1100 : 4'b0011;
        assign data_out     = address[0] ? mig_rd_data[15:0] : mig_rd_data[31:16];

        assign max_ram_address = 26'h0FFFFFF;
        assign mig_byte_addr   = {4'h0, address[24:1], 2'b00};
    end

    else if (DATA_BYTE_WIDTH == 4) begin : LANE_32BIT
        // Full 32-bit word — no lane selection needed
        assign mig_wr_data  = data_in;
        assign mig_wr_mask  = 4'b0000;
        assign data_out     = mig_rd_data;

        assign max_ram_address = 26'h07FFFFF;
        assign mig_byte_addr   = {4'h0, address[23:0], 2'b00};
    end
endgenerate

// -----------------------------------------------------------------------
// Status outputs
// -----------------------------------------------------------------------
assign rdy          = calib_complete;
assign rd_data_pres = (rd_fifo_count > 7'h00);

// -----------------------------------------------------------------------
// MIG DDR2 core instantiation
// -----------------------------------------------------------------------
ram_interface #(
    .C3_P0_MASK_SIZE        (4),
    .C3_P0_DATA_PORT_SIZE   (32),
    .C3_P1_MASK_SIZE        (4),
    .C3_P1_DATA_PORT_SIZE   (32),
    .DEBUG_EN               (0),
    .C3_MEMCLK_PERIOD       (3333),
    .C3_CALIB_SOFT_IP       ("TRUE"),
    .C3_SIMULATION          ("FALSE"),
    .C3_RST_ACT_LOW         (0),
    .C3_INPUT_CLK_TYPE      ("SINGLE_ENDED"),
    .C3_MEM_ADDR_ORDER      ("ROW_BANK_COLUMN"),
    .C3_NUM_DQ_PINS         (16),
    .C3_MEM_ADDR_WIDTH      (13),
    .C3_MEM_BANKADDR_WIDTH  (3)
) u_memory_interface (

    // ---- System ----
    .c3_sys_clk             (clk),
    .c3_sys_rst_i           (reset),
    .c3_clk0                (clkout),
    .c3_rst0                (),
    .c3_calib_done          (calib_complete),

    // ---- DDR2 physical pins ----
    .mcb3_dram_ras_n        (hw_ram_rasn),
    .mcb3_dram_cas_n        (hw_ram_casn),
    .mcb3_dram_we_n         (hw_ram_wen),
    .mcb3_dram_ba           (hw_ram_ba),
    .mcb3_dram_udqs         (hw_ram_udqs_p),
    .mcb3_dram_udqs_n       (hw_ram_udqs_n),
    .mcb3_dram_dqs          (hw_ram_ldqs_p),
    .mcb3_dram_dqs_n        (hw_ram_ldqs_n),
    .mcb3_dram_udm          (hw_ram_udm),
    .mcb3_dram_dm           (hw_ram_ldm),
    .mcb3_dram_ck           (hw_ram_ck),
    .mcb3_dram_ck_n         (hw_ram_ckn),
    .mcb3_dram_cke          (hw_ram_cke),
    .mcb3_dram_odt          (hw_ram_odt),
    .mcb3_dram_a            (hw_ram_ad),
    .mcb3_dram_dq           (hw_ram_dq),
    .mcb3_rzq               (hw_rzq_pin),
    .mcb3_zio               (hw_zio_pin),

    // ---- Command port (p0) ----
    .c3_p0_cmd_clk          (sys_clk),
    .c3_p0_cmd_en           (read_request | write_enable),
    .c3_p0_cmd_instr        ({2'b00, read_request}),   // 000=write, 001=read
    .c3_p0_cmd_bl           (6'b000000),               // burst length 1
    .c3_p0_cmd_byte_addr    (mig_byte_addr),
    .c3_p0_cmd_empty        (c3_p0_cmd_empty),
    .c3_p0_cmd_full         (c3_p0_cmd_full),

    // ---- Write port (p0) ----
    .c3_p0_wr_clk           (sys_clk),
    .c3_p0_wr_en            (write_enable),
    .c3_p0_wr_mask          (mig_wr_mask),
    .c3_p0_wr_data          (mig_wr_data),
    .c3_p0_wr_full          (c3_p0_wr_full),
    .c3_p0_wr_empty         (c3_p0_wr_empty),
    .c3_p0_wr_count         (wr_fifo_count),
    .c3_p0_wr_underrun      (c3_p0_wr_underrun),
    .c3_p0_wr_error         (c3_p0_wr_error),

    // ---- Read port (p0) ----
    .c3_p0_rd_clk           (sys_clk),
    .c3_p0_rd_en            (read_ack),
    .c3_p0_rd_data          (mig_rd_data),
    .c3_p0_rd_full          (c3_p0_rd_full),
    .c3_p0_rd_empty         (c3_p0_rd_empty),
    .c3_p0_rd_count         (rd_fifo_count),
    .c3_p0_rd_overflow      (c3_p0_rd_overflow),
    .c3_p0_rd_error         (c3_p0_rd_error)
);

endmodule