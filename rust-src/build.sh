#!/bin/sh
# The Rust source slice's tree: what rustc's build reads of a Rust release besides
# what neojac keeps in its own repository (compiler/ and src/bootstrap/, in
# neojac's rustc/). So it holds the standard library, rustdoc, clippy, rustfmt,
# cargo and every crate they use, the upstream LLVM release's compiler-rt and
# libunwind in place of Rust's LLVM, and no tests.
#
#   rust-src/build.sh <out>
#
# writes <out>/rust-src/. neojac builds it at its own release, because Rust
# libraries must be built by the compiler that uses them (rust-src/README.md).
RUNTIMES_DIR="$(cd "$(dirname "$0")/../runtimes" && pwd)"
. "$RUNTIMES_DIR/lib.sh"
SOURCES="$RUNTIMES_DIR/sources.txt $RUNTIMES_DIR/../rust-src/sources.txt"
RUST_VERSION=1.99.0

out="$(mkdir -p "$1" && cd "$1" && pwd)"
tree="$out/rust-src"
rm -rf "$tree"
unpack "rustc-$RUST_VERSION-src.tar.xz" "$tree"
rm -rf "$tree/compiler" "$tree/src/bootstrap" "$tree/tests" "$tree/src/llvm-project"
mkdir -p "$tree/src/llvm-project"
# Assigned first: a failed fetch stops the script.
llvm_src="$(fetch llvm-project-22.1.8.src.tar.xz)"
tar -xf "$llvm_src" -C "$tree/src/llvm-project" --strip-components=1 \
    llvm-project-22.1.8.src/compiler-rt llvm-project-22.1.8.src/libunwind llvm-project-22.1.8.src/cmake \
    llvm-project-22.1.8.src/runtimes llvm-project-22.1.8.src/llvm/cmake
{
    echo "# Rust $RUST_VERSION's source, less compiler/, src/bootstrap/ and tests/, from these"
    echo "# pinned inputs (llvm-slice rust-src/sources.txt, runtimes/sources.txt):"
    grep -h -E "^(rustc-$RUST_VERSION-src.tar.xz|llvm-project-22.1.8.src.tar.xz) " $SOURCES
} > "$tree/SOURCES.txt"
log "rust-src: $(du -sh "$tree" | cut -f1)"
