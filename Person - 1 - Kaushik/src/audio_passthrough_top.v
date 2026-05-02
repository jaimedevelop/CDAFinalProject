`timescale 1ns / 1ps
// Standalone Person 1 hardware test top.
//
// Test behavior:
//   KEY0 - active-low reset button
//   SW0  - microphone passthrough enable
//   SW1  - mute output when high
//   LED0 - codec_ready
//   LED1 - sample_end pulse indicator, visually dim/fast
//   LED2 - sample_req pulse indicator, visually dim/fast
//   LED3 - PLL locked

module audio_passthrough_top (
    input  wire       OSC_100MHz,

    inout  wire       AUD_ADCLRCK,
    input  wire       AUD_ADCDAT,
    inout  wire       AUD_DACLRCK,
    output wire       AUD_DACDAT,
    output wire       AUD_XCK,
    inout  wire       AUD_BCLK,
    output wire       AUD_I2C_SCLK,
    inout  wire       AUD_I2C_SDAT,
    output wire       AUD_MUTE,

    output wire       PLL_LOCKED,
    input  wire [3:0] KEY,
    input  wire [3:0] SW,
    output wire [3:0] LED
);

    wire        reset;
    wire [15:0] record_sample_16;
    wire [7:0]  record_sample_8;
    wire        sample_end;
    wire        sample_req;
    wire [3:0]  i2c_status;
    wire        codec_ready;

    assign reset = !KEY[0];

    audio_frontend audio (
        .clk_100mhz         (OSC_100MHz),
        .reset              (reset),
        .playback_sample_16 (16'h0000),
        .playback_sample_8  (8'h00),
        .playback_use_8bit  (1'b0),
        .passthrough_enable (SW[0]),
        .mute_output        (SW[1]),
        .record_sample_16   (record_sample_16),
        .record_sample_8    (record_sample_8),
        .sample_end         (sample_end),
        .sample_req         (sample_req),
        .pll_locked         (PLL_LOCKED),
        .i2c_status         (i2c_status),
        .codec_ready        (codec_ready),
        .AUD_ADCLRCK        (AUD_ADCLRCK),
        .AUD_ADCDAT         (AUD_ADCDAT),
        .AUD_DACLRCK        (AUD_DACLRCK),
        .AUD_DACDAT         (AUD_DACDAT),
        .AUD_XCK            (AUD_XCK),
        .AUD_BCLK           (AUD_BCLK),
        .AUD_I2C_SCLK       (AUD_I2C_SCLK),
        .AUD_I2C_SDAT       (AUD_I2C_SDAT),
        .AUD_MUTE           (AUD_MUTE)
    );

    assign LED[0] = codec_ready;
    assign LED[1] = sample_end;
    assign LED[2] = sample_req;
    assign LED[3] = PLL_LOCKED;

endmodule
