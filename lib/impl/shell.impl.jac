"""Implementations for lib/shell.jac."""

impl run(cmd: list[str]) -> str {
    r = subprocess.run(cmd, capture_output=True, text=True);
    if r.returncode != 0 {
        raise RuntimeError(f"command failed ({r.returncode}): {' '.join(cmd)}\n{r.stderr}");
    }
    return str(r.stdout);
}


impl run_status(cmd: list[str]) -> list {
    r = subprocess.run(cmd, capture_output=True, text=True);
    return [r.returncode, r.stdout, r.stderr];
}


impl eprint(msg: str) -> None {
    os.write(2, (msg + "\n").encode());
}


impl stdin_read() -> str {
    parts: list[bytes] = [];
    while True {
        chunk: bytes = os.read(0, 65536);
        if len(chunk) == 0 {
            break;
        }
        parts.append(chunk);
    }
    return b"".join(parts).decode();
}
