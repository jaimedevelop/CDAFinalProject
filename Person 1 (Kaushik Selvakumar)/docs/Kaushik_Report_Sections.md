# Kaushik Report Sections

Use these sections to fill the red Kaushik placeholders in the final report.

## Work Distribution

Kaushik: Worked on the audio codec and hardware audio path integration. Responsible for the SSM2603 audio CODEC interface files and the digital sample path between the microphone input, memory playback path, and speaker output. Files: `AUDIO_CODEC.v`, `I2C_AV_CONFIG.v`, and `I2C_CONTROLLER.v` provide the serial audio interface and I2C configuration sequence for the codec. `AUDIO_SAMPLE_PATH.v` captures incoming microphone samples, produces recorder-valid/toggle signals for the storage layer, requests playback samples on codec timing, applies volume scaling, supports monitor/playback/test-tone modes, and drives the DAC sample output. `AUDIO_EFFECTS.v` was kept from the audio demo as a reference/demo audio effects block. `TB_AUDIO_SAMPLE_PATH_VOLUME.v` was created to exercise sample capture, playback request toggling, volume levels, monitor mode, and test-tone behavior.

## Total Person Hours

Kaushik: approximately 40-45 hours

## Issues You Ran Into

- Kaushik: Integrating the audio demo code into the final recorder design required separating the original demo-specific `AUDIO_EFFECTS.v` behavior from the project-owned sample path. The original codec side had strict timing signals (`sample_end` and `sample_req`) that had to remain compatible with the SSM2603 serial audio interface while also producing cleaner record/playback handshake signals for the memory controller.
- Kaushik: The audio system used multiple clock domains and inherited clock-wizard/IP assumptions from the provided Canvas demo. The project needed the board/RAM 100 MHz side, the 37.5 MHz RAM-related clock path, and the codec/audio clock path to be kept conceptually separate so audio samples were not treated like ordinary always-available data.
- Kaushik: The sample path had to support several operating modes: recording microphone input, live monitor passthrough, memory-backed playback, muted output, and a test tone. Avoiding conflicts between those modes required defining clear priority in `AUDIO_SAMPLE_PATH.v`, with test tone first, then playback, then monitor, then silence.
- Kaushik: Volume control had to be implemented in a simple synthesizable way using fixed-point scaling instead of software-style arithmetic. The 4-bit volume setting was mapped to mute, fractional gain steps, and full-scale output.
- Kaushik: Full board-level verification was limited because audio, RAM, picoBlaze, and top-level integration all had to come together before the complete recorder could be tested end-to-end on the Anvyl board.

## Overview Paragraph

Kaushik (Audio Codec and Hardware Integration): The audio portion of the project interfaces the Anvyl board with the SSM2603 audio codec and provides the digital sample path used by the recorder. The codec configuration logic sends the required register initialization sequence over I2C using `I2C_AV_CONFIG.v` and `I2C_CONTROLLER.v`, while `AUDIO_CODEC.v` handles the serial-to-parallel and parallel-to-serial audio transfer for microphone input and speaker output. The project-owned `AUDIO_SAMPLE_PATH.v` sits behind the codec interface and converts codec timing pulses into recorder/playback handshakes. When `sample_end` occurs, the current microphone sample is captured and marked valid for storage. When `sample_req` occurs, the module requests or selects the next speaker sample from playback memory, live monitor mode, test-tone mode, or silence. It also applies the user-selected volume level before the sample is sent to the DAC.

## Codes Section

Kaushik:

```text
AUDIO_SAMPLE_PATH.v
AUDIO_EFFECTS.v
AUDIO_CODEC.v
I2C_AV_CONFIG.v
I2C_CONTROLLER.v
TB_AUDIO_SAMPLE_PATH_VOLUME.v
```

## Discussion and Conclusions

Kaushik: The main audio design decision was to avoid leaving the project dependent on the original demo-only `AUDIO_EFFECTS.v` block. That demo block was useful as a reference because it already showed how the codec sample timing worked, but the final recorder needed a cleaner path that could talk to the RAM and playback controller. For that reason, `AUDIO_SAMPLE_PATH.v` was used as the project-specific audio bridge. It preserves the codec timing contract while producing explicit recorder sample-valid and playback-request toggle signals for the rest of the system. Another important decision was to keep volume scaling simple and synthesizable with fixed-point arithmetic rather than trying to implement a complex audio-processing pipeline. If the project were continued, the next improvements would be stronger cross-clock-domain synchronization between the audio and RAM sections, more hardware-level audio tests on the Anvyl board, and a cleaner final top-level integration pass once all teammates' modules are stable.

## File Rename Recommendation

For the report package, Kaushik's copied files were renamed with uppercase basenames inside `Person 1 (Kaushik Selvakumar)/KAUSHIK_AUDIO_SAMPLE_PATH`. The live ISE project still keeps the lowercase originals in `final_project_ise`, because the `.xise` project file references those exact filenames.
