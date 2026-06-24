# llvm-slices

Repackage official [LLVM releases](https://github.com/llvm/llvm-project/releases) into **per-platform,
range-fetchable artifacts** — so a downstream project can pull just the static libraries it links, instead
of downloading and decompressing a multi-gigabyte tarball to get a handful of files.

> **The build itself is upstream's.** This repo does **not** build, patch, or reconfigure LLVM. It only
> consumes the tarballs LLVM already publishes and repackages their development surface. All credit for the
> binaries belongs to the LLVM project.

## Why

The official LLVM releases ship each platform as a single `clang+llvm-<version>-<triple>.tar.xz`. A `.tar.xz`
is a **solid `xz` stream**: there is no seekable index, so to extract any one file you must download and
decompress the *entire* stream. A project that statically links only a subset of LLVM's libraries still has
to pull the whole tarball.

`llvm-slices` fixes this **without rebuilding LLVM**. For each LLVM release and each platform LLVM publishes,
it:

1. Downloads the official `clang+llvm-*` tarball.
2. Extracts only the **development surface** — static libs, headers, CMake package files, and `llvm-config`.
3. Repackages that surface as a **plain ZIP** (DEFLATE, with a central directory) so any HTTP client can pull
   individual members via **HTTP Range requests**. This is the whole point: `tar.xz` can't do random access;
   a ZIP central directory can.
4. Generates a **dependency manifest** (`manifest.json`) so a consumer can compute the transitive closure of
   the libraries it needs and fetch only those members.
5. Publishes the zips + manifests as GitHub Releases on this repo, mirroring upstream's version/platform
   matrix.

The value added over existing "prebuilt LLVM static libs" repos is specifically **granular, range-fetchable
access plus dependency metadata** — not another full build.

## How it works

### Seekability: tar.xz vs zip

| | `clang+llvm-*.tar.xz` (upstream) | `llvm-*-dev.zip` (this repo) |
|---|---|---|
| Compression | solid `xz` stream | per-member DEFLATE |
| Random access to one file | ❌ must decompress whole stream | ✅ via central directory + Range GET |
| Get N libraries out of hundreds | download everything | download only those members |

> *Note: SOZip is intentionally not used. The members are many separate `.a`/`.lib` files, so per-member
> random access from the ordinary ZIP central directory is already sufficient.*

### Dependency-closure model

To pick the right subset of libraries you need the inter-library dependency graph — but **`llvm-config` is
never run** to compute it. You can't execute a foreign-arch/OS binary on a Linux runner, and doing so would
break the "all platforms from one runner" property. Instead the dependency graph is derived by **parsing the
CMake package files**, which are plain text and identical in format across platforms (`lib/cmake/llvm/`):

- `LLVMConfig.cmake` → `LLVM_AVAILABLE_LIBS` (the full set of library targets), targets, include dirs, version.
- `LLVMExports.cmake` → each target's `INTERFACE_LINK_LIBRARIES`. Edges to other LLVM targets are **internal
  deps** (resolved to files in the zip); system libs / link flags (`-lpthread`, `z`, `zstd`, `ZLIB::ZLIB`, …)
  are **external requirements** passed through for the consumer to satisfy on their own link line.
- `LLVMExports-*.cmake` → `IMPORTED_LOCATION_*` maps each target to its on-disk file (e.g. `LLVMCore` →
  `lib/libLLVMCore.a`).

Because repackaging is **execution-free** (we only read text and copy files), **every** platform —
Linux/macOS/Windows, x86_64/aarch64/… — can be processed on a single `ubuntu-latest` runner.

## Published artifacts

Per LLVM release (tagged `v<llvm-version>` on this repo), each platform gets:

- `llvm-<version>-<triple>-dev.zip` — `lib/*.a` (or `*.lib`), `include/`, `lib/cmake/`, `bin/llvm-config`,
  and an embedded `manifest.json`.
- `llvm-<version>-<triple>-manifest.json` — standalone, so a consumer fetches a few-KB file to plan the
  dependency closure *before* touching the zip.
- `index.json` — every platform for the release, with asset names, URLs, sha256s, and any skipped platforms
  with reasons.

## Quickstart (consumer CLI)

A small, dependency-light Python CLI, `llvm-slice`, proves the round trip end to end:

```bash
# List the libraries available for a platform
llvm-slice list --version 20.1.8 --triple x86_64-linux-gnu-ubuntu-22.04

# Compute the transitive closure for a root set (+ merged external link requirements)
llvm-slice resolve --version 20.1.8 --triple x86_64-linux-gnu-ubuntu-22.04 \
  --libs LLVMOrcJIT,LLVMX86CodeGen

# Fetch ONLY those members from the release zip via HTTP Range requests
llvm-slice fetch --version 20.1.8 --triple x86_64-linux-gnu-ubuntu-22.04 \
  --libs LLVMOrcJIT,LLVMX86CodeGen --headers --cmake -o ./out
```

GitHub release-asset downloads redirect to a CDN that supports byte ranges; the CLI verifies this with a
`HEAD` / `Accept-Ranges` check and falls back to a full download (with a warning) if a mirror ever doesn't.

See [`docs/usage-cmake.md`](docs/usage-cmake.md) for consuming an extracted slice (`CMAKE_PREFIX_PATH` /
`LLVM_DIR`, or a raw link line built from `resolve`) and [`docs/manifest-schema.md`](docs/manifest-schema.md)
for the manifest format.

## Status

🚧 **Early / scaffolding.** This repo currently holds the design brief — see the pinned issue for the full
specification and implementation plan. Code, workflows, and the consumer CLI are being built against it.

## License

The repackaged binaries are produced by and licensed under the [LLVM project's license](https://llvm.org/LICENSE.txt)
(Apache-2.0 WITH LLVM-exception). Tooling in this repo is provided under its own license; see `LICENSE`.
