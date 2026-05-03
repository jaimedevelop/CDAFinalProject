# Board Test Package

This folder is for board-facing notes and proposed updates only. It does not replace Felipe's existing files.

## Board / Tool Target

From the project and Lab 6 files, the expected setup is:

- Board: Digilent Anvyl FPGA board
- FPGA part: `xc6slx45-3-csg484`
- Toolchain: Xilinx ISE 14.7
- FPGA oscillator clock: 100 MHz
- Serial terminal: PuTTY or similar
- UART settings: `9600`, `8-N-1`, flow control `None`

Known Lab 6 serial pins:

- `rs232_tx`: `T20`
- `rs232_rx`: `T19`
- `clk`: `D11`
- active-low `reset`: `E6`

## What Is Needed for Actual Board Testing

For a quick board/PuTTY test, the minimum file is:

- `loopback.bit`

That bitstream can be programmed onto the Anvyl board through iMPACT/ISE. PuTTY must be opened on the board's USB Serial COM port.

For a reliable rebuild, the team needs all source files that created the bitstream:

- `final_project_complete.psm`
- generated PicoBlaze ROM Verilog, usually `final_project_complete.v`
- `loopback.v`
- `picoblaze.v`
- `kcpsm6.v`
- `rs232_uart.v`
- `uart_tx6.v`
- `uart_rx6.v`
- `led_driver.v`
- `loopback.ucf`
- the `.xise` project file with repo-relative paths

## Current Problem With Felipe's Uploaded Build

Felipe's `loopback.bit` may be programmable, but the uploaded ISE project is not cleanly rebuildable from GitHub because `loopback.prj` points to:

```text
../Downloads/verilog/uart_tx6.v
../Downloads/verilog/uart_rx6.v
../Downloads/verilog/kcpsm6.v
../Downloads/picoblaze/final_project_complete.v
../Downloads/verilog/led_driver.v
../Downloads/rs232_uart.v
../Downloads/picoblaze.v
../Downloads/loopback.v
```

Those files are not all committed in Felipe's folder. The generated Verilog ROM file `final_project_complete.v` is also not committed.

## What I Updated

I did not modify Felipe's existing board files. I only added separate support files under `updated files`.

This package adds:

- `README.md`: this checklist
- `proposed_loopback_with_timing.ucf`: a proposed UCF improvement for the standalone Lab 6-style UI test

## What Should Be Updated Before Final Board Test

Do not overwrite Felipe's originals blindly. Make a copied ISE project or branch first, then:

1. Regenerate `final_project_complete.v` from `final_project_complete.psm`.
2. Commit the generated `final_project_complete.v`.
3. Replace `../Downloads/...` project paths with repo-relative paths.
4. Add the 100 MHz clock timing constraint shown in `proposed_loopback_with_timing.ucf`.
5. Rebuild the bitstream in ISE.
6. Program the board.
7. Open PuTTY with `9600`, `8-N-1`, flow control `None`.
8. Press the board reset after PuTTY is open.

If the terminal still corrupts text after a clean rebuild, the issue is likely physical setup: wrong COM port, PuTTY flow control, USB serial driver, wrong cable/port, or board reset/clock behavior.
