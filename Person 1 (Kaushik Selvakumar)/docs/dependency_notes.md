# Person 1 Dependency Notes

Person 1 can be developed and tested independently in microphone passthrough mode.

What is independent:

- Codec pin wiring and I2C configuration.
- Original codec clock wizard use.
- Microphone sample capture.
- Speaker sample output.
- Standalone mic-to-speaker passthrough test.

What depends on teammates:

- Person 2 must confirm whether final memory stores 8-bit or 16-bit samples.
- Person 4 must connect `audio_frontend` into the final top module and wire clocks according to the RAM/clock-wizard plan.

Current integration choice:

- `audio_frontend` supports both 16-bit and 8-bit playback paths.
- For Joaquin's current memory controller, use `record_sample_8`, `playback_sample_8`, and set `playback_use_8bit = 1'b1`.
- If the team upgrades memory to 16-bit audio, use `record_sample_16`, `playback_sample_16`, and set `playback_use_8bit = 1'b0`.

Potential follow-up:

- Only adjust the wrapper if Person 4 needs a different audio handoff signal during final integration.
