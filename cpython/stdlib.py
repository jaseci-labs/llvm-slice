"""Lay out CPython's standard library and its frozen modules for the slice.

    python3 cpython/stdlib.py <source> <build> <out>

<source> is the unpacked release, <build> a native build of it in which
Programs/_freeze_module has written Python/frozen_modules/ (cpython/stdlib.sh
makes both). Writes:

  <out>/lib/python3.15/                    Lib/, as an installed interpreter
                                           lays it out, less the test suite,
                                           IDLE and the Tk toolkits
  <out>/frozen/Python/frozen_modules/*.h   the frozen modules

The frozen modules are a native build's: Programs/_freeze_module (C) writes
them, and a cross build would write equivalent but different bytes with
Programs/_freeze_module.py, so this refuses any other's.
"""

import os
import shutil
import sys

# What the interpreter does not ship: the test suite (its own artifact, which
# a consumer's tests fetch), and the editor and the GUI toolkits built on Tk,
# whose C module neojac does not build. A name here is left out at every
# level, as a directory or a file.
LIB_LEAVE_OUT = {"test", "idlelib", "tkinter", "turtledemo", "turtle.py", "__pycache__"}


def copy_file(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)


def copy_lib(source, out):
    top = os.path.join(source, "Lib")
    dest = os.path.join(out, "lib", "python3.15")
    for dirpath, dirnames, filenames in os.walk(top):
        reldir = os.path.relpath(dirpath, top)
        dirnames[:] = sorted(d for d in dirnames if d not in LIB_LEAVE_OUT)
        for name in sorted(filenames):
            if reldir == "." and name in LIB_LEAVE_OUT:
                continue
            if name.endswith((".pyc", ".pyo")):
                continue
            copy_file(os.path.join(dirpath, name), os.path.join(dest, reldir, name))


def copy_frozen(build, out):
    frozen = os.path.join(build, "Python", "frozen_modules")
    names = sorted(n for n in os.listdir(frozen) if n.endswith(".h"))
    if "zipimport.h" not in names:
        sys.exit(f"{frozen} has no zipimport.h: the build wrote no frozen modules")
    # A native build freezes the import system's own modules (zipimport among
    # them) with the C freezer, the rest with the interpreter it bootstraps;
    # a cross build freezes every one with the Python freezer.
    with open(os.path.join(frozen, "zipimport.h")) as f:
        if "_freeze_module.c" not in f.readline():
            sys.exit(f"{frozen}/zipimport.h is not Programs/_freeze_module.c's: not a native build")
    for name in names:
        copy_file(os.path.join(frozen, name), os.path.join(out, "frozen", "Python", "frozen_modules", name))
    return len(names)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    source, build, out = sys.argv[1:4]
    for d in ["lib", "frozen"]:
        if os.path.isdir(os.path.join(out, d)):
            shutil.rmtree(os.path.join(out, d))
    copy_lib(source, out)
    n = copy_frozen(build, out)
    print(f"stdlib.py: the standard library and {n} frozen modules in {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
