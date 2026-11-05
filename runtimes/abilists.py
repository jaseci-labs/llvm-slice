"""Merge the ABI lists of every glibc release into one per architecture.

    python3 abilists.py <out> <release dir>...

Each <release dir> is an extracted glibc source tree (glibc-2.N/). glibc keeps,
for each library and architecture, the list of every symbol the library
exports and the version node it is exported at (the test data of its ABI
checks: sysdeps/unix/sysv/linux/<arch>/<lib>.abilist). Which library exports a
symbol changes between releases (2.34 moved libpthread, libdl, librt and
libutil into libc), so a link for release 2.N must use 2.N's own lists. The
merged list says which releases each entry holds in, one line per entry:

    <lib> <version node> <symbol> <F|D> <size> <first> <last>

<lib> is c, m, ld, resolv, pthread, dl, rt or util; F a function, D an object
of <size> bytes (0 for a function); <first> and <last> the minor numbers of the
first and last 2.N release whose lists have the entry. Writes
<out>/<arch>.abilist for x86_64 and aarch64, and <out>/VERSION, the newest
release.
"""

import os
import re
import sys

LIBS = ["c", "m", "ld", "resolv", "pthread", "dl", "rt", "util"]

# Where each architecture's lists are: older releases keep libpthread's in an
# nptl/ subdirectory, and until the ports were merged into the main tree
# (2.20) AArch64's were under ports/.
DIRS = {
    "x86_64": ["sysdeps/unix/sysv/linux/x86_64/64", "sysdeps/unix/sysv/linux/x86_64/64/nptl"],
    "aarch64": [
        "sysdeps/unix/sysv/linux/aarch64",
        "sysdeps/unix/sysv/linux/aarch64/nptl",
        "ports/sysdeps/unix/sysv/linux/aarch64",
        "ports/sysdeps/unix/sysv/linux/aarch64/nptl",
    ],
}


def file_name(lib: str) -> str:
    return "ld.abilist" if lib == "ld" else f"lib{lib}.abilist"


def parse(path: str) -> list[tuple[str, str, str, int]]:
    """(version node, symbol, type, size) for each entry of an abilist, in
    either format: one line per entry (2.24 and later), or a version node
    followed by its indented entries (before), whose `<node> A` lines only
    name the node."""
    out = []
    node = None
    with open(path) as f:
        for line in f:
            if not line.strip():
                continue
            fields = line.split()
            if line[0] not in " \t":
                if len(fields) == 1:
                    node = fields[0]
                    continue
                node, fields = fields[0], fields[1:]
            if node is None or len(fields) < 2:
                sys.exit(f"abilists: {path}: cannot read {line!r}")
            symbol, kind = fields[0], fields[1]
            if kind == "A":
                continue
            if kind not in ("F", "D"):
                sys.exit(f"abilists: {path}: unknown kind {kind!r}")
            size = int(fields[2], 16) if kind == "D" else 0
            out.append((node, symbol, kind, size))
    return out


def release_minor(tree: str) -> int:
    with open(os.path.join(tree, "version.h")) as f:
        m = re.search(r'#define VERSION "2\.(\d+)"', f.read())
    if not m:
        sys.exit(f"abilists: {tree} is not a glibc 2.N release")
    return int(m.group(1))


def main() -> None:
    out, trees = sys.argv[1], sys.argv[2:]
    os.makedirs(out, exist_ok=True)
    newest = 0
    for arch, dirs in DIRS.items():
        # (lib, node, symbol, kind, size) -> the releases that have it
        seen: dict[tuple, set[int]] = {}
        for tree in trees:
            minor = release_minor(tree)
            newest = max(newest, minor)
            for lib in LIBS:
                found = [os.path.join(tree, d, file_name(lib)) for d in dirs
                         if os.path.isfile(os.path.join(tree, d, file_name(lib)))]
                if len(found) != 1:
                    sys.exit(f"abilists: glibc 2.{minor} has {len(found)} {file_name(lib)} for {arch}")
                for node, symbol, kind, size in parse(found[0]):
                    seen.setdefault((lib, node, symbol, kind, size), set()).add(minor)
        lines = []
        for (lib, node, symbol, kind, size), releases in seen.items():
            ordered = sorted(releases)
            first = ordered[0]
            prev = first
            for r in ordered[1:] + [None]:
                if r is not None and r == prev + 1:
                    prev = r
                    continue
                lines.append(f"{lib} {node} {symbol} {kind} {size} {first} {prev}\n")
                if r is not None:
                    first = prev = r
        lines.sort()
        with open(os.path.join(out, f"{arch}.abilist"), "w") as f:
            f.writelines(lines)
        print(f"abilists: {arch}: {len(lines)} entries from {len(trees)} releases")
    with open(os.path.join(out, "VERSION"), "w") as f:
        f.write(f"2.{newest}\n")


if __name__ == "__main__":
    main()
