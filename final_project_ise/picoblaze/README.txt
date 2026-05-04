PicoBlaze UI source for the final project lives in:

    recorder_ui.psm

The local assembler assets are now also in this folder:

    assembler.exe
    Assembler.txt
    ROM_form.v

The working ISE project now points at:

    recorder_ui.v

The checked-in `recorder_ui.v` file defines `module ROM_form`, so it can drop
into the existing `picoblaze.v` wrapper without any wrapper changes.

Recommended VM-side flow:

1. Open this directory.
2. Run `assemble_recorder_ui.cmd` (or run `assemble_recorder_ui.ps1` directly).
3. This regenerates `recorder_ui.hex` from `recorder_ui.psm` using a local
   deterministic assembler script and avoids the fragile template-generated
   Verilog path that previously produced placeholder artifacts like `{...}` and `@`.
4. Keep using the checked-in `recorder_ui.v` ROM wrapper (the `$readmemh` module).
5. If `recorder_ui.psm` changes later, re-run the assembler script so
   `recorder_ui.hex` stays in sync with the source.

Current scope of `recorder_ui.psm`:

- prints a welcome banner
- prints the main 1..7 menu
- polls UART input
- echoes the typed character
- decodes menu selections
- prints simple confirmation/error text
- issues real hardware commands through the command/status register interface
