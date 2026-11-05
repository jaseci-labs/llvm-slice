"""Prove every target's runtime libraries link against its C library.

    python3 check_links.py <runtimes tree> <llvm-nm>

For each target under targets/, every symbol the runtime libraries (compiler-rt's
builtins, libunwind, libc++abi, libc++) need and do not define themselves must
come from the target's C library:

  *-linux-musl    musl's libc.a and start files
  *-linux-gnu     glibc 2.17, the oldest neojac targets: a symbol its
                  abilists list at 2.17 or earlier, or one in the 2.17 band's
                  libc_nonshared.a and start files
  *-windows-gnu   mingw-w64's libraries (the CRT and the import libraries)
  *-macos         libSystem's stub
  wasm32-wasi     wasi-libc

or be one the linker defines. A weak reference may stay undefined. And no
ELF runtime library may name a library for the link itself (a .deplibs
section, from #pragma comment(lib)): the link names the C library's parts.
This is what CMake cannot check for a cross build of static libraries, whose
checks compile without linking.
"""

import os
import re
import subprocess
import sys

RUNTIME_LIBS = ["libclang_rt.builtins.a", "libunwind.a", "libc++abi.a", "libc++.a"]

# Libraries of a target beyond its C library and runtime that are checked the
# same way: Windows' zlib, which programs link statically.
EXTRA_LIBS = {"x86_64-windows-gnu": ["libz.a"]}

# Symbols the linker defines for every output of the format.
LINKER_DEFINED = {
    "elf": {"__dso_handle", "_GLOBAL_OFFSET_TABLE_", "__ehdr_start", "__executable_start",
            "_DYNAMIC", "__init_array_start", "__init_array_end", "__fini_array_start",
            "__fini_array_end", "__preinit_array_start", "__preinit_array_end", "__bss_start",
            "_end", "_edata", "_etext", "__eh_frame_hdr_start", "__eh_frame_hdr_end",
            "__eh_frame_start", "__eh_frame_end", "__tls_get_addr"},
    "coff": {"__ImageBase", "__CTOR_LIST__", "__DTOR_LIST__", "_tls_index", "__tls_used"},
    "macho": {"___dso_handle", "__mh_execute_header", "__mh_dylib_header", "dyld_stub_binder"},
    "wasm": {"__dso_handle", "__heap_base", "__data_end", "__stack_pointer",
             "__wasm_call_ctors", "__indirect_function_table", "__memory_base",
             "__table_base", "__tls_base", "__tls_size", "__tls_align"},
}


def nm(llvm_nm: str, path: str) -> tuple[set[str], set[str]]:
    """The strong undefined and the defined symbols of an object or archive."""
    out = subprocess.run([llvm_nm, "-P", "--no-sort", path], capture_output=True, text=True, check=True).stdout
    undefined: set[str] = set()
    defined: set[str] = set()
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 2 or line.endswith(":"):
            continue
        name, kind = parts[0], parts[1]
        if kind == "U":
            undefined.add(name)
        elif kind not in ("w", "v", "U"):
            defined.add(name)
    return undefined, defined


def glibc_symbols(tree: str, arch: str, minor: int) -> set[str]:
    """The symbols glibc 2.<minor>'s libraries export (abilists.py's merge)."""
    syms: set[str] = set()
    with open(os.path.join(tree, "libc", "glibc", "abilist", f"{arch}.abilist")) as f:
        for line in f:
            lib, node, symbol, kind, size, first, last = line.split()
            if int(first) <= minor <= int(last):
                syms.add(symbol)
    return syms


def tbd_symbols(path: str, arch: str) -> set[str]:
    """The symbols a text stub exports for arch (arm64 programs link arm64e)."""
    want = {"aarch64": ("arm64", "arm64e"), "x86_64": ("x86_64",)}[arch]
    with open(path) as f:
        text = f.read()
    syms: set[str] = set()
    for block in re.finditer(r"-\s*targets:\s*\[([^\]]*)\]((?:(?!-\s*targets:).)*)", text, re.S):
        targets = [t.strip() for t in block.group(1).split(",")]
        if not any(t.split("-", 1)[0] in want and t.endswith("-macos") for t in targets):
            continue
        for lst in re.finditer(r"(?:symbols|weak-symbols|thread-local-symbols):\s*\[([^\]]*)\]", block.group(2)):
            syms.update(s.strip().strip("'\"") for s in lst.group(1).split(",") if s.strip())
    return syms


def main() -> None:
    tree, llvm_nm = sys.argv[1:3]
    failed = False
    for target in sorted(os.listdir(os.path.join(tree, "targets"))):
        tdir = os.path.join(tree, "targets", target)
        arch = target.split("-", 1)[0]
        libs = [os.path.join(tdir, n) for n in RUNTIME_LIBS + EXTRA_LIBS.get(target, [])
                if os.path.isfile(os.path.join(tdir, n))]
        need: set[str] = set()
        have: set[str] = set()
        for lib in libs:
            u, d = nm(llvm_nm, lib)
            need |= u
            have |= d
        if target.endswith("-linux-musl"):
            fmt = "elf"
            for n in ["libc.a", "crt1.o", "crti.o", "crtn.o"]:
                have |= nm(llvm_nm, os.path.join(tdir, n))[1]
        elif target.endswith("-linux-gnu"):
            fmt = "elf"
            have |= glibc_symbols(tree, arch, 17)
            band = os.path.join(tdir, "glibc-2.17")
            for n in os.listdir(band):
                have |= nm(llvm_nm, os.path.join(band, n))[1]
        elif target.endswith("-windows-gnu"):
            fmt = "coff"
            for n in os.listdir(tdir):
                if (n.endswith(".a") or n.endswith(".o")) and n not in RUNTIME_LIBS + EXTRA_LIBS[target]:
                    have |= nm(llvm_nm, os.path.join(tdir, n))[1]
        elif target.endswith("-macos"):
            fmt = "macho"
            have |= tbd_symbols(os.path.join(tree, "libc", "darwin", "libSystem.tbd"), arch)
        elif target == "wasm32-wasi":
            fmt = "wasm"
            for n in os.listdir(tdir):
                if n.endswith(".a") and n not in RUNTIME_LIBS:
                    have |= nm(llvm_nm, os.path.join(tdir, n))[1]
        else:
            sys.exit(f"check_links: unknown target {target}")
        if fmt == "elf":
            readelf = os.path.join(os.path.dirname(llvm_nm), "llvm-readelf")
            for lib in libs:
                sections = subprocess.run([readelf, "-S", "--wide", lib], capture_output=True, text=True, check=True).stdout
                if ".deplibs" in sections:
                    failed = True
                    print(f"{target}: {os.path.basename(lib)} names libraries for the link (.deplibs)")
        missing = sorted(need - have - LINKER_DEFINED[fmt])
        if missing:
            failed = True
            print(f"{target}: {len(missing)} unresolved: {' '.join(missing[:40])}")
        else:
            print(f"{target}: {len(need)} references, all resolved")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
