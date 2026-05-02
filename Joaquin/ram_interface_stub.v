`timescale 1ns / 1ps
// ram_interface_stub.v
// Used ONLY for wrapper-only synthesis (to produce ram_interface_wrapper.ngc).
// Never add this file to the main ISE project.
// box_type = "user_black_box" tells XST this is a pre-compiled core so it
// suppresses pad inference — ngdbuild then substitutes ram_interface.ngc.

(* box_type = "user_black_box" *)
module ram_interface #(
    parameter C3_P0_MASK_SIZE       = 4,
    parameter C3_P0_DATA_PORT_SIZE  = 32,
    parameter C3_P1_MASK_SIZE       = 4,
    parameter C3_P1_DATA_PORT_SIZE  = 32,
    parameter DEBUG_EN              = 0,
    parameter C3_MEMCLK_PERIOD      = 3333,
    parameter C3_CALIB_SOFT_IP      = "TRUE",
    parameter C3_SIMULATION         = "FALSE",
    parameter C3_RST_ACT_LOW        = 0,
    parameter C3_INPUT_CLK_TYPE     = "SINGLE_ENDED",
    parameter C3_MEM_ADDR_ORDER     = "ROW_BANK_COLUMN",
    parameter C3_NUM_DQ_PINS        = 16,
    parameter C3_MEM_ADDR_WIDTH     = 13,
    parameter C3_MEM_BANKADDR_WIDTH = 3
)(
    // System
    input  wire        c3_sys_clk,
    input  wire        c3_sys_rst_i,
    output wire        c3_clk0,
    output wire        c3_rst0,
    output wire        c3_calib_done,

    // DDR2 physical
    output wire        mcb3_dram_ras_n,
    output wire        mcb3_dram_cas_n,
    output wire        mcb3_dram_we_n,
    output wire [2:0]  mcb3_dram_ba,
    inout  wire        mcb3_dram_udqs,
    inout  wire        mcb3_dram_udqs_n,
    inout  wire        mcb3_dram_dqs,
    inout  wire        mcb3_dram_dqs_n,
    output wire        mcb3_dram_udm,
    output wire        mcb3_dram_dm,
    output wire        mcb3_dram_ck,
    output wire        mcb3_dram_ck_n,
    output wire        mcb3_dram_cke,
    output wire        mcb3_dram_odt,
    output wire [12:0] mcb3_dram_a,
    inout  wire [15:0] mcb3_dram_dq,
    inout  wire        mcb3_rzq,
    inout  wire        mcb3_zio,

    // Port 0 command
    input  wire        c3_p0_cmd_clk,
    input  wire        c3_p0_cmd_en,
    input  wire [2:0]  c3_p0_cmd_instr,
    input  wire [5:0]  c3_p0_cmd_bl,
    input  wire [29:0] c3_p0_cmd_byte_addr,
    output wire        c3_p0_cmd_empty,
    output wire        c3_p0_cmd_full,

    // Port 0 write
    input  wire        c3_p0_wr_clk,
    input  wire        c3_p0_wr_en,
    input  wire [3:0]  c3_p0_wr_mask,
    input  wire [31:0] c3_p0_wr_data,
    output wire        c3_p0_wr_full,
    output wire        c3_p0_wr_empty,
    output wire [6:0]  c3_p0_wr_count,
    output wire        c3_p0_wr_underrun,
    output wire        c3_p0_wr_error,

    // Port 0 read
    input  wire        c3_p0_rd_clk,
    input  wire        c3_p0_rd_en,
    output wire [31:0] c3_p0_rd_data,
    output wire        c3_p0_rd_full,
    output wire        c3_p0_rd_empty,
    output wire [6:0]  c3_p0_rd_count,
    output wire        c3_p0_rd_overflow,
    output wire        c3_p0_rd_error
);
endmodule