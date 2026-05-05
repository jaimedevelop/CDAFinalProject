`timescale 1ns / 1ps

// First combined subsystem top-level for the final project.
// This version instantiates the major reference subsystems together while
// leaving recorder/playback control behavior minimal.

module audio_recorder_top (
    input  OSC_100MHz,

    input  reset,

    input  rs232_rx,
    output rs232_tx,

    inout  AUD_ADCLRCK,
    input  AUD_ADCDAT,
    inout  AUD_DACLRCK,
    output AUD_DACDAT,
    output AUD_XCK,
    inout  AUD_BCLK,
    output AUD_I2C_SCLK,
    inout  AUD_I2C_SDAT,
    output AUD_MUTE,

    output hw_ram_rasn,
    output hw_ram_casn,
    output hw_ram_wen,
    output [2:0] hw_ram_ba,
    inout  hw_ram_udqs_p,
    inout  hw_ram_udqs_n,
    inout  hw_ram_ldqs_p,
    inout  hw_ram_ldqs_n,
    output hw_ram_udm,
    output hw_ram_ldm,
    output hw_ram_ck,
    output hw_ram_ckn,
    output hw_ram_cke,
    output hw_ram_odt,
    output [12:0] hw_ram_ad,
    inout  [15:0] hw_ram_dq,
    inout  hw_rzq_pin,
    inout  hw_zio_pin,

    input  [3:0] switches,
    input  [7:0] dip_switches,
    input  [2:0] buttons,
    output [7:0] leds
);

    // DDR2 wrapper user-side interface
    wire        ram_rdy;
    wire        ram_rd_data_pres;
    wire        ram_led;
    wire [25:0] ram_max_address;
    wire [15:0] ram_data_out;
    wire        ram_ui_clk;
    wire [15:0] ram_data_in;
    wire [25:0] ram_address;
    wire        ram_write_enable;
    wire        ram_read_request;
    wire        ram_read_ack;

    // Project-level clocks derived from DDR2 clkout
    wire project_clk_locked;
    wire project_clk_pb;
    wire project_clk_codec_ref;

    // Codec-local clocks
    wire codec_clk_locked;
    wire main_clk;
    wire audio_clk;
    wire [3:0] codec_cfg_status;

    // Audio sample interface
    wire [1:0]  sample_end;
    wire [1:0]  sample_req;
    wire [15:0] audio_output;
    wire [15:0] audio_input;
    wire [15:0] recorder_input_sample;
    wire        recorder_input_valid;
    wire        recorder_input_toggle;
    wire [15:0] playback_sample_data;
    wire        playback_path_enable;
    wire        playback_request_toggle;
    wire        monitor_path_enable;
    wire        test_tone_enable;
    wire        debug_status_mode;

    // PicoBlaze wires
    wire [7:0] pb_port_id;
    wire [7:0] pb_out_port;
    reg  [7:0] pb_in_port;
    wire       pb_read_strobe;
    wire       pb_write_strobe;
    wire       pb_interrupt_ack;
    wire       write_to_uart;
    reg        read_from_uart;
    wire [7:0] uart_rx_data;
    wire       uart_rx_present;
    wire       uart_tx_full;
    reg  [7:0] command_reg;
    reg  [1:0] selected_message_reg;
    reg  [3:0] volume_reg;
    reg        ui_monitor_enable_reg;
    reg        ui_test_tone_enable_reg;
    reg        clear_status_pulse;
    reg        command_strobe_reg;
    wire       command_done_reg;
    wire       invalid_command_reg;
    wire       control_busy;
    wire       control_recording;
    wire       control_playing;
    wire       control_paused;
    wire       control_deleting;
    wire [7:0] bridge_command;
    wire       bridge_command_strobe;
    wire       bridge_clear_status;
    wire [1:0] bridge_selected_message;
    wire [3:0] bridge_volume_setting;
    wire       command_done_ram;
    wire       invalid_command_ram;
    wire       control_busy_ram;
    wire       control_recording_ram;
    wire       control_playing_ram;
    wire       control_paused_ram;
    wire       control_deleting_ram;
    wire       selected_msg_valid;
    wire       selected_msg_full;
    wire [25:0] selected_msg_start;
    wire [25:0] selected_msg_length;
    wire        any_empty_slot;
    wire        slot_plan_fits_ram;
    wire [2:0]  control_state_reg;
    wire [3:0]  control_latched_volume;
    wire [25:0] control_ram_address;
    wire [15:0] control_ram_data_in;
    wire        control_ram_write_enable;
    wire        control_ram_read_request;
    wire        control_ram_read_ack;
    wire        manual_test_mode;
    wire [2:0]  button_pressed;
    wire [2:0]  button_rise;
    wire [1:0]  manual_selected_message;
    wire [3:0]  manual_volume_setting;
    wire [7:0]  manual_command;
    wire        manual_command_strobe;
    wire        manual_clear_status_pulse;
    reg  [1:0]  recorder_toggle_debug_sync;
    reg         recorder_toggle_debug_seen;
    reg  [1:0]  playback_toggle_debug_sync;
    reg         playback_toggle_debug_seen;
    reg  [1:0]  ram_write_debug_sync;
    reg  [1:0]  ram_read_req_debug_sync;
    reg  [1:0]  ram_read_data_debug_sync;
    reg         dbg_record_seen;
    reg         dbg_ram_write_seen;
    reg         dbg_playback_req_seen;
    reg         dbg_ram_read_req_seen;
    reg         dbg_ram_read_data_seen;
    reg  [7:0]  leds_reg;

    localparam [1:0] MESSAGE_SLOT_COUNT = 2'd3;
    localparam [7:0] CMD_PLAY         = 8'h01;
    localparam [7:0] CMD_RECORD       = 8'h02;
    localparam [7:0] CMD_DELETE       = 8'h03;
    localparam [7:0] CMD_DELETE_ALL   = 8'h04;
    localparam [7:0] CMD_STOP         = 8'h06;
    localparam [7:0] CMD_PAUSE_RESUME = 8'h07;
    localparam [19:0] BUTTON_DEBOUNCE_CLKS = 20'd1000000;

    // Project-level 37.5 MHz -> 100 MHz PLL
    project_clk_wiz_37p5_to_100 project_clocks (
        .CLK_IN1  (ram_ui_clk),
        .CLK_OUT1 (project_clk_pb),
        .CLK_OUT2 (project_clk_codec_ref),
        .RESET    (reset),
        .LOCKED   (project_clk_locked)
    );

    // Codec-local 100 MHz -> 50 MHz / 11.2896 MHz PLL
    clk_wiz_v3_6 codec_clocks (
        .CLK_IN1  (project_clk_codec_ref),
        .CLK_OUT1 (main_clk),
        .CLK_OUT2 (audio_clk),
        .CLK_OUT3 (),
        .RESET    (reset),
        .LOCKED   (codec_clk_locked)
    );

    // DDR2 memory interface
    // In DATA_BYTE_WIDTH = 2 mode:
    //   ram_address N means logical 16-bit sample address N.
    // `ram_rd_data_pres` indicates that a requested sample is available on
    // `ram_data_out`; later playback logic must stage data ahead of use.
    ram_interface_wrapper #(
        .DATA_BYTE_WIDTH(2)
    ) ram_if (
        .address       (ram_address),
        .data_in       (ram_data_in),
        .write_enable  (ram_write_enable),
        .read_request  (ram_read_request),
        .read_ack      (ram_read_ack),
        .data_out      (ram_data_out),
        .reset         (reset),
        .clk           (OSC_100MHz),
        .hw_ram_rasn   (hw_ram_rasn),
        .hw_ram_casn   (hw_ram_casn),
        .hw_ram_wen    (hw_ram_wen),
        .hw_ram_ba     (hw_ram_ba),
        .hw_ram_udqs_p (hw_ram_udqs_p),
        .hw_ram_udqs_n (hw_ram_udqs_n),
        .hw_ram_ldqs_p (hw_ram_ldqs_p),
        .hw_ram_ldqs_n (hw_ram_ldqs_n),
        .hw_ram_udm    (hw_ram_udm),
        .hw_ram_ldm    (hw_ram_ldm),
        .hw_ram_ck     (hw_ram_ck),
        .hw_ram_ckn    (hw_ram_ckn),
        .hw_ram_cke    (hw_ram_cke),
        .hw_ram_odt    (hw_ram_odt),
        .hw_ram_ad     (hw_ram_ad),
        .hw_ram_dq     (hw_ram_dq),
        .hw_rzq_pin    (hw_rzq_pin),
        .hw_zio_pin    (hw_zio_pin),
        .clkout        (ram_ui_clk),
        .sys_clk       (ram_ui_clk),
        .rdy           (ram_rdy),
        .rd_data_pres  (ram_rd_data_pres),
        .max_ram_address(ram_max_address),
        .ledRAM        (ram_led)
    );

    // Codec configuration
    i2c_av_config codec_config (
        .clk      (main_clk),
        .reset    (reset),
        .i2c_sclk (AUD_I2C_SCLK),
        .i2c_sdat (AUD_I2C_SDAT),
        .status   (codec_cfg_status)
    );

    assign AUD_XCK  = audio_clk;
    assign AUD_MUTE = 1'b1;
    assign manual_test_mode = switches[1];
    assign debug_status_mode = dip_switches[6];

    manual_control_frontend #(
        .BUTTON_DEBOUNCE_CLKS(BUTTON_DEBOUNCE_CLKS),
        .CMD_PLAY(CMD_PLAY),
        .CMD_RECORD(CMD_RECORD),
        .CMD_DELETE(CMD_DELETE),
        .CMD_DELETE_ALL(CMD_DELETE_ALL),
        .CMD_STOP(CMD_STOP),
        .CMD_PAUSE_RESUME(CMD_PAUSE_RESUME)
    ) manual_frontend (
        .clk(project_clk_pb),
        .reset(reset),
        .manual_test_mode(manual_test_mode),
        .switches(switches),
        .dip_switches(dip_switches),
        .buttons(buttons),
        .control_recording(control_recording),
        .control_playing(control_playing),
        .control_paused(control_paused),
        .button_pressed(button_pressed),
        .button_rise(button_rise),
        .selected_message(manual_selected_message),
        .volume_setting(manual_volume_setting),
        .command(manual_command),
        .command_strobe(manual_command_strobe),
        .clear_status_pulse(manual_clear_status_pulse)
    );

    control_cdc_bridge control_bridge (
        .src_clk(project_clk_pb),
        .src_reset(reset),
        .src_command(command_reg),
        .src_command_strobe(command_strobe_reg),
        .src_clear_status(clear_status_pulse),
        .src_selected_message(selected_message_reg),
        .src_volume_setting(volume_reg),
        .dst_clk(ram_ui_clk),
        .dst_reset(reset),
        .dst_command(bridge_command),
        .dst_command_strobe(bridge_command_strobe),
        .dst_clear_status(bridge_clear_status),
        .dst_selected_message(bridge_selected_message),
        .dst_volume_setting(bridge_volume_setting),
        .dst_busy(control_busy_ram),
        .dst_recording(control_recording_ram),
        .dst_playing(control_playing_ram),
        .dst_paused(control_paused_ram),
        .dst_invalid_command(invalid_command_ram),
        .dst_command_done(command_done_ram),
        .src_busy(control_busy),
        .src_recording(control_recording),
        .src_playing(control_playing),
        .src_paused(control_paused),
        .src_invalid_command(invalid_command_reg),
        .src_command_done(command_done_reg)
    );

    // Audio serial/parallel interface
    audio_codec codec_if (
        .clk         (audio_clk),
        .reset       (reset),
        .sample_end  (sample_end),
        .sample_req  (sample_req),
        .audio_output(audio_output),
        .audio_input (audio_input),
        .channel_sel (2'b10),
        .AUD_ADCLRCK (AUD_ADCLRCK),
        .AUD_ADCDAT  (AUD_ADCDAT),
        .AUD_DACLRCK (AUD_DACLRCK),
        .AUD_DACDAT  (AUD_DACDAT),
        .AUD_BCLK    (AUD_BCLK)
    );

    assign monitor_path_enable  = switches[0] | ui_monitor_enable_reg;
    assign test_tone_enable     = dip_switches[7] | ui_test_tone_enable_reg;

    // Project-owned audio sample path. Later FSM work will replace the
    // placeholder playback_sample_data source with RAM-backed playback.
    audio_sample_path sample_path (
        .clk         (audio_clk),
        .reset       (reset),
        .sample_end  (sample_end[1]),
        .sample_req  (sample_req[1]),
        .audio_input (audio_input),
        .playback_enable(playback_path_enable),
        .monitor_enable (monitor_path_enable),
        .test_tone_enable(test_tone_enable),
        .playback_sample(playback_sample_data),
        .volume_setting (playback_path_enable ? control_latched_volume : volume_reg),
        .audio_output   (audio_output),
        .recorder_sample(recorder_input_sample),
        .recorder_sample_valid(recorder_input_valid),
        .recorder_sample_toggle(recorder_input_toggle),
        .playback_request_toggle(playback_request_toggle)
    );

    msg_store_ctrl control0 (
        .clk                (ram_ui_clk),
        .reset              (reset),
        .command            (bridge_command),
        .command_strobe     (bridge_command_strobe),
        .clear_status       (bridge_clear_status),
        .selected_message   (bridge_selected_message),
        .volume_setting     (bridge_volume_setting),
        .recorder_input_sample(recorder_input_sample),
        .recorder_input_valid (recorder_input_valid),
        .recorder_input_toggle(recorder_input_toggle),
        .playback_request_toggle(playback_request_toggle),
        .ram_rdy            (ram_rdy),
        .ram_rd_data_pres   (ram_rd_data_pres),
        .ram_data_out       (ram_data_out),
        .ram_max_address    (ram_max_address),
        .command_done       (command_done_ram),
        .invalid_command    (invalid_command_ram),
        .busy               (control_busy_ram),
        .recording          (control_recording_ram),
        .playing            (control_playing_ram),
        .paused             (control_paused_ram),
        .deleting           (control_deleting_ram),
        .selected_msg_valid (selected_msg_valid),
        .selected_msg_full  (selected_msg_full),
        .selected_msg_start (selected_msg_start),
        .selected_msg_length(selected_msg_length),
        .any_empty_slot     (any_empty_slot),
        .slot_plan_fits_ram (slot_plan_fits_ram),
        .state_debug        (control_state_reg),
        .latched_volume_setting(control_latched_volume),
        .playback_enable    (playback_path_enable),
        .playback_sample_data(playback_sample_data),
        .ram_address        (control_ram_address),
        .ram_data_in        (control_ram_data_in),
        .ram_write_enable   (control_ram_write_enable),
        .ram_read_request   (control_ram_read_request),
        .ram_read_ack       (control_ram_read_ack)
    );

    assign ram_address      = control_ram_address;
    assign ram_data_in      = control_ram_data_in;
    assign ram_write_enable = control_ram_write_enable;
    assign ram_read_request = control_ram_read_request;
    assign ram_read_ack     = control_ram_read_ack;

    // UART
    rs232_uart uart0 (
        .tx_data_in       (pb_out_port),
        .write_tx_data    (write_to_uart),
        .rs232_tx         (rs232_tx),
        .tx_buffer_full   (uart_tx_full),
        .rx_data_out      (uart_rx_data),
        .read_rx_data_ack (read_from_uart),
        .rs232_rx         (rs232_rx),
        .rx_data_present  (uart_rx_present),
        .reset            (reset),
        .clk              (project_clk_pb)
    );

    // PicoBlaze CPU. The ROM module now comes from the assembled
    // picoblaze/recorder_ui.v output, which defines module ROM_form.
    picoblaze cpu0 (
        .port_id       (pb_port_id),
        .read_strobe   (pb_read_strobe),
        .in_port       (pb_in_port),
        .write_strobe  (pb_write_strobe),
        .out_port      (pb_out_port),
        .interrupt     (1'b0),
        .interrupt_ack (pb_interrupt_ack),
        .reset         (reset),
        .clk           (project_clk_pb)
    );

    assign write_to_uart = pb_write_strobe & (pb_port_id == 8'h03);

    always @(posedge project_clk_pb or posedge reset) begin
        if (reset) begin
            pb_in_port            <= 8'h00;
            read_from_uart        <= 1'b0;
            command_reg           <= 8'h00;
            selected_message_reg  <= 2'b00;
            volume_reg            <= 4'h8;
            ui_monitor_enable_reg <= 1'b0;
            ui_test_tone_enable_reg <= 1'b0;
            clear_status_pulse    <= 1'b0;
            command_strobe_reg    <= 1'b0;
            recorder_toggle_debug_sync <= 2'b00;
            recorder_toggle_debug_seen <= 1'b0;
            playback_toggle_debug_sync <= 2'b00;
            playback_toggle_debug_seen <= 1'b0;
            ram_write_debug_sync <= 2'b00;
            ram_read_req_debug_sync <= 2'b00;
            ram_read_data_debug_sync <= 2'b00;
            dbg_record_seen         <= 1'b0;
            dbg_ram_write_seen      <= 1'b0;
            dbg_playback_req_seen   <= 1'b0;
            dbg_ram_read_req_seen   <= 1'b0;
            dbg_ram_read_data_seen  <= 1'b0;
        end else begin
            recorder_toggle_debug_sync <= {recorder_toggle_debug_sync[0], recorder_input_toggle};
            playback_toggle_debug_sync <= {playback_toggle_debug_sync[0], playback_request_toggle};
            ram_write_debug_sync <= {ram_write_debug_sync[0], control_ram_write_enable};
            ram_read_req_debug_sync <= {ram_read_req_debug_sync[0], control_ram_read_request};
            ram_read_data_debug_sync <= {ram_read_data_debug_sync[0], ram_rd_data_pres};

            if (clear_status_pulse) begin
                dbg_record_seen        <= 1'b0;
                dbg_ram_write_seen     <= 1'b0;
                dbg_playback_req_seen  <= 1'b0;
                dbg_ram_read_req_seen  <= 1'b0;
                dbg_ram_read_data_seen <= 1'b0;
            end

            if (recorder_toggle_debug_sync[1] != recorder_toggle_debug_seen) begin
                recorder_toggle_debug_seen <= recorder_toggle_debug_sync[1];
                dbg_record_seen <= 1'b1;
            end

            if (playback_toggle_debug_sync[1] != playback_toggle_debug_seen) begin
                playback_toggle_debug_seen <= playback_toggle_debug_sync[1];
                dbg_playback_req_seen <= 1'b1;
            end

            if (ram_write_debug_sync[1])
                dbg_ram_write_seen <= 1'b1;

            if (ram_read_req_debug_sync[1])
                dbg_ram_read_req_seen <= 1'b1;

            if (ram_read_data_debug_sync[1])
                dbg_ram_read_data_seen <= 1'b1;

            clear_status_pulse <= 1'b0;
            command_strobe_reg <= 1'b0;

            if (manual_test_mode) begin
                selected_message_reg <= manual_selected_message;
                volume_reg           <= manual_volume_setting;
                command_reg          <= manual_command;
                command_strobe_reg   <= manual_command_strobe;
                clear_status_pulse   <= manual_clear_status_pulse;
            end

            if (!manual_test_mode && pb_write_strobe) begin
                case (pb_port_id)
                    8'h10: begin
                        command_reg        <= pb_out_port;
                        command_strobe_reg <= 1'b1;
                    end
                    8'h11: begin
                        if (pb_out_port[1:0] <= MESSAGE_SLOT_COUNT)
                            selected_message_reg <= pb_out_port[1:0];
                    end
                    8'h12: volume_reg <= pb_out_port[3:0];
                    8'h13: begin
                        if (pb_out_port[0]) begin
                            clear_status_pulse <= 1'b1;
                        end
                    end
                    8'h21: begin
                        ui_monitor_enable_reg <= pb_out_port[0];
                        ui_test_tone_enable_reg <= pb_out_port[1];
                    end
                    default: begin
                    end
                endcase
            end

            case (pb_port_id)
                8'h00: pb_in_port <= {1'b0, button_pressed, switches};
                8'h01: pb_in_port <= dip_switches;
                8'h02: pb_in_port <= uart_rx_data;
                8'h04: pb_in_port <= {7'b0, uart_rx_present};
                8'h05: pb_in_port <= {7'b0, uart_tx_full};
                8'h10: pb_in_port <= {1'b0,
                                      invalid_command_reg,
                                      command_done_reg,
                                      1'b0,
                                      control_paused,
                                      control_playing,
                                      control_recording,
                                      control_busy};
                8'h11: pb_in_port <= {6'b0, selected_message_reg};
                8'h12: pb_in_port <= {4'b0, volume_reg};
                8'h13: pb_in_port <= command_reg;
                8'h14: pb_in_port <= {2'b00, codec_clk_locked, project_clk_locked,
                                      ram_led, ram_rd_data_pres, ram_rdy, reset};
                8'h15: pb_in_port <= {3'b000,
                                      any_empty_slot,
                                      selected_msg_full,
                                      selected_msg_valid,
                                      selected_message_reg};
                8'h16: pb_in_port <= selected_msg_length[7:0];
                8'h17: pb_in_port <= selected_msg_length[15:8];
                8'h18: pb_in_port <= selected_msg_length[23:16];
                8'h19: pb_in_port <= {6'b0, selected_msg_length[25:24]};
                8'h1A: pb_in_port <= selected_msg_start[7:0];
                8'h1B: pb_in_port <= selected_msg_start[15:8];
                8'h1C: pb_in_port <= selected_msg_start[23:16];
                8'h1D: pb_in_port <= {6'b0, selected_msg_start[25:24]};
                8'h1E: pb_in_port <= ram_max_address[7:0];
                8'h1F: pb_in_port <= ram_max_address[15:8];
                8'h20: pb_in_port <= {slot_plan_fits_ram, 5'b00000, ram_max_address[17:16]};
                8'h21: pb_in_port <= {6'b000000, ui_test_tone_enable_reg, ui_monitor_enable_reg};
                default: pb_in_port <= 8'h00;
            endcase

            read_from_uart <= (!manual_test_mode) && pb_read_strobe & (pb_port_id == 8'h02);
        end
    end

    always @(*) begin
        if (debug_status_mode) begin
            leds_reg = {selected_msg_valid,
                        dbg_ram_read_data_seen,
                        dbg_ram_read_req_seen,
                        dbg_playback_req_seen,
                        dbg_ram_write_seen,
                        dbg_record_seen,
                        invalid_command_reg,
                        ram_rdy};
        end else begin
            leds_reg = {codec_clk_locked,
                        project_clk_locked,
                        manual_test_mode,
                        control_recording,
                        control_playing,
                        control_paused,
                        invalid_command_reg,
                        ram_rdy};
        end
    end

    assign leds = leds_reg;

endmodule
