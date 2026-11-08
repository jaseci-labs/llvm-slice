# The Node slice

What a toolchain that compiles Node's own C++ (and libuv) itself needs from
the rest of a build of Node, for every platform: V8, ICU and the dependencies
Node keeps in its tree, prebuilt; the headers of theirs Node's C++ reads;
what Node's build generates that its C++ is compiled with; how that C++ is
compiled; and npm. It is published as release `node-v<version>-<revision>`:
`node-<version>-dev.zip`, a zip in the dev slices' format (one DEFLATE member
per file and a central directory, so a client range-fetches what it needs),
and `node-<version>-manifest.json`, which names every member's size and
sha256 (`docs/manifest-schema.md`). A consumer pins the manifest by its
sha256; neojac ships the tree in its `lib/`, beside the runtimes and clibs
slices', and builds Node from its own copy of Node's C++ (`rt/node`) with it.

| Path | What |
|---|---|
| `node/<platform>/lib/` | the static libraries `node` links but Node's own C++ (`node_base`), libuv and the clibs slice's: V8's (`libv8_*`, with its builtins and startup snapshot for the platform), what V8 is built on (Abseil, Highway, simdutf, V8's zlib), ICU's (`libicuucx`, `libicui18n`, `libicudata`, the full data), ada, brotli, c-ares, histogram, llhttp, merve, nbytes, ncrypto, nghttp2, simdjson, uvwasi and the inspector's protocol library (`libcrdtp`), and the Rust crates V8's Temporal is built on |
| `node/<platform>/include/` | every header of those Node's C++ reads, by the path it includes it as |
| `node/<platform>/gen/` | `node_javascript.cc` (Node's JavaScript, `lib/`, embedded as data by js2c), `node_snapshot.cc` (the startup snapshot `node_mksnapshot` writes), the inspector's protocol code, and the generated headers Node's C++ reads |
| `node/<platform>/build.json` | how Node's build compiles `node_base`, `libnode` and libuv for the platform (sources, defines, flags, include directories, every file of Node's tree those compiles read), and how a program links the slice (its archives, those linked whole, the system libraries) |
| `node/npm/` | npm, as Node's install lays it out |
| `node/LICENSE` | Node's license, which covers what it bundles |
| `node/SOURCES.txt` | every pinned input |

for `linux-x86_64`, `linux-aarch64` and `macos-aarch64`. `macos-x86_64` (Intel
Macs) is a lane of its own, built when a dispatch of `build-node.yml` asks for it
(`macos_x86_64`), on Apple silicon under Rosetta.

## How it is made

`build.sh` builds the release (pinned in `sources.txt`) with its own
configure and make, natively, compiled as neojac compiles C++ so that the
libraries link into a neojac program: the LLVM release's Clang (pinned in
`runtimes/sources.txt`) with the runtimes slice's libc++ and libc++abi (their
headers and static libraries), and on Linux the glibc headers neojac compiles
against, for glibc 2.28. Node links the clibs slice's OpenSSL, zlib,
Zstandard, SQLite and libffi (configure's `--shared-*`), as neojac's Node
does, and its Temporal is built by the pinned Rust toolchain. Node is built
with full ICU and without LIEF (single executable applications, which a
neojac program, linked whole, has no need of). The build checks the `node`
it made runs, then `pack.py` takes the tree from it: what each file is and
why is in its docstring.

`.github/workflows/build-node.yml` runs it for every platform and packs the
tree with `scripts/pack_slice.jac`.
