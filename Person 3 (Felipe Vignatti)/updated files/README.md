# Person 3 UI Terminal Check

This folder contains an offline PicoBlaze PSM terminal-output check for `final_project_complete.psm`.

It does not need the Anvyl board, PuTTY, VirtualBox USB passthrough, or Xilinx ISE. It executes the startup/menu path in the assembly source with simulated UART status flags and captures bytes written to the UART TX port.

## Run

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File "Person 3 (Felipe Vignatti)\updated files\run_terminal_check.ps1"
```

## Current Result

The current uploaded `final_project_complete.psm` passes this check. It prints:

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

## What This Proves

- The uploaded PSM source includes the full menu text.
- The PSM startup/menu path sends the menu bytes in the expected order.
- The menu cut-off seen in PuTTY is probably not caused by missing assembly text.

## What This Does Not Prove

- It does not prove the programmed `loopback.bit` was rebuilt from this exact PSM.
- It does not test the physical RS232 cable, COM port, PuTTY settings, FPGA clock, or board reset behavior.
- It does not test the final hardware command/status integration with Persons 2 and 4.

If the board still shows corrupted PuTTY output, the next checks are:

1. Verify PuTTY is `9600`, `8-N-1`, flow control `None`.
2. Regenerate the PicoBlaze Verilog ROM from `final_project_complete.psm`.
3. Rebuild `loopback.bit` from repo-contained source files.
4. Confirm the top module uses the correct 100 MHz clock for the UART baud counter.
