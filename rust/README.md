# The Rust slice

rustc and its tools, and Rust's standard library, built against an LLVM
library that carries rustc's LLVM wrapper itself: neojac's libneollvm, which
exports LLVM's C API and the wrapper's `LLVMRust*` functions and nothing of
LLVM's C++ API. A toolchain that ships that library (neojac) runs this rustc
on the same LLVM it generates code with, so it carries one copy of LLVM. It
is published as release `rust-v<version>-<revision>`: `rust-<version>-dev.zip`,
a zip in the dev slices' format (one DEFLATE member per file and a central
directory, so a client range-fetches what it needs), and
`rust-<version>-manifest.json`, which names every member's size and sha256
(`docs/manifest-schema.md`). A consumer pins the manifest by its sha256.

| Path | What |
|---|---|
| `rust/host/<host>/` | rustc (with rustdoc), cargo, clippy and rustfmt for each host, as a sysroot lays them out (`bin/`, `lib/`, `libexec/`, `share/`): `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`, `aarch64-apple-darwin`, `x86_64-pc-windows-gnullvm` |
| `rust/target/<target>/` | the standard library of each target, what a sysroot's `lib/rustlib/<target>/` holds: `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`, `x86_64-unknown-linux-musl`, `aarch64-unknown-linux-musl`, `x86_64-apple-darwin`, `aarch64-apple-darwin`, `x86_64-pc-windows-gnullvm`, `wasm32-wasip1` |
| `rust/neollvm-imports.txt` | every LLVM function rustc's binaries import from the LLVM library, which the library a consumer ships must export |
| `rust/SOURCES.txt` | every pinned input |

rustc's binaries name the LLVM library by the name it has in neojac:
`libneollvm.so` (its soname), `@rpath/libneollvm.dylib` (its install name),
`libneollvm.dll`. They carry no run path to it: the consumer runs them with
the library's directory on the loader's search path.

## How it is made

Every input is pinned by sha256 in `sources.txt` (the LLVM sources and
release, wasi-libc and Zig's inputs aside, in `runtimes/sources.txt`). Each
platform's job (`build.sh <platform>`, run by `.github/workflows/build-rust.yml`)
builds its Rust host's tools, and the standard library of the targets its
toolchain builds, with the platform's own C toolchain, as Rust's releases do:

| Platform | Toolchain | Host | Standard libraries |
|---|---|---|---|
| `linux-x86_64` | manylinux2014 (CentOS 7: GCC, glibc 2.17) | `x86_64-unknown-linux-gnu` | it, `x86_64-unknown-linux-musl`, `wasm32-wasip1` |
| `linux-aarch64` | manylinux2014 on aarch64 | `aarch64-unknown-linux-gnu` | it, `aarch64-unknown-linux-musl` |
| `macos-aarch64` | Xcode's Clang and SDK, for macOS 14.0 | `aarch64-apple-darwin` | it, `x86_64-apple-darwin` |
| `windows-x86_64` | llvm-mingw on Linux (Clang, LLD, mingw-w64 with the Universal CRT, libunwind) | `x86_64-pc-windows-gnullvm` | it |

The musl and WASI standard libraries' C (nothing links there) compiles with
Zig's cc. Every target's compiler runtime is compiler-rt's builtins as the
runtimes slice ships them, musl the runtimes slice's, and wasi-libc
wasi-sdk's sysroot. No system library reaches a build (pkg-config is
disabled).

- **The LLVM library** (`neollvm.sh`): rustc's LLVM wrapper, from its
  source, compiled against the LLVM slice's headers and linked with the
  slice's archives and the runtimes' compression libraries into
  `libneollvm`, exporting `LLVM*` and nothing else: on Linux from the libc++
  slices with Zig's c++ at their glibc 2.17 floor, on macOS from LLVM's
  official archives with the LLVM release's Clang and LLD. It runs the
  compiler the build makes, and is what rustc's binaries link against
  (Windows' link against an import library of the functions it exports).
- **rustc's source**, the release's, with Rust's own LLVM replaced by the
  upstream release's compiler-rt and libunwind (the standard library builds
  compiler-rt's profiling runtime and start files), and one patch,
  `rustc-llvm-wrapper-in-llvm.patch`: with `LLVM_PROVIDES_RUSTC_WRAPPER` set,
  `rustc_llvm` compiles no wrapper and links the LLVM library alone, no C++
  runtime or LLVM dependency, and `rustc_codegen_llvm` names no
  `llvm-wrapper` library.
- **rustc's bootstrap**, with a generated `llvm-config` describing the LLVM
  library to it, runs `x.py dist` for the host's tools and the standard
  libraries.
- The standard library carries line tables (`debuginfo-level-std = 1`),
  their debug sections compressed with zlib, as Rust's own releases do.
