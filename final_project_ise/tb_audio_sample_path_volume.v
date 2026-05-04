`timescale 1ns / 1ps

// --------------------------------------------------------------------
// Testbench : tb_audio_sample_path_volume
// Author    : Kaushik
// DUT       : audio_sample_path
//
// Coverage:
//   1. Reset de-assertion -- all outputs idle
//   2. ADC capture path   -- recorder_sample, valid (level), toggle
//   3. Volume scaling     -- mute(0), partial(1,7,14), unity(15)
//   4. Source MUX         -- playback > monitor > silence priority
//   5. Test-tone path     -- amplitude increases with volume
//   6. Silence (no source selected)
//
// Restructured vs original:
//   - Tasks reorganised into named, single-purpose helpers
//   - Error tracking via a shared 'fail_count' integer
//   - Named-block labels on every always / initial
//   - check_16 / check_1 helpers use $sformat for richer messages
// --------------------------------------------------------------------

module tb_audio_sample_path_volume;

// ----------------------------------------------------------------
// DUT ports
// ----------------------------------------------------------------
reg         clk;
reg         reset;
reg         sample_end;
reg         sample_req;
reg  [15:0] audio_input;
reg         playback_enable;
reg         monitor_enable;
reg         test_tone_enable;
reg  [15:0] playback_sample;
reg  [3:0]  volume_setting;

wire [15:0] audio_output;
wire [15:0] recorder_sample;
wire        recorder_sample_valid;
wire        recorder_sample_toggle;
wire        playback_request_toggle;

// ----------------------------------------------------------------
// DUT instantiation
// ----------------------------------------------------------------
audio_sample_path dut (
    .clk                    (clk),
    .reset                  (reset),
    .sample_end             (sample_end),
    .sample_req             (sample_req),
    .audio_input            (audio_input),
    .playback_enable        (playback_enable),
    .monitor_enable         (monitor_enable),
    .test_tone_enable       (test_tone_enable),
    .playback_sample        (playback_sample),
    .volume_setting         (volume_setting),
    .audio_output           (audio_output),
    .recorder_sample        (recorder_sample),
    .recorder_sample_valid  (recorder_sample_valid),
    .recorder_sample_toggle (recorder_sample_toggle),
    .playback_request_toggle(playback_request_toggle)
);

// ----------------------------------------------------------------
// Clock: 100 MHz (10 ns period)
// ----------------------------------------------------------------
always #5 clk = ~clk;

// ----------------------------------------------------------------
// Shared error counter
// ----------------------------------------------------------------
integer fail_count;

// ----------------------------------------------------------------
// Helper: advance N rising edges
// ----------------------------------------------------------------
task advance_clocks;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1)
            @(posedge clk);
    end
endtask

// ----------------------------------------------------------------
// Helper: assert 16-bit equality
// ----------------------------------------------------------------
task check_16;
    input [15:0] got;
    input [15:0] expected;
    input [255:0] tag;
    begin
        if (got !== expected) begin
            $display("FAIL [%0s]: expected 0x%04h, got 0x%04h", tag, expected, got);
            fail_count = fail_count + 1;
        end
    end
endtask

// ----------------------------------------------------------------
// Helper: assert 1-bit equality
// ----------------------------------------------------------------
task check_1;
    input got;
    input expected;
    input [255:0] tag;
    begin
        if (got !== expected) begin
            $display("FAIL [%0s]: expected %0b, got %0b", tag, expected, got);
            fail_count = fail_count + 1;
        end
    end
endtask

// ----------------------------------------------------------------
// Helper: drive one sample_end pulse and verify ADC capture outputs
// ----------------------------------------------------------------
task drive_adc_sample;
    input [15:0] adc_word;
    reg          prev_toggle;
    begin
        prev_toggle = recorder_sample_toggle;
        audio_input = adc_word;
        sample_end  = 1'b1;
        @(posedge clk);
        sample_end = 1'b0;
        @(posedge clk);

        check_16(recorder_sample,       adc_word, "adc_sample_latch");
        check_1 (recorder_sample_valid, 1'b1,     "adc_valid_assert");
        if (recorder_sample_toggle === prev_toggle) begin
            $display("FAIL [adc_toggle]: did not change on sample_end");
            fail_count = fail_count + 1;
        end
    end
endtask

// ----------------------------------------------------------------
// Helper: drive one sample_req pulse and verify playback toggle fires
// ----------------------------------------------------------------
task drive_dac_req;
    reg prev_pb_toggle;
    begin
        prev_pb_toggle = playback_request_toggle;
        sample_req     = 1'b1;
        @(posedge clk);
        sample_req = 1'b0;
        @(posedge clk);

        if (playback_request_toggle === prev_pb_toggle) begin
            $display("FAIL [dac_toggle]: playback_request_toggle did not change");
            fail_count = fail_count + 1;
        end
    end
endtask

// ----------------------------------------------------------------
// Stimulus
// ----------------------------------------------------------------
initial begin : stimulus
    // Initialise all inputs
    clk              = 1'b0;
    reset            = 1'b1;
    sample_end       = 1'b0;
    sample_req       = 1'b0;
    audio_input      = 16'h0000;
    playback_enable  = 1'b0;
    monitor_enable   = 1'b0;
    test_tone_enable = 1'b0;
    playback_sample  = 16'h0000;
    volume_setting   = 4'h0;
    fail_count       = 0;

    advance_clocks(4);
    reset = 1'b0;
    advance_clocks(2);

    // ----------------------------------------------------------
    // Test 1: Reset state
    // ----------------------------------------------------------
    check_16(audio_output,          16'h0000, "rst_audio_out");
    check_16(recorder_sample,       16'h0000, "rst_rec_sample");
    check_1 (recorder_sample_valid, 1'b0,     "rst_valid");

    // ----------------------------------------------------------
    // Test 2: ADC capture and edge detection
    // ----------------------------------------------------------
    drive_adc_sample(16'h3456);

    // ----------------------------------------------------------
    // Test 3: Volume scaling over playback path
    // ----------------------------------------------------------
    playback_enable = 1'b1;
    playback_sample = 16'h4000;  // 0.5 of full scale

    // Mute
    volume_setting = 4'h0;
    drive_dac_req;
    check_16(audio_output, 16'h0000, "vol_0_mute");

    // vol=1 -> gain = 2/16 -> 0x4000 * 2 >> 4 = 0x0800
    volume_setting = 4'h1;
    drive_dac_req;
    check_16(audio_output, 16'h0800, "vol_1_scaled");

    // vol=7 -> gain = 8/16 = 0.5 -> 0x4000 * 8 >> 4 = 0x2000
    volume_setting = 4'h7;
    drive_dac_req;
    check_16(audio_output, 16'h2000, "vol_7_scaled");

    // vol=14 -> gain = 15/16 -> 0x4000 * 15 >> 4 = 0x3C00
    volume_setting = 4'hE;
    drive_dac_req;
    check_16(audio_output, 16'h3C00, "vol_14_scaled");

    // Unity
    volume_setting = 4'hF;
    drive_dac_req;
    check_16(audio_output, 16'h4000, "vol_15_unity");

    // ----------------------------------------------------------
    // Test 4: Monitor path (mic loopback)
    // ----------------------------------------------------------
    playback_enable = 1'b0;
    monitor_enable  = 1'b1;
    drive_adc_sample(16'h2A2A);
    drive_dac_req;
    check_16(audio_output, 16'h2A2A, "monitor_loopback");

    // ----------------------------------------------------------
    // Test 5: Tone path overrides playback+monitor; amplitude
    //         increases monotonically with volume
    // ----------------------------------------------------------
    playback_enable  = 1'b1;
    monitor_enable   = 1'b1;
    test_tone_enable = 1'b1;

    begin : tone_amplitude_check
        reg [15:0] out_low, out_mid, out_full;

        // First ROM entry is 0x0000; consume it silently
        volume_setting = 4'h1;
        drive_dac_req;

        // Capture three consecutive ROM outputs at escalating volumes
        volume_setting = 4'h1;
        drive_dac_req;
        out_low = audio_output;

        volume_setting = 4'h7;
        drive_dac_req;
        out_mid = audio_output;

        volume_setting = 4'hF;
        drive_dac_req;
        out_full = audio_output;

        if (out_low == 16'h0000) begin
            $display("FAIL [tone_low_nonzero]: low-volume tone should not be zero");
            fail_count = fail_count + 1;
        end
        if (out_mid <= out_low) begin
            $display("FAIL [tone_amp_rise_1]: mid amplitude <= low amplitude");
            fail_count = fail_count + 1;
        end
        if (out_full <= out_mid) begin
            $display("FAIL [tone_amp_rise_2]: full amplitude <= mid amplitude");
            fail_count = fail_count + 1;
        end
    end

    // ----------------------------------------------------------
    // Test 6: Silence when no source is selected
    // ----------------------------------------------------------
    playback_enable  = 1'b0;
    monitor_enable   = 1'b0;
    test_tone_enable = 1'b0;
    drive_dac_req;
    check_16(audio_output, 16'h0000, "silence_path");

    // ----------------------------------------------------------
    // Summary
    // ----------------------------------------------------------
    if (fail_count == 0)
        $display("PASS: tb_audio_sample_path_volume completed without errors.");
    else
        $display("FAIL: tb_audio_sample_path_volume completed with %0d error(s).", fail_count);

    $finish;
end

endmodule
