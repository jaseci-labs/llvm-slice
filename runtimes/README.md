# The runtimes slice

What a toolchain built from an LLVM release (Clang and LLD) needs to compile
and link C and C++ for every target below without a sysroot, Xcode or an SDK:
the C library headers, the data link-time stubs are made from, and every
target's prebuilt C and C++ runtime. It is published as release
`runtimes-v<llvm>-<revision>`: `llvm-<llvm>-runtimes-dev.zip`, a zip in the dev
slices' format (one DEFLATE member per file and a central directory, so a client
range-fetches what it needs), and `llvm-<llvm>-runtimes-manifest.json`, which
names every member's size and sha256 (`docs/manifest-schema.md`). A consumer
pins the manifest by its sha256; neojac ships the tree as its `lib/`.

| Target | Under `targets/` |
|---|---|
| `x86_64-linux-musl`, `aarch64-linux-musl` | musl's `libc.a` and start files (`crt1.o`, `rcrt1.o`, `Scrt1.o`, `crti.o`, `crtn.o`) |
| `x86_64-linux-gnu`, `aarch64-linux-gnu` | glibc's start files and `libc_nonshared.a` for each band of releases whose start files differ: `glibc-2.17/` (2.17 to 2.32), `glibc-2.33/`, `glibc-2.34/` (2.34 and later) |
| `x86_64-windows-gnu` | mingw-w64's CRT (`crt2.o`, `crt2u.o`, `dllcrt2.o`, `crtbegin.o`, `crtend.o`, `libmingw32.a`, `libmingwex.a`, ...), winpthreads, and the import libraries of the system's DLLs, against the Universal CRT; and zlib (`libz.a`, its headers in `libc/include/mingw-w64/`), which Windows ships no DLL of |
| `aarch64-macos`, `x86_64-macos` | (libSystem is the C library: `libc/darwin/libSystem.tbd`; the frameworks programs link besides it, CoreFoundation, Security and SystemConfiguration, are `libc/darwin/System/Library/Frameworks/<name>.framework/`, each its headers and stub) |
| `wasm32-wasi` | wasi-libc and its emulation libraries |

Every target but `wasm32-wasi` also has compiler-rt's builtins
(`libclang_rt.builtins.a`), LLVM's `libc++.a` and `libc++abi.a`, `libunwind.a`
(not on macOS, whose unwinder is libSystem's), and `include/__config_site`,
libc++'s configuration for the target (its other headers are `libcxx/include/`).
Programs link the C++ runtime statically. The Linux runtimes are built against
the oldest glibc the targets support, 2.17, and `assemble.sh` proves (with
`check_links.py`) that every reference they make resolves there, and on every
other target against its C library.

## How each piece is made

Every input is pinned by sha256 in `sources.txt`; each piece is built by its
own build system with the LLVM release's Clang.

| Piece | Script | How |
|---|---|---|
| Linux's headers | `linux-headers.sh` | the kernel's `make headers_install`, for x86_64 and arm64 |
| musl | `musl.sh` | musl's configure and make, with its maintainers' published fixes |
| glibc's start files | `glibc-crt.sh`, `era-deps.sh` | glibc's configure and make of each band's first release, with the GCC of its time, in a distribution of its era (glibc builds only with GCC) |
| glibc's ABI lists | `glibc-data.sh`, `abilists.py` | every release's own lists from 2.17 to 2.44, merged: which library exports each symbol at which version node, in which releases |
| glibc's headers | `glibc-data.sh` | Zig 0.17.0's curated set: one set for every release, whose declarations follow `-D__GLIBC_MINOR__` |
| mingw-w64 | `mingw.sh` | its configure and make, in llvm-mingw's order: headers, CRT, compiler-rt's builtins, winpthreads, the C++ runtime; with two fixes to its headers (`patches/`): `<intrin.h>` included after `<cpuid.h>` no longer breaks on `<cpuid.h>`'s `__cpuid` macro, and `<stdlib.h>` declares the Universal CRT's `_set_thread_local_invalid_parameter_handler` and `_get_thread_local_invalid_parameter_handler`, which its import libraries export |
| zlib for Windows | `mingw.sh` | zlib's own MinGW makefile (`win32/Makefile.gcc`), the static library |
| compiler-rt, libunwind, libc++abi, libc++ | `llvm-runtimes.sh` | LLVM's own CMake, from the release's sources |
| the macOS SDK's headers, libSystem's stub and the frameworks' | `darwin.sh`, `tbd_targets.py` | the runner's SDK, the stubs restricted to the architectures the release's TextAPI reads |
| wasi-libc | `assemble.sh` | wasi-sdk's own build of it and of compiler-rt's builtins |
| zlib, zstd, libxml2 (`host/`) | `host-libs.sh` | their CMake, with LLVM's release options: what the official macOS and Windows LLVM archives reference but do not ship |

`assemble.sh` lays the pieces out and checks them; `scripts/pack_runtimes.jac`
packs the tree. `.github/workflows/build-runtimes.yml` runs it all.

Linux's headers include a few names that differ only in case
(`linux/netfilter/xt_CONNMARK.h` and `xt_connmark.h`, ...). On a
case-insensitive file system only one of each pair can exist: members are
written in the zip's (sorted) order, so the lower-case one is kept.
