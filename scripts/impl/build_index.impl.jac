"""Implementations for scripts/build_index.jac."""

impl _read_records(path: str) -> list[str] {
    if path == "" {
        return stdin_read().splitlines();
    }
    f = open(path, "r");
    data: str = str(f.read());
    f.close();
    return data.splitlines();
}
