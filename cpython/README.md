# The CPython slice

What a toolchain that compiles CPython's C itself needs from the rest of a
CPython build: the C libraries CPython's standard library is built on, for
every platform, and the parts of CPython's release that are not C, the
standard library, the frozen modules and typeshed's stubs of the standard library. It is published as release
`cpython-v<version>-<revision>`: `cpython-<version>-dev.zip`, a zip in the dev
slices' format (one DEFLATE member per file and a central directory, so a
client range-fetches what it needs), and `cpython-<version>-manifest.json`,
which names every member's size and sha256 (`docs/manifest-schema.md`). A
consumer pins the manifest by its sha256; neojac ships the tree in its `lib/`,
beside the runtimes slice's.

| Path | What |
|---|---|
| `clibs/<platform>/lib/` | `libz.a`, `libbz2.a`, `liblzma.a`, `libzstd.a`, `libsqlite3.a`, `libffi.a`, `libcrypto.a`, `libssl.a`, for `linux-x86_64`, `linux-aarch64`, `macos-aarch64`, `macos-x86_64` and `windows-x86_64` |
| `clibs/<platform>/include/` | their public headers, as each installs them |
| `clibs/<platform>/licenses/<library>/` | their licenses |
| `cpython/lib/python3.15/` | the standard library (`Lib/`), as an installed interpreter lays it out, less the test suite, IDLE and Tk (`tkinter`, `turtle`, `turtledemo`) |
| `cpython/frozen/Python/frozen_modules/` | the frozen modules a native build writes, where CPython's C includes them from |
| `cpython/typeshed/{LICENSE,stdlib/}` | typeshed's stubs of the standard library, and its `VERSIONS`: those of the modules the standard library above has (in 3.15 by `VERSIONS`, and not Tk's), for a checker's types |
| `cpython/SOURCES.txt` | every pinned input |

Every library is static, and every symbol it defines is hidden: it is
compiled `-fvisibility=hidden`, and the APIs that would ask for default
visibility (Zstandard's, liblzma's) are built without it. A program that
exports its own C API, as an interpreter linked with `--export-dynamic` does
for its extension modules, then exports none of theirs, and an extension
module bundling its own copy of a library binds to its own.
`check_hidden.py` proves it for the ELF and Mach-O platforms (PE exports only
what a DLL names).

## How each piece is made

Every input is pinned by sha256 in `sources.txt` (the LLVM release and
mingw-w64 in `runtimes/sources.txt`); each library is built by its own build
system.

| Piece | Script | How |
|---|---|---|
| Linux's libraries | `clibs.sh` | natively on each architecture, in a manylinux_2_28 container: its GCC, against glibc 2.28 |
| macOS's libraries | `clibs.sh` | the LLVM release's Clang with the runner's SDK, for macOS 14.0, both architectures |
| Windows' libraries | `clibs.sh` | on Linux, the LLVM release's Clang against mingw-w64 as `runtimes/mingw.sh` builds it (the Universal CRT) |
| zlib | `clibs.sh` | its configure, static (its MinGW makefile on Windows) |
| bzip2 | `clibs.sh` | its Makefile's `libbz2.a` |
| liblzma | `clibs.sh` | xz's configure, without its programs |
| Zstandard | `clibs.sh` | its library's Makefile, multithreaded, without the legacy formats or the deprecated API |
| SQLite | `clibs.sh` | its amalgamation, compiled with the features python.org's interpreters enable |
| libffi | `clibs.sh` | its configure |
| OpenSSL | `clibs.sh` | its Configure: libcrypto and libssl, without assembly, loadable modules, engines or the legacy provider |
| the standard library and frozen modules | `stdlib.sh`, `stdlib.py` | CPython's configure and make of the frozen modules alone (`Programs/_freeze_module` and the interpreter it bootstraps), natively with the host's compiler |
| typeshed's stubs | `stdlib.sh`, `stdlib.py` | typeshed's `stdlib/` at a pinned commit, unchanged, less the stubs of modules the standard library doesn't have |

`.github/workflows/build-cpython.yml` runs it all, and `scripts/pack_slice.jac`
packs the tree.
