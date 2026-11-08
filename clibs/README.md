# The clibs slice

The C libraries the runtimes neojac compiles from their C are built on, for
every platform, one copy of each: CPython's standard library's (zlib, bzip2,
xz's liblzma, Zstandard, SQLite, libffi, OpenSSL) and Node's (zlib,
Zstandard, SQLite, libffi, OpenSSL). It is published as release
`clibs-v<set>-<revision>`, `<set>` naming the set of library releases by when
it was chosen (`2026.11`): `clibs-<set>-dev.zip`, a zip in the dev slices'
format (one DEFLATE member per file and a central directory, so a client
range-fetches what it needs), and `clibs-<set>-manifest.json`, which names
every member's size and sha256 (`docs/manifest-schema.md`). A consumer pins the
manifest by its sha256; neojac ships the tree in its `lib/`, beside the
runtimes slice's, and its CPython and Node link from it
(`{lib}/clibs/{platform}/`). The Node slice (`node/`) is built against it.

| Path | What |
|---|---|
| `clibs/<platform>/lib/` | `libz.a`, `libbz2.a`, `liblzma.a`, `libzstd.a`, `libsqlite3.a`, `libffi.a`, `libcrypto.a`, `libssl.a`, for `linux-x86_64`, `linux-aarch64`, `macos-aarch64` and `windows-x86_64`; `macos-x86_64` (Intel Macs, not an officially supported host) only when a dispatch of `build-clibs.yml` asks for it |
| `clibs/<platform>/include/` | their public headers, as each installs them |
| `clibs/<platform>/licenses/<library>/` | their licenses |
| `clibs/SOURCES.txt` | every pinned input |

Every library is static, and every symbol it defines is hidden: it is
compiled `-fvisibility=hidden`, and the APIs that would ask for default
visibility (Zstandard's, liblzma's) are built without it. A program that
exports its own C API, as an interpreter linked with `--export-dynamic` does
for its extension modules and addons, then exports none of theirs, and an
extension module bundling its own copy of a library binds to its own.
`check_hidden.py` proves it for the ELF and Mach-O platforms (PE exports only
what a DLL names).

Each library is at the release the newest of its consumers needs: SQLite
3.54.0 with every feature either enables (python.org's interpreters' and
Node's `deps/sqlite/sqlite.gyp`'s: sessions and their pre-update hook, RBU,
percentile functions), libffi 3.8.0 (Node calls `FFI_VERSION_STRING`, which
3.5 added) and OpenSSL 3.5.9, the releases Node 26.13.0 bundles.

## How each is made

Every input is pinned by sha256 in `sources.txt` (the LLVM release and
mingw-w64 in `runtimes/sources.txt`); `clibs.sh` builds each library by its
own build system.

| Platform | How |
|---|---|
| Linux | natively on each architecture, in a manylinux_2_28 container: its GCC, against glibc 2.28 |
| macOS | the LLVM release's Clang with the runner's SDK, for macOS 14.0, both architectures |
| Windows | on Linux, the LLVM release's Clang against mingw-w64 as `runtimes/mingw.sh` builds it (the Universal CRT) |

| Library | How |
|---|---|
| zlib | its configure, static (its MinGW makefile on Windows) |
| bzip2 | its Makefile's `libbz2.a` |
| liblzma | xz's configure, without its programs |
| Zstandard | its library's Makefile, multithreaded, without the legacy formats or the deprecated API |
| SQLite | its amalgamation, compiled with the features above |
| libffi | its configure |
| OpenSSL | its Configure: libcrypto and libssl, without assembly, loadable modules, engines or the legacy provider |

`.github/workflows/build-clibs.yml` runs it all, and `scripts/pack_slice.jac`
packs the tree.
