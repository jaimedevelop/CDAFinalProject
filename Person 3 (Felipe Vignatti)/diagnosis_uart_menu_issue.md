# UART/Menu Display Diagnosis

Issue observed: PuTTY starts printing the Audio Message Recorder menu, but the output cuts off around option 2. After pressing an Anvyl board button, the terminal shows corrupted characters.

## Main findings

1. The PicoBlaze source does include the full menu.
   - `final_project_complete.psm` prints `1) Play a message`, `2) Record a message`, `3) Delete a message`, `4) Delete all messages`, `5) Volume control`, and `Select [1-5]:`.
   - So the visible cut-off is probably not because the menu text is missing from the assembly file.

2. The uploaded ISE project is not self-contained.
   - `final_project.xise` and `loopback.prj` reference files from `../Downloads/...`.
   - The synthesis report confirms ISE built from `/home/ise/Downloads/...`, including:
     - `/home/ise/Downloads/picoblaze/final_project_complete.v`
     - `/home/ise/Downloads/loopback.v`
     - `/home/ise/Downloads/rs232_uart.v`
     - `/home/ise/Downloads/verilog/uart_tx6.v`
     - `/home/ise/Downloads/verilog/uart_rx6.v`
   - Because those Verilog sources are not in this GitHub folder, the current `loopback.bit` may not match the uploaded `.psm`, and another teammate cannot rebuild the same bitstream from the repo.

3. The UART design assumes a 100 MHz FPGA clock and 9600 baud.
   - `rs232_uart.v` from Lab 6 uses `MAX_BAUD_COUNT = 10'd651`, which is for a 100 MHz clock at 9600 baud with 16x oversampling.
   - If the top module is fed by a different clock, PuTTY will receive bad characters even if the assembly code is correct.
   - PuTTY should be configured as: 9600 baud, 8 data bits, 1 stop bit, no parity, flow control None.

4. The build has no user timing constraint for the clock.
   - `loopback.twr` says: `No timing constraints found`.
   - The build still placed/routed, but the project should include a clock TIMESPEC for the 100 MHz clock so timing is actually checked against the intended board clock.

5. Board button input handling is raw.
   - The PicoBlaze code reads `switches/buttons` directly on input port `00`.
   - It only uses a delay after a command; it does not properly synchronize/debounce the button inputs before detecting them.
   - A mechanical button press can bounce and trigger repeated pause/skip/stop actions.
   - If the button being pressed is the active-low reset on pin `E6`, the program will restart mid-output, which can look like the terminal is suddenly printing corrupted or partial text.

6. Final project command/status ports still need top-level verification.
   - The PicoBlaze code uses:
     - OUT port `06` = `command_out`
     - OUT port `07` = `msg_num_out`
     - IN port `08` = `status_in`
   - The uploaded repo does not include the actual `loopback.v` source used in synthesis, so these port routes cannot be reviewed directly.
   - The synthesis logs mention `command_out`, `msg_num_out`, and `status_in`, so Felipe may have modified `loopback.v`, but that modified source file needs to be committed.

## Most likely causes of the PuTTY corruption

1. PuTTY serial settings mismatch, especially baud or flow control.
2. UART baud clock mismatch because the FPGA clock is not the 100 MHz clock assumed by `rs232_uart.v`.
3. The programmed bitstream is stale or was built from a different generated `final_project_complete.v` than the uploaded `.psm`.
4. A physical button is resetting or bouncing the PicoBlaze while text is being transmitted.

## Immediate test checklist

1. In PuTTY, set:
   - Speed: `9600`
   - Data bits: `8`
   - Stop bits: `1`
   - Parity: `None`
   - Flow control: `None`

2. Re-test with the original Lab 6 `loopback.bit`.
   - If Lab 6 also prints corrupted output, the issue is likely PuTTY settings, serial cable/COM port, or clock/pin setup.
   - If Lab 6 prints cleanly, the issue is in the new final-project bitstream or PicoBlaze ROM build.

3. Reassemble `final_project_complete.psm` into `final_project_complete.v`.
   - Confirm ISE is using that exact regenerated Verilog file.
   - Rebuild `loopback.bit` after regenerating the PicoBlaze ROM.

4. Commit the actual Verilog sources used by ISE.
   - At minimum, commit the modified versions of:
     - `loopback.v`
     - `picoblaze.v`
     - `rs232_uart.v`
     - `uart_tx6.v`
     - `uart_rx6.v`
     - `kcpsm6.v`
     - generated `final_project_complete.v`
     - `loopback.ucf`
   - Update the ISE project paths so they are repo-relative, not `../Downloads/...`.

5. Add or verify the 100 MHz clock constraint in the UCF:

```ucf
NET "clk" LOC = "D11";
NET "clk" TNM_NET = "clk";
TIMESPEC "TS_clk" = PERIOD "clk" 10 ns HIGH 50%;
```

6. Avoid pressing the reset button while checking menu output.
   - Use PuTTY keyboard input first.
   - Add synchronized/debounced button logic before relying on physical buttons for pause/skip/stop.

## Suggested fix order

1. Make the repo rebuildable by committing the actual source files and generated PicoBlaze ROM.
2. Confirm PuTTY settings and original Lab 6 loopback behavior.
3. Rebuild the final project bitstream from the committed sources.
4. Add clock timing constraints.
5. Add synchronizer/debounce logic for physical board buttons.
