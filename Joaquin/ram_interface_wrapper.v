`timescale 1ns / 1ps
module ram_interface_wrapper (
    // Command/data ports — raw 32-bit, no byte-select logic here
    input  [29:0] ram_cmd_byte_addr,
    input  [31:0] wr_data_in,
    input  [3:0]  write_mask,
    output [31:0] ram_rd_bus,

    // Control
    input  write_enable,
    input  read_request,
    input  read_ack,

    // Status
    output rdy,
    output [6:0] c3_p0_rd_count,

    // Clocks / reset
    input  clk,
    input  reset,
    input  sys_clk,
    output clkout,

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

    wire c3_calib_done;
    wire [6:0] c3_p0_rd_count_w;

    assign rdy           = c3_calib_done;
    assign c3_p0_rd_count = c3_p0_rd_count_w;

    ram_interface # (
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

        .c3_clk0                (clkout),
        .c3_rst0                (),
        .c3_sys_clk             (clk),
        .c3_sys_rst_i           (reset),
        .c3_calib_done          (c3_calib_done),

        .c3_p0_cmd_clk          (sys_clk),
        .c3_p0_cmd_en           (read_request | write_enable),
        .c3_p0_cmd_instr        ({2'b00, read_request}),
        .c3_p0_cmd_bl           (6'b00_0000),
        .c3_p0_cmd_byte_addr    ({4'h0, ram_cmd_byte_addr}),
        .c3_p0_cmd_empty        (),
        .c3_p0_cmd_full         (),

        .c3_p0_wr_clk           (sys_clk),
        .c3_p0_wr_en            (write_enable),
        .c3_p0_wr_mask          (write_mask),
        .c3_p0_wr_data          (wr_data_in),
        .c3_p0_wr_full          (),
        .c3_p0_wr_empty         (),
        .c3_p0_wr_count         (),
        .c3_p0_wr_underrun      (),
        .c3_p0_wr_error         (),

        .c3_p0_rd_clk           (sys_clk),
        .c3_p0_rd_en            (read_ack),
        .c3_p0_rd_data          (ram_rd_bus),
        .c3_p0_rd_full          (),
        .c3_p0_rd_empty         (),
        .c3_p0_rd_count         (c3_p0_rd_count_w),
        .c3_p0_rd_overflow      (),
        .c3_p0_rd_error         ()
    );

endmodule