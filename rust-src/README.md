# The Rust source slice

`rust-src-<version>-dev.zip`, release `rust-src-v<version>-<revision>`: what neojac's
build of rustc reads of a Rust release besides what neojac keeps in its own
repository: rustc (`compiler/`), rustdoc (`src/librustdoc/`, `src/rustdoc-json-types/`,
`src/tools/rustdoc/`) and cargo (`src/tools/cargo/`), in neojac's `rustc/`, which
neojac's `toolchain/pins.json` lists as rust `vendored`. Member names start with
`rust-src/`.

| Holds | Why |
|---|---|
| `library/` | the standard library, which neojac builds for every target |
| the rest of `src/` | the members of the workspace neojac builds rustc and rustdoc in |
| `vendor/` | the crates rustc, rustdoc, cargo and the standard library use |
| `src/llvm-project/` | upstream LLVM's compiler-rt and libunwind, and the CMake modules they read, in place of Rust's LLVM |
| `Cargo.toml`, `Cargo.lock` and the rest of the top level | the workspace neojac builds it as |

It's source, not binaries, because Rust libraries must be built by the exact
compiler that uses them, so neojac builds these at its own release.

`rust-src/build.sh <out>` writes the tree, from the inputs `rust-src/sources.txt`
and `runtimes/sources.txt` pin; `build-rust-src.yml` packs and publishes it.

## The standard library's source slice

`rust-library-<version>-dev.zip`, release `rust-library-v<version>-<revision>`: only
`library/`. neojac fetches it to compile a target's standard library the first time a
build for that target needs it. It's separate because the whole slice's manifest is 31 MB
and has 163,523 members, where this one's a few thousand, small enough to ship in every
download of neojac.

`rust-src/library.sh <out>` writes the tree; `build-rust-src.yml` packs and publishes it.
