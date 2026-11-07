"""Lay out CPython's standard library, its frozen modules and typeshed's
stubs of it for the slice.

    python3 cpython/stdlib.py <source> <build> <typeshed> <out>

<source> is the unpacked release, <build> a native build of it in which
Programs/_freeze_module has written Python/frozen_modules/ (cpython/stdlib.sh
makes both), <typeshed> an unpacked typeshed tree. Writes:

  <out>/lib/python3.15/                    Lib/, as an installed interpreter
                                           lays it out, less the test suite,
                                           IDLE and the Tk toolkits
  <out>/frozen/Python/frozen_modules/*.h   the frozen modules
  <out>/typeshed/{LICENSE,stdlib/}         typeshed's stubs of the standard
                                           library (and VERSIONS, which says
                                           which Pythons have each module):
                                           those of the modules this one
                                           ships, for a checker's types

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

# The Python whose standard library this is, for typeshed's VERSIONS.
VERSION = (3, 15)


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


def typeshed_versions(path):
    """VERSIONS as {module: (first, last)}, each a (major, minor) or None."""
    table = {}
    with open(path) as f:
        for line in f:
            line = line.split("#")[0].strip()
            if not line:
                continue
            module, span = line.split(":")
            first, last = span.strip().split("-")
            table[module.strip()] = tuple(
                tuple(int(p) for p in v.split(".")) if v else None for v in (first, last)
            )
    return table


def shipped(module, versions):
    """Whether this standard library has `module`: VERSIONS has it in 3.15
    (by its own line, else its nearest package's), and it is not one the
    slice leaves out."""
    if module.split(".")[0] in LIB_LEAVE_OUT or module.split(".")[0] + ".py" in LIB_LEAVE_OUT:
        return False
    parts = module.split(".")
    for k in range(len(parts), 0, -1):
        span = versions.get(".".join(parts[:k]))
        if span is not None:
            first, last = span
            return first <= VERSION and (last is None or VERSION <= last)
    sys.exit(f"typeshed's VERSIONS has no line for {module}")


def copy_typeshed(typeshed, out):
    src = os.path.join(typeshed, "stdlib")
    versions = typeshed_versions(os.path.join(src, "VERSIONS"))
    dest = os.path.join(out, "typeshed", "stdlib")
    n = 0
    for dirpath, dirnames, filenames in os.walk(src):
        rel = os.path.relpath(dirpath, src)
        dirnames.sort()
        for name in sorted(filenames):
            if not name.endswith(".pyi"):
                continue
            path = name[:-4] if rel == "." else os.path.join(rel, name[:-4])
            module = path.replace(os.sep, ".").removesuffix(".__init__")
            if shipped(module, versions):
                copy_file(os.path.join(dirpath, name), os.path.join(dest, rel, name))
                n += 1
    copy_file(os.path.join(src, "VERSIONS"), os.path.join(dest, "VERSIONS"))
    copy_file(os.path.join(typeshed, "LICENSE"), os.path.join(out, "typeshed", "LICENSE"))
    return n


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    source, build, typeshed, out = sys.argv[1:5]
    for d in ["lib", "frozen", "typeshed"]:
        if os.path.isdir(os.path.join(out, d)):
            shutil.rmtree(os.path.join(out, d))
    copy_lib(source, out)
    n = copy_frozen(build, out)
    stubs = copy_typeshed(typeshed, out)
    print(f"stdlib.py: the standard library, {n} frozen modules and {stubs} stubs in {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
