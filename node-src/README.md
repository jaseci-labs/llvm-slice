# The Node source slice

`node-src-<version>-dev.zip`, release `node-src-v<version>-<revision>`: the Rust crates
of a Node release, as source. Member names start with `node-src/`.

| Holds | Why |
|---|---|
| `crates/` | Node's `deps/crates`: the crate `node_crates`, whose dependency `temporal_capi` is what V8's Temporal calls, and the crates they use, vendored by Node in `crates/vendor/` with cargo's checksums and pinned by `crates/Cargo.lock`, so they build offline |
| `SOURCES.txt` | the pinned Node release it is from |

It's source because a program has one Rust standard library. The Node slice's prebuilt
`libnode_crates.a` (`node/<platform>/lib/`) is these crates built as a static library,
with a Rust standard library of its own; neojac, whose programs can hold rustc and other
Rust besides Node, builds the crates from this source in the program's one Rust link.
neojac keeps the crate `node_crates` itself in its repository (`node/deps/crates/`) and
reads `crates/vendor/` from here.

`node-src/build.sh <out>` writes the tree, from the Node release `node/sources.txt` pins
(the one the Node slice is built from); `build-node-src.yml` packs and publishes it.
