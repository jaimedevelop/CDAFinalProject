# Person 1 - Kaushik Selvakumar

Audio Codec & Hardware Integration for the CDA 4203/4203L final project.

## Folder Structure

- `src/` - Verilog/VHDL source files to add to the Xilinx ISE project.
- `constraints/` - UCF constraints for standalone audio testing and final integration.
- `docs/` - Person 1 answers and notes for Claudio/Person 4.
- `sim/` - Windows/Icarus Verilog syntax-check support only.
- `canvas_reference/audio_codec_demo/` - relevant original Canvas audio demo files used as reference.

## Use In Final Integration

Person 4 should instantiate `src/audio_frontend.v` as the audio wrapper.

Add these files to the final ISE hardware project:

- `src/audio_frontend.v`
- `src/audio_codec.v`
- `src/i2c_av_config.v`
- `src/i2c_controller.v`
- `src/clk_wiz_v3_6.vhd`

Merge `constraints/audio_frontend_pins.ucf` into the final system UCF.

Do not add `sim/sim_clk_wiz_v3_6_stub.v` to the ISE hardware project. It exists only so Icarus Verilog can syntax-check the Verilog files on Windows without compiling the Xilinx VHDL clock wizard.

## Audio Interface

Recording:

- `record_sample_16[15:0]` is the microphone sample.
- `record_sample_8[7:0]` is `record_sample_16[15:8]` for Joaquin's current 8-bit memory controller.
- Capture/store on `sample_end`.

Playback:

- Drive `playback_sample_16[15:0]` if storing 16-bit audio.
- Drive `playback_sample_8[7:0]` and set `playback_use_8bit = 1'b1` if using the current 8-bit memory controller.
- Provide the next playback sample when `sample_req` pulses.

Controls:

- `passthrough_enable = 1'b1` loops microphone audio directly to speaker for hardware testing.
- `mute_output = 1'b1` forces speaker output to zero.
- `codec_ready` goes high after the audio PLL locks and the I2C codec configuration reaches the final table entry.

## Lab 6 Connection

Lab 6 is related to the final project mainly through picoBlaze, UART, and the PuTTY serial terminal workflow. Those files are most directly useful for Person 3's command menu. Person 1 does not need to reuse the Lab 6 UART files directly, but this audio wrapper is designed so the Lab 6-style picoBlaze UI can drive commands through the final top module.

## Standalone Audio Test

For an isolated hardware test before full system integration:

1. In Xilinx ISE, set `audio_passthrough_top` as the top module.
2. Add the `src/` source files.
3. Use `constraints/audio_passthrough_top.ucf`.
4. Generate a bitstream.
5. Plug microphone into the pink audio port and speaker/headphones into the green audio port.
6. Use `SW0 = 1` for mic passthrough and `SW1 = 0` for unmuted output.

LEDs:

- `LED0` - `codec_ready`
- `LED1` - `sample_end` pulse
- `LED2` - `sample_req` pulse
- `LED3` - `pll_locked`

## Windows Syntax Check

From this folder:

```powershell
& "C:\iverilog\bin\iverilog.exe" -g2012 -Wall -s audio_passthrough_top -o audio_check.vvp src\audio_passthrough_top.v src\audio_frontend.v src\audio_codec.v src\i2c_av_config.v src\i2c_controller.v sim\sim_clk_wiz_v3_6_stub.v
```

This checks Verilog syntax/elaboration only. Xilinx ISE must still use the real `src/clk_wiz_v3_6.vhd` file for hardware.
