# Rebuild Source Package

This folder is a clean, self-contained source package for rebuilding Felipe's PicoBlaze UART UI test for the Anvyl board.

It is intentionally separate from Felipe's original files. Nothing in the original folder was overwritten.

## What This Package Contains

- `picoblaze/final_project_complete.psm`
- `picoblaze/assembler.exe`
- `verilog/kcpsm6.v`
- `verilog/uart_tx6.v`
- `verilog/uart_rx6.v`
- `verilog/rs232_uart.v`
- `verilog/led_driver.v`
- `verilog/picoblaze_final_project.v`
- `verilog/loopback_ui_board_test.v`
- `verilog/loopback_ui_integration.v`
- `loopback_ui_board_test.ucf`
- `loopback_ui_board_test.prj`
- `loopback_ui_board_test.xst`

## One Missing Generated File

The build still needs:

```text
picoblaze/final_project_complete.v
```

That file is generated from:

```text
picoblaze/final_project_complete.psm
```

I tried to run the old KCPSM6 `assembler.exe` from this Windows environment, but it did not successfully emit the generated Verilog ROM here. Generate it using the same PicoBlaze assembler flow used in Lab 6, then place the generated file at:

```text
Person 3 (Felipe Vignatti)/updated files/rebuild source/picoblaze/final_project_complete.v
```

## Board-Test Top Module

Use this file for standalone PuTTY/menu testing on the Anvyl board:

```text
verilog/loopback_ui_board_test.v
```

It keeps Felipe's command/status ports internal so ISE does not assign random unlocated FPGA pins. This is the correct standalone board test for "does the menu print cleanly in PuTTY?"

Top module name:

```text
loopback
```

## Integration Top Module

Use this only when Claudio integrates UI with the full final project:

```text
verilog/loopback_ui_integration.v
```

It exposes:

```text
command_out[7:0]
msg_num_out[7:0]
status_in[7:0]
```

Do not use this as the standalone board test top unless those ports are connected by a higher-level top module.

## Proper ISE GUI Rebuild Steps

1. Generate `picoblaze/final_project_complete.v` from `picoblaze/final_project_complete.psm`.
2. Open Xilinx ISE 14.7.
3. Create a new ISE project or copy Felipe's old one.
4. Set the device to:

```text
Family: Spartan6
Device: xc6slx45
Package: csg484
Speed: -3
Preferred language: Verilog
```

5. Add these source files:

```text
verilog/uart_tx6.v
verilog/uart_rx6.v
verilog/kcpsm6.v
picoblaze/final_project_complete.v
verilog/rs232_uart.v
verilog/picoblaze_final_project.v
verilog/led_driver.v
verilog/loopback_ui_board_test.v
loopback_ui_board_test.ucf
```

6. Set top module to:

```text
loopback
```

7. Run:

```text
Synthesize
Implement Design
Generate Programming File
```

8. Program the board with the generated `.bit` file.
9. Open PuTTY:

```text
Speed: 9600
Data bits: 8
Stop bits: 1
Parity: None
Flow control: None
```

10. Press the board reset after PuTTY is open.

## What Was Fixed Versus Felipe's Current Project

Felipe's uploaded `loopback.prj` points to `../Downloads/...`, so it is not reproducible from GitHub. This rebuild package uses local paths only.

The UCF also adds the missing 100 MHz timing constraint for `clk`.
