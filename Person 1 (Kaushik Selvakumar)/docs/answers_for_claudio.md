# Person 1 Audio Answers - Kaushik Selvakumar

## Lab 6 Connection

Lab 6 is related to the final project mainly through picoBlaze, UART, and the PuTTY serial-terminal workflow. The Lab 6 files in the shared VM folder include the `program.psm` assembly pattern, `kcpsm6.v`, UART modules, and loopback top-level design. Those are most directly useful for Person 3's serial menu and command handling.

For Person 1, I used the final-project audio codec demo instead of the Lab 6 UART files. The audio module exposes simple sample/control ports so the Lab 6-style picoBlaze UI can eventually control record, play, pause, delete, and volume through Person 4's top module.

## Answers For Claudio

1. Are you keeping `sockit_top.v` as the audio wrapper?

   Yes, I am keeping the same audio-wrapper architecture from the Canvas `sockit_top.v`, but I moved it into an integration-ready wrapper named `audio_frontend.v`.

2. What exact signal gives the microphone sample?

   `record_sample_16[15:0]` gives the microphone sample. For Joaquin's current 8-bit memory controller, use `record_sample_8[7:0]`, which is the upper byte of the 16-bit sample.

3. What exact signal receives the speaker/playback sample?

   `playback_sample_16[15:0]` receives the full playback sample. If we keep the current 8-bit memory controller, drive `playback_sample_8[7:0]` and set `playback_use_8bit = 1'b1`.

4. Are we using `sample_end[1]` and `sample_req[1]`?

   Yes. `audio_frontend.v` exposes these selected-channel signals as `sample_end` and `sample_req`. Store microphone data when `sample_end` pulses, and provide the next playback sample when `sample_req` pulses.

5. What files should Person 4 add to the final ISE project?

   Add these files from the `Person 1 (Kaushik Selvakumar)/src` folder:

   - `src/audio_frontend.v`
   - `src/audio_codec.v`
   - `src/i2c_av_config.v`
   - `src/i2c_controller.v`
   - `src/clk_wiz_v3_6.vhd`

   Merge the audio pin constraints from `constraints/audio_frontend_pins.ucf` into the final system UCF.

   Do not add `sim/sim_clk_wiz_v3_6_stub.v` to the ISE hardware project. It is only for Icarus Verilog syntax checks on Windows.
