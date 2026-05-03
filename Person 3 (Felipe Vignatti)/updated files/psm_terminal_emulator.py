#!/usr/bin/env python3
"""Minimal PicoBlaze PSM terminal-output checker.

This is not a full PicoBlaze simulator. It implements the instruction subset
needed to follow the startup/banner/menu path in final_project_complete.psm and
capture bytes written to the UART TX port.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


REG_NAMES = {f"s{i:X}": i for i in range(16)}
COMMENT_RE = re.compile(r";.*$")
CONSTANT_RE = re.compile(r"^CONSTANT\s+([A-Za-z_][A-Za-z0-9_]*)\s*,\s*([0-9A-Fa-f]+)\s*$")
LABEL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):(?:\s*(.*))?$")


class PsmProgram:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.constants: dict[str, int] = {}
        self.labels: dict[str, int] = {}
        self.instructions: list[tuple[int, str, list[str]]] = []
        self._parse()

    def _parse(self) -> None:
        for line_no, raw_line in enumerate(self.path.read_text(encoding="utf-8").splitlines(), 1):
            line = COMMENT_RE.sub("", raw_line).strip()
            if not line:
                continue

            match = CONSTANT_RE.match(line)
            if match:
                name, value = match.groups()
                self.constants[name] = int(value, 16) & 0xFF
                continue

            label_match = LABEL_RE.match(line)
            if label_match:
                label, rest = label_match.groups()
                self.labels[label] = len(self.instructions)
                line = (rest or "").strip()
                if not line:
                    continue

            parts = line.split(None, 1)
            op = parts[0].upper()
            args = []
            if len(parts) > 1:
                args = [arg.strip() for arg in parts[1].split(",")]
            self.instructions.append((line_no, op, args))

    def value(self, token: str) -> int:
        token = token.strip()
        if token in self.constants:
            return self.constants[token]
        return int(token, 16) & 0xFF


class StartupTerminalEmulator:
    def __init__(self, program: PsmProgram, start_label: str = "cold_start") -> None:
        self.program = program
        self.pc = self.program.labels[start_label]
        self.regs = [0] * 16
        self.ram = [0] * 256
        self.stack: list[int] = []
        self.zero = False
        self.carry = False
        self.output_bytes: list[int] = []
        self.port_writes: list[tuple[int, int]] = []
        self.wait_for_uart_visits = 0

    def reg_index(self, token: str) -> int:
        key = token.strip()
        if key not in REG_NAMES:
            raise ValueError(f"Unsupported register '{token}'")
        return REG_NAMES[key]

    def input_port_value(self, port: int) -> int:
        # Startup/menu print test: TX buffer is never full and no user key is
        # available. Status/switch inputs are held low.
        return 0

    def address_value(self, token: str) -> int:
        token = token.strip()
        if token.startswith("(") and token.endswith(")"):
            return self.regs[self.reg_index(token[1:-1])] & 0xFF
        return self.program.value(token)

    def step(self) -> bool:
        if self.pc < 0 or self.pc >= len(self.program.instructions):
            return False

        if self.pc == self.program.labels.get("wait_for_uart"):
            self.wait_for_uart_visits += 1
            if self.wait_for_uart_visits > 1:
                return False

        line_no, op, args = self.program.instructions[self.pc]
        next_pc = self.pc + 1

        if op == "LOAD":
            self.regs[self.reg_index(args[0])] = self.program.value(args[1])
        elif op == "INPUT":
            self.regs[self.reg_index(args[0])] = self.input_port_value(self.program.value(args[1]))
        elif op == "STORE":
            self.ram[self.address_value(args[1])] = self.regs[self.reg_index(args[0])] & 0xFF
        elif op == "FETCH":
            self.regs[self.reg_index(args[0])] = self.ram[self.address_value(args[1])]
        elif op == "OUTPUT":
            value = self.regs[self.reg_index(args[0])]
            port = self.program.value(args[1])
            self.port_writes.append((port, value))
            if port == self.program.constants.get("uart_data_tx"):
                self.output_bytes.append(value)
        elif op == "TEST":
            value = self.regs[self.reg_index(args[0])] & self.program.value(args[1])
            self.zero = value == 0
            self.carry = False
        elif op == "COMPARE":
            left = self.regs[self.reg_index(args[0])]
            right = self.program.value(args[1])
            self.zero = left == right
            self.carry = left < right
        elif op == "ADD":
            idx = self.reg_index(args[0])
            result = self.regs[idx] + self.program.value(args[1])
            self.regs[idx] = result & 0xFF
            self.zero = self.regs[idx] == 0
            self.carry = result > 0xFF
        elif op == "SUB":
            idx = self.reg_index(args[0])
            subtrahend = self.program.value(args[1])
            result = self.regs[idx] - subtrahend
            self.regs[idx] = result & 0xFF
            self.zero = self.regs[idx] == 0
            self.carry = result < 0
        elif op == "XOR":
            idx = self.reg_index(args[0])
            self.regs[idx] = (self.regs[idx] ^ self.program.value(args[1])) & 0xFF
            self.zero = self.regs[idx] == 0
            self.carry = False
        elif op == "OR":
            idx = self.reg_index(args[0])
            self.regs[idx] = (self.regs[idx] | self.program.value(args[1])) & 0xFF
            self.zero = self.regs[idx] == 0
            self.carry = False
        elif op == "AND":
            idx = self.reg_index(args[0])
            self.regs[idx] = (self.regs[idx] & self.program.value(args[1])) & 0xFF
            self.zero = self.regs[idx] == 0
            self.carry = False
        elif op == "CALL":
            self.stack.append(next_pc)
            next_pc = self.program.labels[args[0]]
        elif op == "RETURN":
            if not self.stack:
                raise RuntimeError(f"RETURN with empty stack at line {line_no}")
            next_pc = self.stack.pop()
        elif op == "JUMP":
            if len(args) == 1:
                next_pc = self.program.labels[args[0]]
            elif len(args) == 2:
                condition, label = args
                condition = condition.upper()
                take = (condition == "Z" and self.zero) or (condition == "NZ" and not self.zero)
                take = take or (condition == "C" and self.carry) or (condition == "NC" and not self.carry)
                if take:
                    next_pc = self.program.labels[label]
            else:
                raise ValueError(f"Unsupported JUMP form at line {line_no}")
        else:
            raise ValueError(f"Unsupported instruction {op} at line {line_no}")

        self.pc = next_pc
        return True

    def run(self, max_steps: int) -> str:
        for _ in range(max_steps):
            if not self.step():
                return bytes(self.output_bytes).decode("ascii", errors="replace")
        raise RuntimeError(f"Stopped after {max_steps} steps before reaching UART wait loop")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("psm", type=Path, help="Path to final_project_complete.psm")
    parser.add_argument("--expect", action="append", default=[], help="Text that must appear in terminal output")
    parser.add_argument("--max-steps", type=int, default=20000)
    args = parser.parse_args()

    program = PsmProgram(args.psm)
    emulator = StartupTerminalEmulator(program)
    terminal_text = emulator.run(args.max_steps)

    print("=== Captured terminal output ===")
    print(terminal_text, end="" if terminal_text.endswith("\n") else "\n")
    print("=== Check summary ===")
    print(f"Captured bytes: {len(terminal_text.encode('ascii', errors='replace'))}")

    missing = [expected for expected in args.expect if expected not in terminal_text]
    if missing:
        print("Missing expected text:")
        for expected in missing:
            print(f"- {expected}")
        return 1

    print("All expected text found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
