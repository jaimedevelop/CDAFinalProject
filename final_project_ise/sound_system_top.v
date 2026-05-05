`timescale 1ns / 1ps

// First combined subsystem top-level for the final project.
// This version instantiates the major reference subsystems together while
// leaving recorder/playback control behavior minimal.

module sound_system_top (
    input  board_clk_100m,

    input  sys_rst,

    input  serial_rx_in,
    output serial_tx_out,

    inout  aud_adc_lrck,
    input  aud_adc_data,
    inout  aud_dac_lrck,
    output aud_dac_data,
    output aud_xck,
    inout  aud_bclk,
    output aud_i2c_sclk,
    inout  aud_i2c_sdat,
    output aud_mute,

    output ddr2_rasn,
    output ddr2_casn,
    output ddr2_wen,
    output [2:0]  ddr2_bank,
    inout  ddr2_udqs_p,
    inout  ddr2_udqs_n,
    inout  ddr2_ldqs_p,
    inout  ddr2_ldqs_n,
    output ddr2_udm,
    output ddr2_ldm,
    output ddr2_ck,
    output ddr2_ckn,
    output ddr2_cke,
    output ddr2_odt,
    output [12:0] ddr2_addr,
    inout  [15:0] ddr2_dq,
    inout  ddr2_rzq,
    inout  ddr2_zio,

    input  [3:0]  slide_sw,
    input  [7:0]  dip_sw,
    input  [2:0]  push_btn,
    output [7:0]  led_out
);

    // DDR2 wrapper user-side interface
    wire        mem_ready;
    wire        mem_rd_valid;
    wire        mem_status_led;
    wire [25:0] mem_top_addr;
    wire [15:0] mem_rd_data;
    wire        mem_sys_clk;
    wire [15:0] mem_wr_data;
    wire [25:0] mem_addr;
    wire        mem_wr_en;
    wire        mem_rd_req;
    wire        mem_rd_ack;

    // Project-level clocks derived from DDR2 clkout
    wire pll_locked;
    wire clk_cpu;
    wire clk_codec_ref;

    // Codec-local clocks
    wire codec_pll_locked;
    wire clk_codec_main;
    wire clk_audio;
    wire [3:0] codec_init_status;

    // Audio sample interface
    wire [1:0]  aud_sample_end;
    wire [1:0]  aud_sample_req;
    wire [15:0] dac_sample;
    wire [15:0] adc_sample;
    wire [15:0] rec_sample_data;
    wire        rec_sample_valid;
    wire        rec_sample_tog;
    wire [15:0] pb_sample_data;
    wire        pb_path_en;
    wire        pb_req_tog;
    wire        mon_path_en;
    wire        tone_en;
    wire        dbg_mode;

    // CPU (PicoBlaze) wires
    wire [7:0] cpu_port_id;
    wire [7:0] cpu_out_data;
    reg  [7:0] cpu_in_data;
    wire       cpu_rd_strb;
    wire       cpu_wr_strb;
    wire       cpu_irq_ack;
    wire       uart_wr_en;
    reg        uart_rd_en;
    wire [7:0] uart_rx_byte;
    wire       uart_rx_rdy;
    wire       uart_tx_busy;
    reg  [7:0] cmd_byte;
    reg  [1:0] sel_msg;
    reg  [3:0] vol_lvl;
    reg        ui_mon_en;
    reg        ui_tone_en;
    reg        clr_stat;
    reg        cmd_strb;
    wire       cmd_done;
    wire       cmd_invalid;
    wire       ctrl_busy;
    wire       ctrl_rec;
    wire       ctrl_play;
    wire       ctrl_pause;
    wire       ctrl_del;
    wire [7:0] xdomain_cmd;
    wire       xdomain_cmd_strb;
    wire       xdomain_clr;
    wire [1:0] xdomain_sel_msg;
    wire [3:0] xdomain_vol;
    wire       ram_cmd_done;
    wire       ram_cmd_invalid;
    wire       ram_ctrl_busy;
    wire       ram_ctrl_rec;
    wire       ram_ctrl_play;
    wire       ram_ctrl_pause;
    wire       ram_ctrl_del;
    wire       slot_valid;
    wire       slot_full;
    wire [25:0] slot_start_addr;
    wire [25:0] slot_length;
    wire        has_free_slot;
    wire        plan_fits;
    wire [2:0]  ctrl_state;
    wire [3:0]  latched_vol;
    wire [25:0] ctrl_mem_addr;
    wire [15:0] ctrl_mem_wr_data;
    wire        ctrl_mem_wr_en;
    wire        ctrl_mem_rd_req;
    wire        ctrl_mem_rd_ack;
    wire        btn_override_mode;
    wire [2:0]  btn_state;
    wire [2:0]  btn_edge;
    wire [1:0]  btn_sel_msg;
    wire [3:0]  btn_vol;
    wire [7:0]  btn_cmd;
    wire        btn_cmd_strb;
    wire        btn_clr_stat;
    reg  [1:0]  rec_tog_sync;
    reg         rec_tog_seen;
    reg  [1:0]  pb_tog_sync;
    reg         pb_tog_seen;
    reg  [1:0]  mwr_sync;
    reg  [1:0]  mrd_req_sync;
    reg  [1:0]  mrd_dat_sync;
    reg         dbg_rec;
    reg         dbg_mwr;
    reg         dbg_pb_req;
    reg         dbg_mrd_req;
    reg         dbg_mrd_dat;
    reg  [7:0]  led_val;

    localparam [1:0] NUM_MSG_SLOTS    = 2'd3;
    localparam [7:0] OP_PLAY         = 8'h01;
    localparam [7:0] OP_RECORD       = 8'h02;
    localparam [7:0] OP_DELETE       = 8'h03;
    localparam [7:0] OP_DELETE_ALL   = 8'h04;
    localparam [7:0] OP_STOP         = 8'h06;
    localparam [7:0] OP_PAUSE_RESUME = 8'h07;
    localparam [19:0] BTN_DEBOUNCE_CYCLES = 20'd1000000;

    // Project-level 37.5 MHz -> 100 MHz PLL
    project_clk_wiz_37p5_to_100 proj_pll (
        .CLK_IN1  (mem_sys_clk),
        .CLK_OUT1 (clk_cpu),
        .CLK_OUT2 (clk_codec_ref),
        .RESET    (sys_rst),
        .LOCKED   (pll_locked)
    );

    // Codec-local 100 MHz -> 50 MHz / 11.2896 MHz PLL
    clk_wiz_v3_6 codec_pll (
        .CLK_IN1  (clk_codec_ref),
        .CLK_OUT1 (clk_codec_main),
        .CLK_OUT2 (clk_audio),
        .CLK_OUT3 (),
        .RESET    (sys_rst),
        .LOCKED   (codec_pll_locked)
    );

    // DDR2 memory interface
    // In DATA_BYTE_WIDTH = 2 mode:
    //   mem_addr N means logical 16-bit sample address N.
    // `mem_rd_valid` indicates that a requested sample is available on
    // `mem_rd_data`; later playback logic must stage data ahead of use.
    ram_interface_wrapper #(
        .DATA_BYTE_WIDTH(2)
    ) mem_if (
        .address       (mem_addr),
        .data_in       (mem_wr_data),
        .write_enable  (mem_wr_en),
        .read_request  (mem_rd_req),
        .read_ack      (mem_rd_ack),
        .data_out      (mem_rd_data),
        .reset         (sys_rst),
        .clk           (board_clk_100m),
        .hw_ram_rasn   (ddr2_rasn),
        .hw_ram_casn   (ddr2_casn),
        .hw_ram_wen    (ddr2_wen),
        .hw_ram_ba     (ddr2_bank),
        .hw_ram_udqs_p (ddr2_udqs_p),
        .hw_ram_udqs_n (ddr2_udqs_n),
        .hw_ram_ldqs_p (ddr2_ldqs_p),
        .hw_ram_ldqs_n (ddr2_ldqs_n),
        .hw_ram_udm    (ddr2_udm),
        .hw_ram_ldm    (ddr2_ldm),
        .hw_ram_ck     (ddr2_ck),
        .hw_ram_ckn    (ddr2_ckn),
        .hw_ram_cke    (ddr2_cke),
        .hw_ram_odt    (ddr2_odt),
        .hw_ram_ad     (ddr2_addr),
        .hw_ram_dq     (ddr2_dq),
        .hw_rzq_pin    (ddr2_rzq),
        .hw_zio_pin    (ddr2_zio),
        .clkout        (mem_sys_clk),
        .sys_clk       (mem_sys_clk),
        .rdy           (mem_ready),
        .rd_data_pres  (mem_rd_valid),
        .max_ram_address(mem_top_addr),
        .ledRAM        (mem_status_led)
    );

    // Codec configuration
    i2c_av_config codec_cfg_ctrl (
        .clk      (clk_codec_main),
        .reset    (sys_rst),
        .i2c_sclk (aud_i2c_sclk),
        .i2c_sdat (aud_i2c_sdat),
        .status   (codec_init_status)
    );

    assign aud_xck  = clk_audio;
    assign aud_mute = 1'b1;
    assign btn_override_mode = slide_sw[1];
    assign dbg_mode = dip_sw[6];

    hw_input_handler #(
        .DEBOUNCE_CYCLES(BTN_DEBOUNCE_CYCLES),
        .OP_PLAY(OP_PLAY),
        .OP_RECORD(OP_RECORD),
        .OP_DELETE(OP_DELETE),
        .OP_DELETE_ALL(OP_DELETE_ALL),
        .OP_STOP(OP_STOP),
        .OP_PAUSE_RESUME(OP_PAUSE_RESUME)
    ) btn_handler (
        .clk(clk_cpu),
        .reset(sys_rst),
        .btn_mode_active(btn_override_mode),
        .slide_sw(slide_sw),
        .dip_sw(dip_sw),
        .push_btn(push_btn),
        .is_recording(ctrl_rec),
        .is_playing(ctrl_play),
        .is_paused(ctrl_pause),
        .btn_state(btn_state),
        .btn_edge(btn_edge),
        .msg_sel(btn_sel_msg),
        .vol_out(btn_vol),
        .cmd_out(btn_cmd),
        .cmd_pulse(btn_cmd_strb),
        .clr_pulse(btn_clr_stat)
    );

    async_cmd_relay xdomain_bridge (
        .fast_clk(clk_cpu),
        .fast_rst(sys_rst),
        .fast_cmd_in(cmd_byte),
        .fast_cmd_pulse(cmd_strb),
        .fast_clr_pulse(clr_stat),
        .fast_slot_sel(sel_msg),
        .fast_vol_in(vol_lvl),
        .slow_clk(mem_sys_clk),
        .slow_rst(sys_rst),
        .slow_cmd_out(xdomain_cmd),
        .slow_cmd_pulse(xdomain_cmd_strb),
        .slow_clr_pulse(xdomain_clr),
        .slow_slot_sel(xdomain_sel_msg),
        .slow_vol_out(xdomain_vol),
        .slow_busy(ram_ctrl_busy),
        .slow_rec(ram_ctrl_rec),
        .slow_play(ram_ctrl_play),
        .slow_pause(ram_ctrl_pause),
        .slow_invalid(ram_cmd_invalid),
        .slow_done(ram_cmd_done),
        .fast_busy(ctrl_busy),
        .fast_rec(ctrl_rec),
        .fast_play(ctrl_play),
        .fast_pause(ctrl_pause),
        .fast_invalid(cmd_invalid),
        .fast_done(cmd_done)
    );

    // Audio serial/parallel interface
    audio_codec codec_serial (
        .clk         (clk_audio),
        .reset       (sys_rst),
        .sample_end  (aud_sample_end),
        .sample_req  (aud_sample_req),
        .audio_output(dac_sample),
        .audio_input (adc_sample),
        .channel_sel (2'b10),
        .AUD_ADCLRCK (aud_adc_lrck),
        .AUD_ADCDAT  (aud_adc_data),
        .AUD_DACLRCK (aud_dac_lrck),
        .AUD_DACDAT  (aud_dac_data),
        .AUD_BCLK    (aud_bclk)
    );

    assign mon_path_en = slide_sw[0] | ui_mon_en;
    assign tone_en     = dip_sw[7] | ui_tone_en;

    // Project-owned audio sample path. Later FSM work will replace the
    // placeholder pb_sample_data source with RAM-backed playback.
    audio_sample_path sample_path (
        .clk         (clk_audio),
        .reset       (sys_rst),
        .sample_end  (aud_sample_end[1]),
        .sample_req  (aud_sample_req[1]),
        .audio_input (adc_sample),
        .playback_enable(pb_path_en),
        .monitor_enable (mon_path_en),
        .test_tone_enable(tone_en),
        .playback_sample(pb_sample_data),
        .volume_setting (pb_path_en ? latched_vol : vol_lvl),
        .audio_output   (dac_sample),
        .recorder_sample(rec_sample_data),
        .recorder_sample_valid(rec_sample_valid),
        .recorder_sample_toggle(rec_sample_tog),
        .playback_request_toggle(pb_req_tog)
    );

    recorder_control ctrl_core (
        .clk                (mem_sys_clk),
        .reset              (sys_rst),
        .command            (xdomain_cmd),
        .command_strobe     (xdomain_cmd_strb),
        .clear_status       (xdomain_clr),
        .selected_message   (xdomain_sel_msg),
        .volume_setting     (xdomain_vol),
        .recorder_input_sample(rec_sample_data),
        .recorder_input_valid (rec_sample_valid),
        .recorder_input_toggle(rec_sample_tog),
        .playback_request_toggle(pb_req_tog),
        .ram_rdy            (mem_ready),
        .ram_rd_data_pres   (mem_rd_valid),
        .ram_data_out       (mem_rd_data),
        .ram_max_address    (mem_top_addr),
        .command_done       (ram_cmd_done),
        .invalid_command    (ram_cmd_invalid),
        .busy               (ram_ctrl_busy),
        .recording          (ram_ctrl_rec),
        .playing            (ram_ctrl_play),
        .paused             (ram_ctrl_pause),
        .deleting           (ram_ctrl_del),
        .selected_msg_valid (slot_valid),
        .selected_msg_full  (slot_full),
        .selected_msg_start (slot_start_addr),
        .selected_msg_length(slot_length),
        .any_empty_slot     (has_free_slot),
        .slot_plan_fits_ram (plan_fits),
        .state_debug        (ctrl_state),
        .latched_volume_setting(latched_vol),
        .playback_enable    (pb_path_en),
        .playback_sample_data(pb_sample_data),
        .ram_address        (ctrl_mem_addr),
        .ram_data_in        (ctrl_mem_wr_data),
        .ram_write_enable   (ctrl_mem_wr_en),
        .ram_read_request   (ctrl_mem_rd_req),
        .ram_read_ack       (ctrl_mem_rd_ack)
    );

    assign mem_addr    = ctrl_mem_addr;
    assign mem_wr_data = ctrl_mem_wr_data;
    assign mem_wr_en   = ctrl_mem_wr_en;
    assign mem_rd_req  = ctrl_mem_rd_req;
    assign mem_rd_ack  = ctrl_mem_rd_ack;

    // UART
    rs232_uart uart_module (
        .tx_data_in       (cpu_out_data),
        .write_tx_data    (uart_wr_en),
        .rs232_tx         (serial_tx_out),
        .tx_buffer_full   (uart_tx_busy),
        .rx_data_out      (uart_rx_byte),
        .read_rx_data_ack (uart_rd_en),
        .rs232_rx         (serial_rx_in),
        .rx_data_present  (uart_rx_rdy),
        .reset            (sys_rst),
        .clk              (clk_cpu)
    );

    // PicoBlaze CPU
    picoblaze cpu_core (
        .port_id       (cpu_port_id),
        .read_strobe   (cpu_rd_strb),
        .in_port       (cpu_in_data),
        .write_strobe  (cpu_wr_strb),
        .out_port      (cpu_out_data),
        .interrupt     (1'b0),
        .interrupt_ack (cpu_irq_ack),
        .reset         (sys_rst),
        .clk           (clk_cpu)
    );

    assign uart_wr_en = cpu_wr_strb & (cpu_port_id == 8'h03);

    always @(posedge clk_cpu or posedge sys_rst) begin
        if (sys_rst) begin
            cpu_in_data  <= 8'h00;
            uart_rd_en   <= 1'b0;
            cmd_byte     <= 8'h00;
            sel_msg      <= 2'b00;
            vol_lvl      <= 4'h8;
            ui_mon_en    <= 1'b0;
            ui_tone_en   <= 1'b0;
            clr_stat     <= 1'b0;
            cmd_strb     <= 1'b0;
            rec_tog_sync <= 2'b00;
            rec_tog_seen <= 1'b0;
            pb_tog_sync  <= 2'b00;
            pb_tog_seen  <= 1'b0;
            mwr_sync         <= 2'b00;
            mrd_req_sync     <= 2'b00;
            mrd_dat_sync     <= 2'b00;
            dbg_rec          <= 1'b0;
            dbg_mwr          <= 1'b0;
            dbg_pb_req       <= 1'b0;
            dbg_mrd_req      <= 1'b0;
            dbg_mrd_dat      <= 1'b0;
        end else begin
            rec_tog_sync <= {rec_tog_sync[0], rec_sample_tog};
            pb_tog_sync  <= {pb_tog_sync[0], pb_req_tog};
            mwr_sync     <= {mwr_sync[0], ctrl_mem_wr_en};
            mrd_req_sync <= {mrd_req_sync[0], ctrl_mem_rd_req};
            mrd_dat_sync <= {mrd_dat_sync[0], mem_rd_valid};

            if (clr_stat) begin
                dbg_rec     <= 1'b0;
                dbg_mwr     <= 1'b0;
                dbg_pb_req  <= 1'b0;
                dbg_mrd_req <= 1'b0;
                dbg_mrd_dat <= 1'b0;
            end

            if (rec_tog_sync[1] != rec_tog_seen) begin
                rec_tog_seen <= rec_tog_sync[1];
                dbg_rec <= 1'b1;
            end

            if (pb_tog_sync[1] != pb_tog_seen) begin
                pb_tog_seen <= pb_tog_sync[1];
                dbg_pb_req <= 1'b1;
            end

            if (mwr_sync[1])
                dbg_mwr <= 1'b1;

            if (mrd_req_sync[1])
                dbg_mrd_req <= 1'b1;

            if (mrd_dat_sync[1])
                dbg_mrd_dat <= 1'b1;

            clr_stat <= 1'b0;
            cmd_strb <= 1'b0;

            if (btn_override_mode) begin
                sel_msg  <= btn_sel_msg;
                vol_lvl  <= btn_vol;
                cmd_byte <= btn_cmd;
                cmd_strb <= btn_cmd_strb;
                clr_stat <= btn_clr_stat;
            end

            if (!btn_override_mode && cpu_wr_strb) begin
                case (cpu_port_id)
                    8'h10: begin
                        cmd_byte <= cpu_out_data;
                        cmd_strb <= 1'b1;
                    end
                    8'h11: begin
                        if (cpu_out_data[1:0] <= NUM_MSG_SLOTS)
                            sel_msg <= cpu_out_data[1:0];
                    end
                    8'h12: vol_lvl <= cpu_out_data[3:0];
                    8'h13: begin
                        if (cpu_out_data[0]) begin
                            clr_stat <= 1'b1;
                        end
                    end
                    8'h21: begin
                        ui_mon_en  <= cpu_out_data[0];
                        ui_tone_en <= cpu_out_data[1];
                    end
                    default: begin
                    end
                endcase
            end

            case (cpu_port_id)
                8'h00: cpu_in_data <= {1'b0, btn_state, slide_sw};
                8'h01: cpu_in_data <= dip_sw;
                8'h02: cpu_in_data <= uart_rx_byte;
                8'h04: cpu_in_data <= {7'b0, uart_rx_rdy};
                8'h05: cpu_in_data <= {7'b0, uart_tx_busy};
                8'h10: cpu_in_data <= {1'b0,
                                       cmd_invalid,
                                       cmd_done,
                                       1'b0,
                                       ctrl_pause,
                                       ctrl_play,
                                       ctrl_rec,
                                       ctrl_busy};
                8'h11: cpu_in_data <= {6'b0, sel_msg};
                8'h12: cpu_in_data <= {4'b0, vol_lvl};
                8'h13: cpu_in_data <= cmd_byte;
                8'h14: cpu_in_data <= {2'b00, codec_pll_locked, pll_locked,
                                       mem_status_led, mem_rd_valid, mem_ready, sys_rst};
                8'h15: cpu_in_data <= {3'b000,
                                       has_free_slot,
                                       slot_full,
                                       slot_valid,
                                       sel_msg};
                8'h16: cpu_in_data <= slot_length[7:0];
                8'h17: cpu_in_data <= slot_length[15:8];
                8'h18: cpu_in_data <= slot_length[23:16];
                8'h19: cpu_in_data <= {6'b0, slot_length[25:24]};
                8'h1A: cpu_in_data <= slot_start_addr[7:0];
                8'h1B: cpu_in_data <= slot_start_addr[15:8];
                8'h1C: cpu_in_data <= slot_start_addr[23:16];
                8'h1D: cpu_in_data <= {6'b0, slot_start_addr[25:24]};
                8'h1E: cpu_in_data <= mem_top_addr[7:0];
                8'h1F: cpu_in_data <= mem_top_addr[15:8];
                8'h20: cpu_in_data <= {plan_fits, 5'b00000, mem_top_addr[17:16]};
                8'h21: cpu_in_data <= {6'b000000, ui_tone_en, ui_mon_en};
                default: cpu_in_data <= 8'h00;
            endcase

            uart_rd_en <= (!btn_override_mode) && cpu_rd_strb & (cpu_port_id == 8'h02);
        end
    end

    always @(*) begin
        if (dbg_mode) begin
            led_val = {slot_valid,
                       dbg_mrd_dat,
                       dbg_mrd_req,
                       dbg_pb_req,
                       dbg_mwr,
                       dbg_rec,
                       cmd_invalid,
                       mem_ready};
        end else begin
            led_val = {codec_pll_locked,
                       pll_locked,
                       btn_override_mode,
                       ctrl_rec,
                       ctrl_play,
                       ctrl_pause,
                       cmd_invalid,
                       mem_ready};
        end
    end

    assign led_out = led_val;

endmodule
