"""Thin wrappers over external commands (gh, curl, tar) and small stdio helpers.
Bodies live in impl/shell.impl.jac."""

import subprocess;
import os;


# Run a command, returning stdout. Raises RuntimeError on a non-zero exit.
def run(cmd: list[str]) -> str;

# Run a command, returning [returncode, stdout, stderr] without raising.
def run_status(cmd: list[str]) -> list;

# Write a line to stderr (the Jac `print` stub does not accept a `file=` kwarg,
# and `sys.stderr.write` is untyped at the boundary, so write to fd 2 directly).
def eprint(msg: str) -> None;

# Read all of stdin as text (via fd 0).
def stdin_read() -> str;
