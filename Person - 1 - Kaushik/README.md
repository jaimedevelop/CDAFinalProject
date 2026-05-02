# Person 1 - Audio Codec & Hardware Integration

This folder contains Kaushik's Person 1 audio interface work for the CDA 4203/4203L final project.

## Files

- `audio_frontend.v` - clean integration wrapper for the SSM2603 audio codec.
- `audio_passthrough_top.v` - standalone board-test top for Person 1 only.
- `audio_codec.v` - original Canvas demo serial/parallel codec module.
- `i2c_av_config.v` - original Canvas demo codec configuration module.
- `i2c_controller.v` - original Canvas demo I2C bit controller.
- `clk_wiz_v3_6.vhd` - original Canvas demo clock wizard for codec clocks.
- `sim_clk_wiz_v3_6_stub.v` - simulation/syntax-check stub only; do not add this to the ISE hardware project.
- `audio_frontend_pins.ucf` - audio pin constraints to merge into the final UCF.
- `audio_passthrough_top.ucf` - standalone constraints for testing only.

## Integration Ports For Person 4

Use `audio_frontend` as the audio wrapper. Feed `clk_100mhz` from the final system 100 MHz clock. In the assignment clock plan, the board 100 MHz clock goes into the RAM interface, RAM outputs 37.5 MHz, and a separate top-level clock wizard generates 100 MHz clocks for audio and picoBlaze. This module still keeps the original codec PLL inside it because the SSM2603 needs 50 MHz logic and 11.2896 MHz audio clocks.

Recording:

- `record_sample_16[15:0]` is the microphone sample.
- `record_sample_8[7:0]` is `record_sample_16[15:8]` for the current 8-bit memory controller.
- Capture/store on `sample_end`.

Playback:

- Drive `playback_sample_16[15:0]` if storing 16-bit audio.
- Drive `playback_sample_8[7:0]` and set `playback_use_8bit = 1'b1` if using Joaquin's current 8-bit memory controller.
- Provide the next playback sample when `sample_req` pulses.

Controls:

- `passthrough_enable = 1'b1` loops microphone audio directly to speaker for hardware testing.
- `mute_output = 1'b1` forces speaker output to zero.
- `codec_ready` goes high after the audio PLL locks and the I2C codec configuration reaches the final table entry.

## Direct Answers For Claudio

1. We are keeping the audio wrapper approach from `sockit_top.v`, but the integration-ready wrapper is now `audio_frontend.v`.
2. The microphone sample is `record_sample_16`; for the current 8-bit memory controller use `record_sample_8`.
3. The speaker/playback sample enters through `playback_sample_16` or `playback_sample_8`.
4. Yes, use the selected-channel timing pulses: `sample_end = sample_end[1]` and `sample_req = sample_req[1]`.

## Quick Hardware Test

Before full integration, set `audio_passthrough_top` as the ISE top module and use `audio_passthrough_top.ucf`.

Controls:

- `KEY0` resets the audio logic while pressed.
- `SW0 = 1` enables microphone passthrough.
- `SW1 = 1` mutes the speaker output.
- `LED0` is `codec_ready`.
- `LED3` is `pll_locked`.

Plug microphone into the pink audio port and speakers/headphones into the green audio port. If the codec is configured and clocks are correct, microphone audio should pass to the speaker.

## Windows Syntax Check

With Icarus Verilog installed:

```powershell
iverilog -g2012 -Wall -s audio_passthrough_top -o audio_check.vvp audio_passthrough_top.v audio_frontend.v audio_codec.v i2c_av_config.v i2c_controller.v sim_clk_wiz_v3_6_stub.v
```

This only checks Verilog syntax/elaboration. Xilinx ISE must still use the real `clk_wiz_v3_6.vhd` file for hardware.
