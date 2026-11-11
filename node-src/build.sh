#!/bin/sh
# The Node source slice's tree: the Rust crates of a Node release (deps/crates:
# the crate node_crates, whose dependency temporal_capi is V8's Temporal, and the
# crates they use, which Node vendors in vendor/ with cargo's checksums), as the
# release ships them. neojac builds them from this source in the one Rust link of
# a program that has Node in it, with the one Rust standard library there, where
# the Node slice's prebuilt libnode_crates.a carries one of its own.
#
#     node-src/build.sh <out>
#
# writes <out>/node-src/ (crates/, SOURCES.txt), from the Node release that
# node/sources.txt pins: the one the Node slice is built from.
RUNTIMES_DIR="$(cd "$(dirname "$0")/../runtimes" && pwd)"
SOURCES="$RUNTIMES_DIR/../node/sources.txt"
. "$RUNTIMES_DIR/lib.sh"

NODE_VERSION=26.13.0

out="$(mkdir -p "$1" && cd "$1" && pwd)"
tree="$out/node-src"
rm -rf "$tree"
mkdir -p "$tree"
unpack "node-v$NODE_VERSION.tar.xz" "$WORK/node-src-unpack" "node-v$NODE_VERSION/deps/crates"
[ -f "$WORK/node-src-unpack/deps/crates/Cargo.lock" ] || die "node-v$NODE_VERSION has no deps/crates/Cargo.lock"
[ -d "$WORK/node-src-unpack/deps/crates/vendor" ] || die "node-v$NODE_VERSION vendors no crates in deps/crates/vendor"
mv "$WORK/node-src-unpack/deps/crates" "$tree/crates"
rm -rf "$WORK/node-src-unpack"
{
    echo "# Node $NODE_VERSION's Rust crates (deps/crates), as the release ships them,"
    echo "# from this pinned input (llvm-slice node/sources.txt):"
    grep -h -E "^node-v$NODE_VERSION.tar.xz " "$SOURCES"
} > "$tree/SOURCES.txt"
log "node-src: $(du -sh "$tree" | cut -f1), $(find "$tree" -type f | wc -l | tr -d ' ') files"
