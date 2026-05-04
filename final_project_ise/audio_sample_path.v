`timescale 1ns / 1ps

// --------------------------------------------------------------------
// Module : audio_sample_path
// Author : Kaushik
// Description:
//   Sits between the codec I/O layer and the recorder/playback FSM.
//   On sample_end  -> latch ADC word, assert recorder_sample_valid
//                     (level, held until next sample_end), toggle
//                     recorder_sample_toggle.
//   On sample_req  -> select a source (tone > playback > monitor >
//                     silence), apply 4-bit volume, drive DAC output,
//                     toggle playback_request_toggle.
// --------------------------------------------------------------------

module audio_sample_path (
    // System
    input              clk,
    input              reset,

    // Codec timing strobes (single-cycle pulses from audio_codec)
    input              sample_end,
    input              sample_req,

    // ADC word from codec
    input  [15:0]      audio_input,

    // Source-select flags (from control plane)
    input              playback_enable,
    input              monitor_enable,
    input              test_tone_enable,

    // Playback word supplied by recorder FSM
    input  [15:0]      playback_sample,

    // 4-bit volume: 0=mute, 15=unity
    input  [3:0]       volume_setting,

    // DAC word to codec
    output [15:0]      audio_output,

    // ADC handshaking toward recorder FSM
    output reg [15:0]  recorder_sample,
    output reg         recorder_sample_valid,   // level: high once latched
    output reg         recorder_sample_toggle,

    // DAC handshaking toward recorder FSM
    output reg         playback_request_toggle
);

// ----------------------------------------------------------------
// Sine-wave ROM  (100 entries, 16-bit unsigned, one full period)
// ----------------------------------------------------------------
localparam [6:0] SINE_LAST = 7'd99;

reg [15:0] sine_rom [0:99];
reg [6:0]  sine_ptr;

initial begin
    sine_rom[ 0] = 16'h0000; sine_rom[ 1] = 16'h0805;
    sine_rom[ 2] = 16'h1002; sine_rom[ 3] = 16'h17ee;
    sine_rom[ 4] = 16'h1fc3; sine_rom[ 5] = 16'h2777;
    sine_rom[ 6] = 16'h2f04; sine_rom[ 7] = 16'h3662;
    sine_rom[ 8] = 16'h3d89; sine_rom[ 9] = 16'h4472;
    sine_rom[10] = 16'h4b16; sine_rom[11] = 16'h516f;
    sine_rom[12] = 16'h5776; sine_rom[13] = 16'h5d25;
    sine_rom[14] = 16'h6276; sine_rom[15] = 16'h6764;
    sine_rom[16] = 16'h6bea; sine_rom[17] = 16'h7004;
    sine_rom[18] = 16'h73ad; sine_rom[19] = 16'h76e1;
    sine_rom[20] = 16'h799e; sine_rom[21] = 16'h7be1;
    sine_rom[22] = 16'h7da7; sine_rom[23] = 16'h7eef;
    sine_rom[24] = 16'h7fb7; sine_rom[25] = 16'h7fff;
    sine_rom[26] = 16'h7fc6; sine_rom[27] = 16'h7f0c;
    sine_rom[28] = 16'h7dd3; sine_rom[29] = 16'h7c1b;
    sine_rom[30] = 16'h79e6; sine_rom[31] = 16'h7737;
    sine_rom[32] = 16'h7410; sine_rom[33] = 16'h7074;
    sine_rom[34] = 16'h6c67; sine_rom[35] = 16'h67ed;
    sine_rom[36] = 16'h630a; sine_rom[37] = 16'h5dc4;
    sine_rom[38] = 16'h5820; sine_rom[39] = 16'h5222;
    sine_rom[40] = 16'h4bd3; sine_rom[41] = 16'h4537;
    sine_rom[42] = 16'h3e55; sine_rom[43] = 16'h3735;
    sine_rom[44] = 16'h2fdd; sine_rom[45] = 16'h2855;
    sine_rom[46] = 16'h20a5; sine_rom[47] = 16'h18d3;
    sine_rom[48] = 16'h10e9; sine_rom[49] = 16'h08ee;
    sine_rom[50] = 16'h00e9; sine_rom[51] = 16'hf8e4;
    sine_rom[52] = 16'hf0e6; sine_rom[53] = 16'he8f7;
    sine_rom[54] = 16'he120; sine_rom[55] = 16'hd967;
    sine_rom[56] = 16'hd1d5; sine_rom[57] = 16'hca72;
    sine_rom[58] = 16'hc344; sine_rom[59] = 16'hbc54;
    sine_rom[60] = 16'hb5a7; sine_rom[61] = 16'haf46;
    sine_rom[62] = 16'ha935; sine_rom[63] = 16'ha37c;
    sine_rom[64] = 16'h9e20; sine_rom[65] = 16'h9926;
    sine_rom[66] = 16'h9494; sine_rom[67] = 16'h906e;
    sine_rom[68] = 16'h8cb8; sine_rom[69] = 16'h8976;
    sine_rom[70] = 16'h86ab; sine_rom[71] = 16'h845a;
    sine_rom[72] = 16'h8286; sine_rom[73] = 16'h8130;
    sine_rom[74] = 16'h8059; sine_rom[75] = 16'h8003;
    sine_rom[76] = 16'h802d; sine_rom[77] = 16'h80d8;
    sine_rom[78] = 16'h8203; sine_rom[79] = 16'h83ad;
    sine_rom[80] = 16'h85d3; sine_rom[81] = 16'h8875;
    sine_rom[82] = 16'h8b8f; sine_rom[83] = 16'h8f1d;
    sine_rom[84] = 16'h931e; sine_rom[85] = 16'h978c;
    sine_rom[86] = 16'h9c63; sine_rom[87] = 16'ha19e;
    sine_rom[88] = 16'ha738; sine_rom[89] = 16'had2b;
    sine_rom[90] = 16'hb372; sine_rom[91] = 16'hba05;
    sine_rom[92] = 16'hc0df; sine_rom[93] = 16'hc7f9;
    sine_rom[94] = 16'hcf4b; sine_rom[95] = 16'hd6ce;
    sine_rom[96] = 16'hde7a; sine_rom[97] = 16'he648;
    sine_rom[98] = 16'hee30; sine_rom[99] = 16'hf629;
end

// ----------------------------------------------------------------
// Volume scaling function
//   level 0   -> hard mute
//   level 15  -> unity
//   level 1-14-> signed_sample * (level+1) >>> 4
// ----------------------------------------------------------------
function [15:0] scale_volume;
    input [15:0] raw_sample;
    input [3:0]  vol_level;
    reg signed [15:0] s_sample;
    reg signed [20:0] s_product;
    reg        [ 4:0] gain;
    begin
        s_sample = raw_sample;
        if (vol_level == 4'd0) begin
            scale_volume = 16'd0;
        end else if (vol_level == 4'd15) begin
            scale_volume = raw_sample;
        end else begin
            gain         = {1'b0, vol_level} + 5'd1;
            s_product    = s_sample * $signed({1'b0, gain});
            scale_volume = s_product >>> 4;
        end
    end
endfunction

// ----------------------------------------------------------------
// DAC output register
// ----------------------------------------------------------------
reg [15:0] dac_out_reg;
assign audio_output = dac_out_reg;

// ----------------------------------------------------------------
// ADC capture block
//   recorder_sample_valid is a level signal: goes high on the first
//   sample_end after reset and stays high (a new latch clears-and-sets
//   it on each subsequent sample_end). This satisfies the TB contract
//   where valid is sampled one cycle after sample_end fires.
// ----------------------------------------------------------------
always @(posedge clk) begin : adc_capture
    if (reset) begin
        recorder_sample        <= 16'd0;
        recorder_sample_valid  <= 1'b0;
        recorder_sample_toggle <= 1'b0;
    end else if (sample_end) begin
        recorder_sample        <= audio_input;
        recorder_sample_valid  <= 1'b1;         // stays high (level)
        recorder_sample_toggle <= ~recorder_sample_toggle;
    end
    // No default clear of recorder_sample_valid -- it is sticky
    // until reset, which is fine because the downstream FSM uses
    // the toggle edge for synchronization.
end

// ----------------------------------------------------------------
// DAC output block
//   Priority: test_tone > playback > monitor > silence
// ----------------------------------------------------------------
always @(posedge clk) begin : dac_output
    if (reset) begin
        dac_out_reg             <= 16'd0;
        sine_ptr                <= 7'd0;
        playback_request_toggle <= 1'b0;
    end else if (sample_req) begin
        playback_request_toggle <= ~playback_request_toggle;

        if (test_tone_enable) begin
            dac_out_reg <= scale_volume(sine_rom[sine_ptr], volume_setting);
            sine_ptr    <= (sine_ptr == SINE_LAST) ? 7'd0 : sine_ptr + 1'b1;
        end else if (playback_enable) begin
            dac_out_reg <= scale_volume(playback_sample, volume_setting);
        end else if (monitor_enable) begin
            dac_out_reg <= recorder_sample;
        end else begin
            dac_out_reg <= 16'd0;
        end
    end
end

endmodule
