`timescale 1ns / 1ps

module tb_audio_sample_path_volume;

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

    integer error_count;
    reg [15:0] captured_tone_low;
    reg [15:0] captured_tone_high;
    reg [15:0] captured_tone_full;

    audio_sample_path dut (
        .clk(clk),
        .reset(reset),
        .sample_end(sample_end),
        .sample_req(sample_req),
        .audio_input(audio_input),
        .playback_enable(playback_enable),
        .monitor_enable(monitor_enable),
        .test_tone_enable(test_tone_enable),
        .playback_sample(playback_sample),
        .volume_setting(volume_setting),
        .audio_output(audio_output),
        .recorder_sample(recorder_sample),
        .recorder_sample_valid(recorder_sample_valid),
        .recorder_sample_toggle(recorder_sample_toggle),
        .playback_request_toggle(playback_request_toggle)
    );

    always #5 clk = ~clk;

    task tick;
        input integer cycle_count;
        integer idx;
        begin
            for (idx = 0; idx < cycle_count; idx = idx + 1)
                @(posedge clk);
        end
    endtask

    task pulse_sample_end_with_input;
        input [15:0] sample_value;
        reg previous_toggle;
        begin
            previous_toggle = recorder_sample_toggle;
            audio_input = sample_value;
            sample_end = 1'b1;
            @(posedge clk);
            sample_end = 1'b0;
            @(posedge clk);

            if (recorder_sample !== sample_value) begin
                $display("ERROR: recorder_sample expected 0x%0h, got 0x%0h", sample_value, recorder_sample);
                error_count = error_count + 1;
            end
            if (recorder_sample_valid !== 1'b1) begin
                $display("ERROR: recorder_sample_valid did not assert after sample_end");
                error_count = error_count + 1;
            end
            if (recorder_sample_toggle === previous_toggle) begin
                $display("ERROR: recorder_sample_toggle did not change after sample_end");
                error_count = error_count + 1;
            end
        end
    endtask

    task pulse_sample_req_and_check_toggle;
        reg previous_toggle;
        begin
            previous_toggle = playback_request_toggle;
            sample_req = 1'b1;
            @(posedge clk);
            sample_req = 1'b0;
            @(posedge clk);

            if (playback_request_toggle === previous_toggle) begin
                $display("ERROR: playback_request_toggle did not change after sample_req");
                error_count = error_count + 1;
            end
        end
    endtask

    task check_equal_1bit;
        input actual_value;
        input expected_value;
        input [255:0] check_name;
        begin
            if (actual_value !== expected_value) begin
                $display("ERROR: %0s expected %0d, got %0d", check_name, expected_value, actual_value);
                error_count = error_count + 1;
            end
        end
    endtask

    task check_equal_16bit;
        input [15:0] actual_value;
        input [15:0] expected_value;
        input [255:0] check_name;
        begin
            if (actual_value !== expected_value) begin
                $display("ERROR: %0s expected 0x%0h, got 0x%0h", check_name, expected_value, actual_value);
                error_count = error_count + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        sample_end = 1'b0;
        sample_req = 1'b0;
        audio_input = 16'h0000;
        playback_enable = 1'b0;
        monitor_enable = 1'b0;
        test_tone_enable = 1'b0;
        playback_sample = 16'h0000;
        volume_setting = 4'h0;
        error_count = 0;
        captured_tone_low = 16'h0000;
        captured_tone_high = 16'h0000;
        captured_tone_full = 16'h0000;

        tick(4);
        reset = 1'b0;
        tick(2);

        // Reset sanity
        check_equal_16bit(audio_output, 16'h0000, "reset audio_output");
        check_equal_16bit(recorder_sample, 16'h0000, "reset recorder_sample");
        check_equal_1bit(recorder_sample_valid, 1'b0, "reset recorder_sample_valid");

        // Recorder-side sample capture and toggle generation
        pulse_sample_end_with_input(16'h3456);

        // Playback volume behavior using a fixed playback sample
        playback_enable = 1'b1;
        playback_sample = 16'h4000;

        volume_setting = 4'h0;
        pulse_sample_req_and_check_toggle;
        check_equal_16bit(audio_output, 16'h0000, "volume 0 mute");

        volume_setting = 4'h1;
        pulse_sample_req_and_check_toggle;
        check_equal_16bit(audio_output, 16'h0800, "volume 1 scaled output");

        volume_setting = 4'h7;
        pulse_sample_req_and_check_toggle;
        check_equal_16bit(audio_output, 16'h2000, "volume 7 scaled output");

        volume_setting = 4'hE;
        pulse_sample_req_and_check_toggle;
        check_equal_16bit(audio_output, 16'h3C00, "volume 14 scaled output");

        volume_setting = 4'hF;
        pulse_sample_req_and_check_toggle;
        check_equal_16bit(audio_output, 16'h4000, "volume 15 full scale");

        // Monitor path behavior
        playback_enable = 1'b0;
        monitor_enable = 1'b1;
        pulse_sample_end_with_input(16'h2A2A);
        pulse_sample_req_and_check_toggle;
        check_equal_16bit(audio_output, 16'h2A2A, "monitor path output");

        // Tone path behavior and priority over playback/monitor
        playback_enable = 1'b1;
        monitor_enable = 1'b1;
        test_tone_enable = 1'b1;

        // The sine ROM intentionally starts at 0, so consume one request
        // before checking amplitude scaling across volume levels.
        volume_setting = 4'h1;
        pulse_sample_req_and_check_toggle;

        volume_setting = 4'h1;
        pulse_sample_req_and_check_toggle;
        captured_tone_low = audio_output;

        volume_setting = 4'h7;
        pulse_sample_req_and_check_toggle;
        captured_tone_high = audio_output;

        volume_setting = 4'hF;
        pulse_sample_req_and_check_toggle;
        captured_tone_full = audio_output;

        if (captured_tone_low == 16'h0000) begin
            $display("ERROR: tone output at low volume should not be zero");
            error_count = error_count + 1;
        end
        if (captured_tone_high <= captured_tone_low) begin
            $display("ERROR: tone output did not increase between low and medium volume");
            error_count = error_count + 1;
        end
        if (captured_tone_full <= captured_tone_high) begin
            $display("ERROR: tone output did not increase between medium and full volume");
            error_count = error_count + 1;
        end

        // Silence path when no source is enabled
        playback_enable = 1'b0;
        monitor_enable = 1'b0;
        test_tone_enable = 1'b0;
        pulse_sample_req_and_check_toggle;
        check_equal_16bit(audio_output, 16'h0000, "silence path");

        if (error_count == 0) begin
            $display("PASS: tb_audio_sample_path_volume completed without errors.");
        end else begin
            $display("FAIL: tb_audio_sample_path_volume completed with %0d error(s).", error_count);
        end

        $finish;
    end

endmodule
