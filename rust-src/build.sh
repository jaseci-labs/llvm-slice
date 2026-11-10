#!/bin/sh
# The Rust source slice's tree: what rustc's build reads of a Rust release besides
# what neojac keeps in its own repository (rustc, rustdoc and cargo, in neojac's
# rustc/; toolchain/pins.json's rust "vendored" lists them) and the build system
# neojac doesn't use (src/bootstrap/). So it holds the standard library and every
# crate rustc, rustdoc and cargo use, the upstream LLVM release's compiler-rt and
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
# What neojac's rustc/ holds, as its toolchain/pins.json lists it.
VENDORED="compiler src/librustdoc src/rustdoc-json-types src/tools/rustdoc src/tools/cargo"

out="$(mkdir -p "$1" && cd "$1" && pwd)"
tree="$out/rust-src"
rm -rf "$tree"
unpack "rustc-$RUST_VERSION-src.tar.xz" "$tree"
for d in $VENDORED src/bootstrap tests src/llvm-project; do
    rm -rf "${tree:?}/$d"
done
mkdir -p "$tree/src/llvm-project"
# Assigned first: a failed fetch stops the script.
llvm_src="$(fetch llvm-project-22.1.8.src.tar.xz)"
tar -xf "$llvm_src" -C "$tree/src/llvm-project" --strip-components=1 \
    llvm-project-22.1.8.src/compiler-rt llvm-project-22.1.8.src/libunwind llvm-project-22.1.8.src/cmake \
    llvm-project-22.1.8.src/runtimes llvm-project-22.1.8.src/llvm/cmake
{
    echo "# Rust $RUST_VERSION's source, less what neojac's rustc/ holds ($VENDORED),"
    echo "# src/bootstrap/ and tests/, from these"
    echo "# pinned inputs (llvm-slice rust-src/sources.txt, runtimes/sources.txt):"
    grep -h -E "^(rustc-$RUST_VERSION-src.tar.xz|llvm-project-22.1.8.src.tar.xz) " $SOURCES
} > "$tree/SOURCES.txt"
log "rust-src: $(du -sh "$tree" | cut -f1)"
