"""Check that no static library of the CPython slice gives a symbol it defines
default visibility: a program exporting its own C API (an interpreter linked
with --export-dynamic or -export_dynamic) then exports none of the
libraries', and a shared library it loads that bundles its own copy of one
binds to its own.

    python3 clibs/check_hidden.py <tool> <archive>...

<tool> is `readelf` (ELF: a defined GLOBAL or WEAK symbol of DEFAULT
visibility fails) or an `llvm-nm` (Mach-O, with -m: a defined `external`
symbol that is not `private external` fails).
"""

import os
import subprocess
import sys


def elf_visible(tool, archive):
    out = subprocess.run([tool, "-sW", archive], check=True, capture_output=True, text=True).stdout
    found = []
    for line in out.splitlines():
        f = line.split()
        # Num: Value Size Type Bind Vis Ndx Name
        if len(f) < 8 or not f[0].endswith(":") or not f[0][:-1].isdigit():
            continue
        bind, vis, ndx, name = f[4], f[5], f[6], f[7]
        if bind in ("GLOBAL", "WEAK") and vis == "DEFAULT" and ndx != "UND":
            found.append(name)
    return found


def macho_visible(tool, archive):
    out = subprocess.run([tool, "-m", archive], check=True, capture_output=True, text=True).stdout
    found = []
    for line in out.splitlines():
        if "(undefined)" in line or " external " not in line or "private external" in line:
            continue
        found.append(line.split()[-1])
    return found


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    tool = sys.argv[1]
    visible = elf_visible if os.path.basename(tool) == "readelf" else macho_visible
    bad = 0
    for archive in sys.argv[2:]:
        names = sorted(set(visible(tool, archive)))
        if names:
            bad += 1
            shown = ", ".join(names[:12]) + (" ..." if len(names) > 12 else "")
            print(f"{os.path.basename(archive)}: {len(names)} symbols of default visibility: {shown}", file=sys.stderr)
    if bad:
        sys.exit(1)
    print(f"check_hidden.py: {len(sys.argv) - 2} libraries, every symbol hidden", file=sys.stderr)


if __name__ == "__main__":
    main()
