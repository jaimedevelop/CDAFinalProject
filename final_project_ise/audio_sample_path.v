`timescale 1ns / 1ps

// Project-owned audio sample path.
// This sits between audio_codec.v and the future recorder/playback FSM logic.
// It keeps the codec-side timing contract intact while removing the dependency
// on the demo-specific audio_effects block.

module audio_sample_path (
    input         clk,
    input         reset,
    input         sample_end,
    input         sample_req,
    input  [15:0] audio_input,
    input         playback_enable,
    input         monitor_enable,
    input         test_tone_enable,
    input  [15:0] playback_sample,
    input  [3:0]  volume_setting,
    output [15:0] audio_output,
    output reg [15:0] recorder_sample,
    output reg        recorder_sample_valid,
    output reg        recorder_sample_toggle,
    output reg        playback_request_toggle
);

reg [15:0] output_sample;
reg [15:0] tone_rom [0:99];
reg [6:0]  tone_index;

assign audio_output = output_sample;

initial begin
    tone_rom[0] = 16'h0000;
    tone_rom[1] = 16'h0805;
    tone_rom[2] = 16'h1002;
    tone_rom[3] = 16'h17ee;
    tone_rom[4] = 16'h1fc3;
    tone_rom[5] = 16'h2777;
    tone_rom[6] = 16'h2f04;
    tone_rom[7] = 16'h3662;
    tone_rom[8] = 16'h3d89;
    tone_rom[9] = 16'h4472;
    tone_rom[10] = 16'h4b16;
    tone_rom[11] = 16'h516f;
    tone_rom[12] = 16'h5776;
    tone_rom[13] = 16'h5d25;
    tone_rom[14] = 16'h6276;
    tone_rom[15] = 16'h6764;
    tone_rom[16] = 16'h6bea;
    tone_rom[17] = 16'h7004;
    tone_rom[18] = 16'h73ad;
    tone_rom[19] = 16'h76e1;
    tone_rom[20] = 16'h799e;
    tone_rom[21] = 16'h7be1;
    tone_rom[22] = 16'h7da7;
    tone_rom[23] = 16'h7eef;
    tone_rom[24] = 16'h7fb7;
    tone_rom[25] = 16'h7fff;
    tone_rom[26] = 16'h7fc6;
    tone_rom[27] = 16'h7f0c;
    tone_rom[28] = 16'h7dd3;
    tone_rom[29] = 16'h7c1b;
    tone_rom[30] = 16'h79e6;
    tone_rom[31] = 16'h7737;
    tone_rom[32] = 16'h7410;
    tone_rom[33] = 16'h7074;
    tone_rom[34] = 16'h6c67;
    tone_rom[35] = 16'h67ed;
    tone_rom[36] = 16'h630a;
    tone_rom[37] = 16'h5dc4;
    tone_rom[38] = 16'h5820;
    tone_rom[39] = 16'h5222;
    tone_rom[40] = 16'h4bd3;
    tone_rom[41] = 16'h4537;
    tone_rom[42] = 16'h3e55;
    tone_rom[43] = 16'h3735;
    tone_rom[44] = 16'h2fdd;
    tone_rom[45] = 16'h2855;
    tone_rom[46] = 16'h20a5;
    tone_rom[47] = 16'h18d3;
    tone_rom[48] = 16'h10e9;
    tone_rom[49] = 16'h08ee;
    tone_rom[50] = 16'h00e9;
    tone_rom[51] = 16'hf8e4;
    tone_rom[52] = 16'hf0e6;
    tone_rom[53] = 16'he8f7;
    tone_rom[54] = 16'he120;
    tone_rom[55] = 16'hd967;
    tone_rom[56] = 16'hd1d5;
    tone_rom[57] = 16'hca72;
    tone_rom[58] = 16'hc344;
    tone_rom[59] = 16'hbc54;
    tone_rom[60] = 16'hb5a7;
    tone_rom[61] = 16'haf46;
    tone_rom[62] = 16'ha935;
    tone_rom[63] = 16'ha37c;
    tone_rom[64] = 16'h9e20;
    tone_rom[65] = 16'h9926;
    tone_rom[66] = 16'h9494;
    tone_rom[67] = 16'h906e;
    tone_rom[68] = 16'h8cb8;
    tone_rom[69] = 16'h8976;
    tone_rom[70] = 16'h86ab;
    tone_rom[71] = 16'h845a;
    tone_rom[72] = 16'h8286;
    tone_rom[73] = 16'h8130;
    tone_rom[74] = 16'h8059;
    tone_rom[75] = 16'h8003;
    tone_rom[76] = 16'h802d;
    tone_rom[77] = 16'h80d8;
    tone_rom[78] = 16'h8203;
    tone_rom[79] = 16'h83ad;
    tone_rom[80] = 16'h85d3;
    tone_rom[81] = 16'h8875;
    tone_rom[82] = 16'h8b8f;
    tone_rom[83] = 16'h8f1d;
    tone_rom[84] = 16'h931e;
    tone_rom[85] = 16'h978c;
    tone_rom[86] = 16'h9c63;
    tone_rom[87] = 16'ha19e;
    tone_rom[88] = 16'ha738;
    tone_rom[89] = 16'had2b;
    tone_rom[90] = 16'hb372;
    tone_rom[91] = 16'hba05;
    tone_rom[92] = 16'hc0df;
    tone_rom[93] = 16'hc7f9;
    tone_rom[94] = 16'hcf4b;
    tone_rom[95] = 16'hd6ce;
    tone_rom[96] = 16'hde7a;
    tone_rom[97] = 16'he648;
    tone_rom[98] = 16'hee30;
    tone_rom[99] = 16'hf629;
end

function [15:0] apply_volume;
    input [15:0] sample_value;
    input [3:0]  level;
    reg signed [15:0] signed_sample;
    reg signed [20:0] scaled_sample;
    reg [4:0]         gain_step;
    begin
        signed_sample = sample_value;
        // 4-bit volume policy:
        //   0  -> mute
        //   1  -> 2/16 scale
        //   ...
        //   14 -> 15/16 scale
        //   15 -> full scale
        if (level == 4'd0) begin
            apply_volume = 16'sd0;
        end else if (level == 4'd15) begin
            apply_volume = sample_value;
        end else begin
            gain_step = {1'b0, level} + 5'd1;
            scaled_sample = signed_sample * $signed({1'b0, gain_step});
            apply_volume = scaled_sample >>> 4;
        end
    end
endfunction

always @(posedge clk) begin
    if (reset) begin
        recorder_sample       <= 16'd0;
        recorder_sample_valid <= 1'b0;
        recorder_sample_toggle <= 1'b0;
        playback_request_toggle <= 1'b0;
        output_sample         <= 16'd0;
        tone_index            <= 7'd0;
    end else begin
        recorder_sample_valid <= 1'b0;

        if (sample_end) begin
            recorder_sample       <= audio_input;
            recorder_sample_valid <= 1'b1;
            recorder_sample_toggle <= ~recorder_sample_toggle;
        end

        if (sample_req) begin
            playback_request_toggle <= ~playback_request_toggle;
            if (test_tone_enable) begin
                output_sample <= apply_volume(tone_rom[tone_index], volume_setting);
                if (tone_index == 7'd99)
                    tone_index <= 7'd0;
                else
                    tone_index <= tone_index + 1'b1;
            end else if (playback_enable)
                output_sample <= apply_volume(playback_sample, volume_setting);
            else if (monitor_enable)
                output_sample <= recorder_sample;
            else
                output_sample <= 16'd0;
        end
    end
end

endmodule
