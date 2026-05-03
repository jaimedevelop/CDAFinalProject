# Felipe Rebuild Instructions

This folder is a clean rebuild package for Felipe's PicoBlaze / PuTTY UI test.

Nothing in Felipe's original files was overwritten. These files are separate so we can test a clean version without losing the current work.

## Why This Exists

The current uploaded ISE project points to files in `../Downloads/...`.

That means the uploaded `loopback.bit` may have been built from files that are not actually in GitHub. It also means another teammate cannot reliably rebuild the same bitstream from the repo.

This folder fixes that by collecting the needed source files in one place and using local paths.

## What Was Changed

The original Felipe files were not edited. The new logic is in this folder only.

Main added files:

```text
verilog/picoblaze_final_project.v
verilog/loopback_ui_board_test.v
verilog/loopback_ui_integration.v
loopback_ui_board_test.ucf
loopback_ui_board_test.prj
loopback_ui_board_test.xst
```

### `picoblaze_final_project.v`

This is based on the Lab 6 `picoblaze.v` wrapper.

The only important change is that it uses Felipe's generated ROM module:

```verilog
final_project_complete pblaze_rom (...)
```

instead of the Lab 6 ROM module:

```verilog
ROM_form pblaze_rom (...)
```

### `loopback_ui_board_test.v`

This is the file Felipe should use for a standalone Anvyl / PuTTY board test.

It is based on the Lab 6 `loopback.v`, but it also routes Felipe's UI ports:

```text
PicoBlaze OUT port 06 -> command_out
PicoBlaze OUT port 07 -> msg_num_out
PicoBlaze IN  port 08 -> status_in
```

For this standalone PuTTY test, `status_in` is tied to `8'h00` inside the module. That keeps the test simple and prevents ISE from creating random external FPGA pins for command/status signals.

Use this to answer:

```text
Does the menu print cleanly in PuTTY on the actual board?
```

### `loopback_ui_integration.v`

This is for Claudio / final top-level integration later.

It exposes these ports:

```text
command_out[7:0]
msg_num_out[7:0]
status_in[7:0]
```

Do not use this one for the standalone board/PuTTY test unless those ports are connected by another top module.

### `loopback_ui_board_test.ucf`

This uses the Lab 6 Anvyl pins and adds the missing 100 MHz clock timing constraint:

```ucf
NET "clk" TNM_NET = "clk";
TIMESPEC "TS_clk" = PERIOD "clk" 10 ns HIGH 50%;
```

## Important Missing Generated File

Before ISE can build the `.bit`, Felipe must regenerate the PicoBlaze ROM Verilog file:

```text
picoblaze/final_project_complete.v
```

Generate it from:

```text
picoblaze/final_project_complete.psm
```

This is the same kind of step used in Lab 6 when `program.psm` generated `program.v`.

Place the generated file here:

```text
Person 3 (Felipe Vignatti)/updated files/rebuild source/picoblaze/final_project_complete.v
```

## Xilinx ISE Steps

1. Open the VM.

2. Go to:

```text
SharedVMFolder/CDAFinalProject/Person 3 (Felipe Vignatti)/updated files/rebuild source
```

3. Run the PicoBlaze assembler on:

```text
picoblaze/final_project_complete.psm
```

4. Confirm this file now exists:

```text
picoblaze/final_project_complete.v
```

5. Open Xilinx ISE 14.7.

6. Create a new ISE project or copy Felipe's old one.

7. Use these project settings:

```text
Family: Spartan6
Device: xc6slx45
Package: csg484
Speed: -3
Preferred language: Verilog
Top module: loopback
```

8. Add these source files to ISE:

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

9. Make sure the top module is:

```text
loopback
```

10. Run these ISE steps:

```text
Synthesize
Implement Design
Generate Programming File
```

11. Use the generated `.bit` file to program the Anvyl board.

## PuTTY Steps

1. Plug in the board's USB serial cable.

2. In Windows Device Manager, find the USB Serial COM port.

3. Open PuTTY.

4. Use:

```text
Connection type: Serial
Serial line: COMx
Speed: 9600
Data bits: 8
Stop bits: 1
Parity: None
Flow control: None
```

5. Open the PuTTY terminal.

6. Press reset on the Anvyl board after PuTTY is open.

Expected output:

```text
================================
  AUDIO MESSAGE RECORDER v1.0
================================


MAIN MENU:
1) Play a message
2) Record a message
3) Delete a message
4) Delete all messages
5) Volume control

Select [1-5]:
```

## If It Still Shows Weird Characters

If this clean rebuild still prints corrupted text in PuTTY, the problem is probably not the menu assembly source.

Check these next:

```text
Wrong COM port
PuTTY flow control not set to None
Wrong baud rate
USB serial cable/driver issue
Board reset being pressed at the wrong time
Clock not actually 100 MHz
Old bitstream accidentally programmed instead of the new one
```
