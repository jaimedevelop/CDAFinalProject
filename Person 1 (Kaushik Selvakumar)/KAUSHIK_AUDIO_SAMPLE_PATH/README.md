# KAUSHIK AUDIO SAMPLE PATH

This folder is Kaushik's cleaned Person 1 audio-code package for the final report/submission organization.

The files here are copied from the team project folder `final_project_ise` and renamed with uppercase basenames so Kaushik's audio files are easy to identify in the report:

```text
SRC/AUDIO_SAMPLE_PATH.v
SRC/AUDIO_EFFECTS.v
SRC/AUDIO_CODEC.v
SRC/I2C_AV_CONFIG.v
SRC/I2C_CONTROLLER.v
SIM/TB_AUDIO_SAMPLE_PATH_VOLUME.v
```

## Important Build Note

The actual Xilinx ISE project currently references the original lowercase filenames in `final_project_ise`:

```text
audio_sample_path.v
audio_effects.v
audio_codec.v
i2c_av_config.v
i2c_controller.v
tb_audio_sample_path_volume.v
```

For the safest final build, keep using the lowercase originals inside `final_project_ise` unless the whole team updates the `.xise` project file and every source/testbench reference together. This folder is for clean organization and report submission, not for replacing the working ISE project paths at the last minute.

## File Responsibilities

- `AUDIO_SAMPLE_PATH.v` is the project-specific audio bridge. It captures microphone samples on codec timing, sends recorder-valid/toggle signals to storage, requests playback samples, applies volume scaling, and selects playback, monitor, test-tone, or silence output.
- `AUDIO_CODEC.v` handles the serial audio interface to the SSM2603 codec.
- `I2C_AV_CONFIG.v` sends the codec initialization register sequence.
- `I2C_CONTROLLER.v` performs the lower-level I2C transaction timing.
- `AUDIO_EFFECTS.v` is retained from the audio demo/reference path.
- `TB_AUDIO_SAMPLE_PATH_VOLUME.v` is the simulation testbench for the sample path and volume behavior.

## Refactor Notes

These files were refactored for readability and safer verification without changing module names or top-level ports:

- Added named constants for codec timing, I2C states, tone indexing, and volume levels.
- Fixed the testbench pulse timing so checks happen immediately after the active clock edge.
- Removed a duplicate reset assignment in `AUDIO_CODEC.v`.
- Added explicit timescale declarations to the audio/I2C source files.
- Kept the same external module names so `sound_system_top.v` and teammates' code still connect normally.
