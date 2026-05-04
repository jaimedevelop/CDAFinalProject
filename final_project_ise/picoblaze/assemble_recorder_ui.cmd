@echo off
cd /d "%~dp0"
REM FLAG: Use the local deterministic assembler script so recorder_ui.hex always matches recorder_ui.psm.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0assemble_recorder_ui.ps1" -InputPsm "%~dp0recorder_ui.psm" -OutputHex "%~dp0recorder_ui.hex"
