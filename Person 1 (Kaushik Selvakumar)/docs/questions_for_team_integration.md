# Questions For Team Integration

Prepared by Kaushik Selvakumar, Person 1 Audio Codec & Hardware Integration.

## Current Person 1 Status

- Audio wrapper files are organized under `Person 1 (Kaushik Selvakumar)/src`.
- Standalone audio test top is `src/audio_passthrough_top.v`.
- Final integration wrapper is `src/audio_frontend.v`.
- Icarus Verilog syntax/elaboration check passes on Windows.
- Board-level validation in Xilinx ISE is still needed.

## Questions For Person 2 - Memory

1. Are we storing audio as 8-bit samples or 16-bit samples?
2. If 8-bit, should Person 1 continue using the upper byte `record_sample_8 = record_sample_16[15:8]`?
3. What exact playback signal should I connect to: `playback_sample_8` or `playback_sample_16`?
4. Do you want `sample_end` to trigger writes and `sample_req` to trigger reads?
5. Does your memory controller output a valid/playback-ready signal, or should the top module simply present data on each `sample_req`?
6. What clock domain will your memory controller use for audio sample handoff: RAM `sys_clk` at 37.5 MHz or the generated 100 MHz system clock?

## Questions For Person 4 - Top Module / Integration Lead

1. What is the final top module name?
2. Are you instantiating `Person 1 (Kaushik Selvakumar)/src/audio_frontend.v` directly?
3. Which 100 MHz clock should feed `audio_frontend.clk_100mhz`?
4. Are you generating the required 100 MHz audio/system clocks from RAM `clkout` as described in the project instructions?
5. Should Person 1's `codec_ready` gate record/playback operations?
6. How should reset be routed to audio: push-button reset, global reset, or controller reset?
7. Should `passthrough_enable` remain available for demo/debug, or should it be tied low in the final design?
8. Can you merge `constraints/audio_frontend_pins.ucf` into the final UCF and check for pin-name conflicts?

## Person 1 Proposed Defaults

- Use `audio_frontend.v` for final integration.
- Use `sample_end` to latch/store microphone samples.
- Use `sample_req` to request/present playback samples.
- Use 8-bit memory mode initially with `record_sample_8` and `playback_sample_8`, because the current memory controller appears to use 8-bit audio.
- Tie `passthrough_enable = 1'b0` in final system mode, but keep it available for standalone debug.
- Tie `mute_output = 1'b0` unless UI/top module controls mute.

## Remaining Person 1 Work

1. Run Xilinx ISE standalone test using `audio_passthrough_top`.
2. Confirm microphone-to-speaker passthrough on the Anvyl board.
3. Update the wrapper if the team chooses 16-bit storage.
