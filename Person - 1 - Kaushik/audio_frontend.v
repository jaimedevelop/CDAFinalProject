`timescale 1ns / 1ps
// Person 1 - Audio Codec & Hardware Integration
// CDA 4203/4203L Spring 2026
//
// Integration wrapper for the Anvyl SSM2603 audio codec demo.
// Keep the original codec support modules in this folder:
//   audio_codec.v
//   i2c_av_config.v
//   i2c_controller.v
//   clk_wiz_v3_6.vhd
//
// Person 4 should feed clk_100mhz from the final system 100 MHz clock.
// For the final project clocking plan, that 100 MHz clock is generated from
// the RAM interface clkout after the separate top-level clock wizard.

module audio_frontend (
    input  wire        clk_100mhz,
    input  wire        reset,

    // Playback data from memory/controller.
    input  wire [15:0] playback_sample_16,
    input  wire [7:0]  playback_sample_8,
    input  wire        playback_use_8bit,
    input  wire        passthrough_enable,
    input  wire        mute_output,

    // Recording data to memory/controller.
    output reg  [15:0] record_sample_16,
    output wire [7:0]  record_sample_8,

    // Sample timing for the selected audio channel.
    output wire        sample_end,
    output wire        sample_req,

    // Codec setup/status.
    output wire        pll_locked,
    output wire [3:0]  i2c_status,
    output wire        codec_ready,

    // Anvyl audio pins.
    inout  wire        AUD_ADCLRCK,
    input  wire        AUD_ADCDAT,
    inout  wire        AUD_DACLRCK,
    output wire        AUD_DACDAT,
    output wire        AUD_XCK,
    inout  wire        AUD_BCLK,
    output wire        AUD_I2C_SCLK,
    inout  wire        AUD_I2C_SDAT,
    output wire        AUD_MUTE
);

    wire        main_clk;
    wire        audio_clk;
    wire [1:0]  sample_end_bus;
    wire [1:0]  sample_req_bus;
    wire [15:0] codec_audio_input;
    wire [15:0] codec_audio_output;
    wire [15:0] playback_sample_expanded;

    assign sample_end = sample_end_bus[1];
    assign sample_req = sample_req_bus[1];

    // The memory controller in the current repo uses 8-bit samples. For that
    // path, keep the signed sample's upper byte and restore it to 16 bits.
    assign record_sample_8 = record_sample_16[15:8];
    assign playback_sample_expanded = playback_use_8bit
                                    ? {playback_sample_8, 8'h00}
                                    : playback_sample_16;

    assign codec_audio_output = mute_output
                              ? 16'h0000
                              : (passthrough_enable
                                 ? record_sample_16
                                 : playback_sample_expanded);

    assign AUD_XCK = audio_clk;
    assign AUD_MUTE = 1'b1;  // SSM2603 mute is active low.
    assign codec_ready = pll_locked && (i2c_status == 4'ha);

    // Original audio demo clock wizard:
    // clk_100mhz -> 50 MHz main_clk and 11.2896 MHz audio_clk.
    clk_wiz_v3_6 audio_pll (
        .CLK_IN1  (clk_100mhz),
        .CLK_OUT1 (main_clk),
        .CLK_OUT2 (audio_clk),
        .RESET    (reset),
        .LOCKED   (pll_locked)
    );

    // I2C codec configuration. FPGA is master, codec is slave.
    i2c_av_config codec_config (
        .clk      (main_clk),
        .reset    (reset),
        .i2c_sclk (AUD_I2C_SCLK),
        .i2c_sdat (AUD_I2C_SDAT),
        .status   (i2c_status)
    );

    // Serial/parallel conversion for the selected channel.
    audio_codec codec (
        .clk          (audio_clk),
        .reset        (reset),
        .sample_end   (sample_end_bus),
        .sample_req   (sample_req_bus),
        .audio_output (codec_audio_output),
        .audio_input  (codec_audio_input),
        .channel_sel  (2'b10),
        .AUD_ADCLRCK  (AUD_ADCLRCK),
        .AUD_ADCDAT   (AUD_ADCDAT),
        .AUD_DACLRCK  (AUD_DACLRCK),
        .AUD_DACDAT   (AUD_DACDAT),
        .AUD_BCLK     (AUD_BCLK)
    );

    always @(posedge audio_clk) begin
        if (reset) begin
            record_sample_16 <= 16'h0000;
        end else if (sample_end) begin
            record_sample_16 <= codec_audio_input;
        end
    end

endmodule
