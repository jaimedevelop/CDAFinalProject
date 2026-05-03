$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$personDir = Split-Path -Parent $scriptDir
$psmPath = Join-Path $personDir "final_project_complete.psm"
$emulator = Join-Path $scriptDir "psm_terminal_emulator.py"

python $emulator $psmPath `
  --expect "AUDIO MESSAGE RECORDER v1.0" `
  --expect "MAIN MENU:" `
  --expect "1) Play a message" `
  --expect "2) Record a message" `
  --expect "3) Delete a message" `
  --expect "4) Delete all messages" `
  --expect "5) Volume control" `
  --expect "Select [1-5]: "
