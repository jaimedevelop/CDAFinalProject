# Kaushik Audio Block Diagram Caption

Kaushik: This diagram shows the Person 1 audio subsystem. The SSM2603 audio codec is configured through `I2C_AV_CONFIG.v`/`I2C_CONTROLLER.v`, while `AUDIO_CODEC.v` converts the codec serial audio pins into 16-bit parallel ADC/DAC samples. `AUDIO_SAMPLE_PATH.v` receives the codec timing pulses, captures microphone samples for recording, requests playback samples, applies volume scaling, and selects playback, monitor, test-tone, or silence output before sending the sample back to the DAC.

