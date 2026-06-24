"""Thin wrappers over external commands (gh, curl, tar). Kept in a `::py::` block
because subprocess result objects surface as untyped at the Jac boundary; the
exposed Jac functions return plain str/int."""

::py::
import subprocess
import sys as _sys


def _eprint(msg):
    print(msg, file=_sys.stderr)


def _stdin_read():
    return _sys.stdin.read()


def _run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(
            "command failed (%d): %s\n%s" % (r.returncode, " ".join(cmd), r.stderr)
        )
    return r.stdout


def _run_status(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    return [r.returncode, r.stdout, r.stderr]
::py::


# Run a command, returning stdout. Raises RuntimeError on a non-zero exit.
def run(cmd: list[str]) -> str {
    return str(_run(cmd));
}


# Run a command, returning (returncode, stdout, stderr) without raising.
def run_status(cmd: list[str]) -> list {
    return list(_run_status(cmd));
}


# Write a line to stderr (the Jac `print` stub does not accept a `file=` kwarg).
def eprint(msg: str) -> None {
    _eprint(msg);
}


# Read all of stdin as text.
def stdin_read() -> str {
    return str(_stdin_read());
}
