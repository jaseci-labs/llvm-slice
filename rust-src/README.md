# The Rust source slice

`rust-src-<version>-dev.zip`, release `rust-src-v<version>-<revision>`: what neojac's
build of rustc reads of a Rust release besides what neojac keeps in its own
repository (`compiler/` and `src/bootstrap/`, in neojac's `rustc/`). Member names
start with `rust-src/`.

| Holds | Why |
|---|---|
| `library/` | the standard library, which neojac builds for every target |
| `src/librustdoc/`, `src/tools/{clippy,rustfmt,cargo}/` and the rest of `src/` | the tools, and the workspace rustc's bootstrap reads |
| `vendor/` | the crates all of it uses |
| `src/llvm-project/` | upstream LLVM's compiler-rt and libunwind, and the CMake modules they read, in place of Rust's LLVM |
| `Cargo.toml`, `Cargo.lock`, `x.py` and the rest of the top level | rustc's build |

It's source, not binaries, because Rust libraries must be built by the exact
compiler that uses them, so neojac builds these at its own release.

`rust-src/build.sh <out>` writes the tree, from the inputs `rust-src/sources.txt`
and `runtimes/sources.txt` pin; `build-rust-src.yml` packs and publishes it.
