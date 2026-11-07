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

Every input is pinned by sha256 in `sources.txt` (the LLVM sources, Zig's
inputs aside, and wasi-libc in `runtimes/sources.txt`), and it all builds on
linux-x86_64 (`build.sh`, run by `.github/workflows/build-rust.yml`):

- **The LLVM library** (`neollvm.sh`): rustc's LLVM wrapper, from its
  source, compiled against the libc++ LLVM slice's headers with Zig's c++,
  and linked with the slice's archives and the runtimes' zlib and zstd into
  `libneollvm.so`, at the slice's glibc 2.17 floor, exporting `LLVM*` and
  nothing else. It runs the compiler the build makes. Every other host gets a
  library to link against that exports the same functions (a stub, an import
  library): rustc's binaries load the consumer's library at run time.
- **rustc's source**, the release's, with Rust's own LLVM replaced by the
  upstream release's compiler-rt and libunwind (the standard library builds
  compiler-rt's profiling runtime), and one patch,
  `rustc-llvm-wrapper-in-llvm.patch`: with `LLVM_PROVIDES_RUSTC_WRAPPER` set,
  `rustc_llvm` compiles no wrapper and links the LLVM library alone, no C++
  runtime or LLVM dependency, and `rustc_codegen_llvm` names no
  `llvm-wrapper` library.
- **rustc's bootstrap**, with a generated `llvm-config` describing each
  host's LLVM library to it, builds each host's tools (`x.py dist rustc cargo
  clippy rustfmt`, cross-compiled from linux-x86_64 for the other hosts) and
  every target's standard library (`x.py dist rust-std`). Every target's C
  compiler and linker is Zig's cc at the target's floor (glibc 2.17, musl,
  macOS with the runtimes slice's framework stubs, mingw-w64 with the
  Universal CRT, WASI); the compiler runtime is compiler-rt's builtins as the
  runtimes slice ships them, musl the runtimes slice's, and wasi-libc
  wasi-sdk's sysroot. Nothing comes from the building machine: no system
  library (pkg-config is disabled) and no other C toolchain.
- The standard library carries line tables (`debuginfo-level-std = 1`),
  their debug sections compressed with zlib, as Rust's own releases do.
