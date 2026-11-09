#!/bin/sh
# The Rust standard library's source slice's tree: `library/` of a Rust release, which
# neojac fetches to compile a target's standard library the first time a build names
# it. So it's a small part of the Rust source slice, with a manifest small enough to
# ship in every download of neojac.
#
#   rust-src/library.sh <out>
#
# writes <out>/library/.
RUNTIMES_DIR="$(cd "$(dirname "$0")/../runtimes" && pwd)"
. "$RUNTIMES_DIR/lib.sh"
SOURCES="$RUNTIMES_DIR/sources.txt $RUNTIMES_DIR/../rust-src/sources.txt"
RUST_VERSION=1.99.0

out="$(mkdir -p "$1" && cd "$1" && pwd)"
work="$out/.rust-src"
rm -rf "$work" "$out/library"
unpack "rustc-$RUST_VERSION-src.tar.xz" "$work"
mv "$work/library" "$out/library"
rm -rf "$work"
{
    echo "# Rust $RUST_VERSION's library/, from this pinned input (llvm-slice rust-src/sources.txt):"
    grep -h -E "^rustc-$RUST_VERSION-src.tar.xz " $SOURCES
} > "$out/library/SOURCES.txt"
log "rust-library: $(du -sh "$out/library" | cut -f1)"
