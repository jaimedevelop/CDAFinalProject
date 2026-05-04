param(
    [string]$InputPsm = "recorder_ui.psm",
    [string]$OutputHex = "recorder_ui.hex"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# FLAG: This script replaces the fragile template flow with a deterministic local assembler
# for the current recorder_ui.psm instruction subset (CONSTANT + labels + basic KCPSM6 ops).

function Remove-Comment {
    param([string]$Line)
    $idx = $Line.IndexOf(';')
    if ($idx -ge 0) {
        return $Line.Substring(0, $idx)
    }
    return $Line
}

function Parse-HexToken {
    param(
        [string]$Token,
        [int]$LineNo
    )
    if ($Token -notmatch '^[0-9A-Fa-f]+$') {
        throw "Line ${LineNo}: invalid hex token '$Token'."
    }
    return [Convert]::ToInt32($Token, 16)
}

function Resolve-Operand {
    param(
        [string]$Token,
        [hashtable]$Constants,
        [hashtable]$Labels,
        [int]$LineNo
    )
    $trimmed = $Token.Trim()
    if ($trimmed -match '^[sS]([0-9A-Fa-f])$') {
        return @{ Type = "reg"; Value = [Convert]::ToInt32($matches[1], 16) }
    }

    if ($trimmed -match '^[0-9A-Fa-f]+$') {
        return @{ Type = "imm"; Value = [Convert]::ToInt32($trimmed, 16) }
    }

    $key = $trimmed.ToUpperInvariant()
    if ($Constants.ContainsKey($key)) {
        return @{ Type = "imm"; Value = [int]$Constants[$key] }
    }
    if ($Labels.ContainsKey($key)) {
        return @{ Type = "addr"; Value = [int]$Labels[$key] }
    }

    throw "Line ${LineNo}: unresolved token '$trimmed'."
}

function Require-Range {
    param(
        [int]$Value,
        [int]$Min,
        [int]$Max,
        [string]$Context
    )
    if ($Value -lt $Min -or $Value -gt $Max) {
        throw "$Context out of range: $Value (expected $Min..$Max)."
    }
}

function Require-Register {
    param(
        [hashtable]$Operand,
        [int]$LineNo
    )
    if ($Operand.Type -ne "reg") {
        throw "Line ${LineNo}: expected register operand, got '$($Operand.Type)'."
    }
    Require-Range -Value $Operand.Value -Min 0 -Max 15 -Context "Line $LineNo register"
    return [int]$Operand.Value
}

function Require-ByteValue {
    param(
        [hashtable]$Operand,
        [int]$LineNo
    )
    if ($Operand.Type -eq "reg") {
        throw "Line ${LineNo}: expected immediate/constant, got register."
    }
    Require-Range -Value $Operand.Value -Min 0 -Max 255 -Context "Line $LineNo immediate"
    return [int]$Operand.Value
}

function Require-Address12 {
    param(
        [hashtable]$Operand,
        [int]$LineNo
    )
    if ($Operand.Type -eq "reg") {
        throw "Line ${LineNo}: expected label/address, got register."
    }
    Require-Range -Value $Operand.Value -Min 0 -Max 4095 -Context "Line $LineNo address"
    return [int]$Operand.Value
}

function Parse-ConditionOpcode {
    param(
        [string]$Condition,
        [hashtable]$Map,
        [int]$LineNo
    )
    $condKey = $Condition.Trim().ToUpperInvariant()
    if (-not $Map.ContainsKey($condKey)) {
        throw "Line ${LineNo}: unsupported condition '$Condition'."
    }
    return [int]$Map[$condKey]
}

$inputPath = (Resolve-Path -Path $InputPsm).Path
if ([System.IO.Path]::IsPathRooted($OutputHex)) {
    $outputPath = $OutputHex
}
else {
    $outputPath = Join-Path -Path (Split-Path -Parent $inputPath) -ChildPath $OutputHex
}

$constants = @{}
$labels = @{}
$instructions = New-Object System.Collections.Generic.List[object]

$pc = 0
$lineNo = 0
foreach ($line in Get-Content -Path $inputPath) {
    $lineNo++
    $work = (Remove-Comment -Line $line).Trim()
    if ([string]::IsNullOrWhiteSpace($work)) {
        continue
    }

    while ($work -match '^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$') {
        $labelName = $matches[1].ToUpperInvariant()
        if ($labels.ContainsKey($labelName)) {
            throw "Line ${lineNo}: duplicate label '$labelName'."
        }
        $labels[$labelName] = $pc
        $work = $matches[2].Trim()
        if ([string]::IsNullOrWhiteSpace($work)) {
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($work)) {
        continue
    }

    if ($work -match '^(?i)CONSTANT\s+([A-Za-z_][A-Za-z0-9_]*)\s*,\s*([0-9A-Fa-f]+)\s*$') {
        $constName = $matches[1].ToUpperInvariant()
        $constValue = Parse-HexToken -Token $matches[2] -LineNo $lineNo
        Require-Range -Value $constValue -Min 0 -Max 255 -Context "Line $lineNo CONSTANT $constName"
        $constants[$constName] = $constValue
        continue
    }

    $mnemonic = $work
    $operandText = ""
    if ($work -match '^([A-Za-z_]+)\s+(.*)$') {
        $mnemonic = $matches[1]
        $operandText = $matches[2].Trim()
    }

    $operands = @()
    if (-not [string]::IsNullOrWhiteSpace($operandText)) {
        $operands = @($operandText.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    }

    $instructions.Add([PSCustomObject]@{
            Address = $pc
            Mnemonic = $mnemonic.ToUpperInvariant()
            Operands = $operands
            LineNo = $lineNo
            Source = $line.Trim()
        })
    $pc++
}

Require-Range -Value $pc -Min 0 -Max 4096 -Context "Program size"

$encoded = New-Object System.Collections.Generic.List[object]
foreach ($inst in $instructions) {
    $m = $inst.Mnemonic
    $ops = @($inst.Operands)
    $ln = [int]$inst.LineNo
    $code = 0

    switch ($m) {
        "LOAD" {
            if ($ops.Count -ne 2) { throw "Line ${ln}: LOAD expects 2 operands." }
            $sx = Require-Register -Operand (Resolve-Operand -Token $ops[0] -Constants $constants -Labels $labels -LineNo $ln) -LineNo $ln
            $rhs = Resolve-Operand -Token $ops[1] -Constants $constants -Labels $labels -LineNo $ln
            if ($rhs.Type -eq "reg") {
                $sy = Require-Register -Operand $rhs -LineNo $ln
                $code = (0x00 -shl 12) -bor ($sx -shl 8) -bor ($sy -shl 4)
            }
            else {
                $kk = Require-ByteValue -Operand $rhs -LineNo $ln
                $code = (0x01 -shl 12) -bor ($sx -shl 8) -bor $kk
            }
        }
        "AND" {
            if ($ops.Count -ne 2) { throw "Line ${ln}: AND expects 2 operands." }
            $sx = Require-Register -Operand (Resolve-Operand -Token $ops[0] -Constants $constants -Labels $labels -LineNo $ln) -LineNo $ln
            $rhs = Resolve-Operand -Token $ops[1] -Constants $constants -Labels $labels -LineNo $ln
            if ($rhs.Type -eq "reg") {
                $sy = Require-Register -Operand $rhs -LineNo $ln
                $code = (0x02 -shl 12) -bor ($sx -shl 8) -bor ($sy -shl 4)
            }
            else {
                $kk = Require-ByteValue -Operand $rhs -LineNo $ln
                $code = (0x03 -shl 12) -bor ($sx -shl 8) -bor $kk
            }
        }
        "TEST" {
            if ($ops.Count -ne 2) { throw "Line ${ln}: TEST expects 2 operands." }
            $sx = Require-Register -Operand (Resolve-Operand -Token $ops[0] -Constants $constants -Labels $labels -LineNo $ln) -LineNo $ln
            $rhs = Resolve-Operand -Token $ops[1] -Constants $constants -Labels $labels -LineNo $ln
            if ($rhs.Type -eq "reg") {
                $sy = Require-Register -Operand $rhs -LineNo $ln
                $code = (0x0C -shl 12) -bor ($sx -shl 8) -bor ($sy -shl 4)
            }
            else {
                $kk = Require-ByteValue -Operand $rhs -LineNo $ln
                $code = (0x0D -shl 12) -bor ($sx -shl 8) -bor $kk
            }
        }
        "COMPARE" {
            if ($ops.Count -ne 2) { throw "Line ${ln}: COMPARE expects 2 operands." }
            $sx = Require-Register -Operand (Resolve-Operand -Token $ops[0] -Constants $constants -Labels $labels -LineNo $ln) -LineNo $ln
            $rhs = Resolve-Operand -Token $ops[1] -Constants $constants -Labels $labels -LineNo $ln
            if ($rhs.Type -eq "reg") {
                $sy = Require-Register -Operand $rhs -LineNo $ln
                $code = (0x1C -shl 12) -bor ($sx -shl 8) -bor ($sy -shl 4)
            }
            else {
                $kk = Require-ByteValue -Operand $rhs -LineNo $ln
                $code = (0x1D -shl 12) -bor ($sx -shl 8) -bor $kk
            }
        }
        "INPUT" {
            if ($ops.Count -ne 2) { throw "Line ${ln}: INPUT expects 2 operands." }
            $sx = Require-Register -Operand (Resolve-Operand -Token $ops[0] -Constants $constants -Labels $labels -LineNo $ln) -LineNo $ln
            $rhs = Resolve-Operand -Token $ops[1] -Constants $constants -Labels $labels -LineNo $ln
            if ($rhs.Type -eq "reg") {
                $sy = Require-Register -Operand $rhs -LineNo $ln
                $code = (0x08 -shl 12) -bor ($sx -shl 8) -bor ($sy -shl 4)
            }
            else {
                $port = Require-ByteValue -Operand $rhs -LineNo $ln
                $code = (0x09 -shl 12) -bor ($sx -shl 8) -bor $port
            }
        }
        "OUTPUT" {
            if ($ops.Count -ne 2) { throw "Line ${ln}: OUTPUT expects 2 operands." }
            $sx = Require-Register -Operand (Resolve-Operand -Token $ops[0] -Constants $constants -Labels $labels -LineNo $ln) -LineNo $ln
            $rhs = Resolve-Operand -Token $ops[1] -Constants $constants -Labels $labels -LineNo $ln
            if ($rhs.Type -eq "reg") {
                $sy = Require-Register -Operand $rhs -LineNo $ln
                $code = (0x2C -shl 12) -bor ($sx -shl 8) -bor ($sy -shl 4)
            }
            else {
                $port = Require-ByteValue -Operand $rhs -LineNo $ln
                $code = (0x2D -shl 12) -bor ($sx -shl 8) -bor $port
            }
        }
        "JUMP" {
            $jumpMap = @{
                "Z" = 0x32
                "NZ" = 0x36
                "C" = 0x3A
                "NC" = 0x3E
            }

            if ($ops.Count -eq 1) {
                $target = Require-Address12 -Operand (Resolve-Operand -Token $ops[0] -Constants $constants -Labels $labels -LineNo $ln) -LineNo $ln
                $code = (0x22 -shl 12) -bor $target
            }
            elseif ($ops.Count -eq 2) {
                $opcode = Parse-ConditionOpcode -Condition $ops[0] -Map $jumpMap -LineNo $ln
                $target = Require-Address12 -Operand (Resolve-Operand -Token $ops[1] -Constants $constants -Labels $labels -LineNo $ln) -LineNo $ln
                $code = ($opcode -shl 12) -bor $target
            }
            else {
                throw "Line ${ln}: JUMP expects 1 or 2 operands."
            }
        }
        "CALL" {
            $callMap = @{
                "Z" = 0x30
                "NZ" = 0x34
                "C" = 0x38
                "NC" = 0x3C
            }

            if ($ops.Count -eq 1) {
                $target = Require-Address12 -Operand (Resolve-Operand -Token $ops[0] -Constants $constants -Labels $labels -LineNo $ln) -LineNo $ln
                $code = (0x20 -shl 12) -bor $target
            }
            elseif ($ops.Count -eq 2) {
                $opcode = Parse-ConditionOpcode -Condition $ops[0] -Map $callMap -LineNo $ln
                $target = Require-Address12 -Operand (Resolve-Operand -Token $ops[1] -Constants $constants -Labels $labels -LineNo $ln) -LineNo $ln
                $code = ($opcode -shl 12) -bor $target
            }
            else {
                throw "Line ${ln}: CALL expects 1 or 2 operands."
            }
        }
        "RETURN" {
            $returnMap = @{
                "Z" = 0x31
                "NZ" = 0x35
                "C" = 0x39
                "NC" = 0x3D
            }

            if ($ops.Count -eq 0) {
                $code = (0x25 -shl 12)
            }
            elseif ($ops.Count -eq 1) {
                $opcode = Parse-ConditionOpcode -Condition $ops[0] -Map $returnMap -LineNo $ln
                $code = ($opcode -shl 12)
            }
            else {
                throw "Line ${ln}: RETURN expects 0 or 1 operands."
            }
        }
        default {
            throw "Line ${ln}: unsupported mnemonic '$m'."
        }
    }

    Require-Range -Value $code -Min 0 -Max 262143 -Context "Line $ln instruction encoding"
    $encoded.Add([PSCustomObject]@{
            Address = [int]$inst.Address
            Code = [int]$code
            LineNo = $ln
            Source = [string]$inst.Source
        })
}

$mem = New-Object 'System.UInt32[]' 4096
foreach ($row in $encoded) {
    $mem[$row.Address] = [uint32]$row.Code
}

$hexLines = for ($i = 0; $i -lt 4096; $i++) {
    "{0:X5}" -f $mem[$i]
}

Set-Content -Path $outputPath -Value $hexLines -Encoding ASCII

Write-Host ("Assembled {0} instructions from {1} into {2}" -f $encoded.Count, (Split-Path -Leaf $inputPath), (Split-Path -Leaf $outputPath))
