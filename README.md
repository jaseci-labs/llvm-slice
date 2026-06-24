# llvm-slice

**Link the parts of LLVM you actually use — without downloading the parts you don't.**

If your project statically links a *subset* of LLVM's libraries, you've probably paid the LLVM tax: to get a
few `.a`/`.lib` files you download a multi-gigabyte `clang+llvm-*.tar.xz`, decompress the whole thing, and
throw away 95% of it. `llvm-slice` exists to make that unnecessary for **any** project, on **any** platform
LLVM ships — by turning the official releases into artifacts you can fetch *piece by piece*.

> 🙌 **This is community infrastructure, not a fork.** We do **not** build, patch, or reconfigure LLVM. We
> repackage the binaries LLVM already publishes so they're cheaper to consume. All credit for the toolchain
> belongs to the [LLVM project](https://llvm.org).

## Who this is for

If you embed or link against LLVM, this is for you:

- **JIT & runtime authors** — pull just ORC/MCJIT + your target backend, skip every other target.
- **Compiler & language frontends** — link Core, your codegen target, and analysis libs, nothing else.
- **Static analysis / instrumentation tools** — grab the analysis surface without the world.
- **CI pipelines** — stop spending minutes per job decompressing tarballs to extract a handful of libs.
- **Packagers & toolchain integrators** — consistent, range-fetchable artifacts across every platform from
  one place.

If you've ever wished `find_package(LLVM)` could come from "just the bytes I need," that's the goal.

## The problem, briefly

Official LLVM releases ship each platform as a single `clang+llvm-<version>-<triple>.tar.xz`. A `.tar.xz` is
a **solid `xz` stream** — there's no seekable index, so to read *any one file* you must download and
decompress the *entire* stream. Linking a subset doesn't save you anything: you still pull it all.

## What llvm-slice does

For each LLVM release and each platform LLVM publishes, it:

1. **Downloads** the official `clang+llvm-*` tarball.
2. **Extracts** only the development surface — static libs, headers, CMake package files, `llvm-config`.
3. **Repackages** it as a **plain ZIP** (DEFLATE + central directory) so any HTTP client can fetch individual
   members via **Range requests**. `tar.xz` can't do random access; a ZIP central directory can.
4. **Publishes** a tiny **dependency manifest** (`manifest.json`) so you can compute the transitive closure
   of the libraries you need — and download *only those members*.

The thing that makes this generally useful isn't "prebuilt LLVM" (those exist) — it's **granular,
range-fetchable access plus dependency metadata**, available uniformly for every platform.

### tar.xz vs the slice

| | `clang+llvm-*.tar.xz` (upstream) | `llvm-*-dev.zip` (this repo) |
|---|---|---|
| Compression | solid `xz` stream | per-member DEFLATE |
| Random access to one file | ❌ decompress the whole stream | ✅ central directory + Range GET |
| Get N libs out of hundreds | download everything | download only those members |

## Quickstart

A small, dependency-light Python CLI proves the round trip:

```bash
# 1. See what's available for a platform
llvm-slice list --version 20.1.8 --triple x86_64-linux-gnu-ubuntu-22.04

# 2. Compute the closure for the libs you link (+ the external link flags you'll need)
llvm-slice resolve --version 20.1.8 --triple x86_64-linux-gnu-ubuntu-22.04 \
  --libs LLVMOrcJIT,LLVMX86CodeGen

# 3. Fetch ONLY those members over HTTP Range requests
llvm-slice fetch --version 20.1.8 --triple x86_64-linux-gnu-ubuntu-22.04 \
  --libs LLVMOrcJIT,LLVMX86CodeGen --headers --cmake -o ./out
```

You get back a directory you can point CMake at (`CMAKE_PREFIX_PATH` / `LLVM_DIR`) or feed to a raw link
line — having transferred a fraction of the bytes a full tarball would cost.

## How the dependency graph is computed (and why it's trustworthy)

`llvm-slice` **never runs `llvm-config`** to figure out dependencies. Running a foreign-arch/OS binary on a
build machine isn't portable — and it would break the property that *every* platform is processed identically
from one runner. Instead it **parses LLVM's own CMake package files**, which are plain text and identical in
format across platforms:

- `LLVMConfig.cmake` → `LLVM_AVAILABLE_LIBS`, targets, include dirs, version.
- `LLVMExports.cmake` → each target's `INTERFACE_LINK_LIBRARIES`. Edges to other LLVM targets are **internal
  deps** (resolved to files in the zip); system libs / link flags (`-lpthread`, `z`, `zstd`, `ZLIB::ZLIB`, …)
  are **external requirements** passed through so your link line stays correct.
- `LLVMExports-*.cmake` → `IMPORTED_LOCATION_*` maps each target to its on-disk file.

Because this is **execution-free** — we only read text and copy files — Linux, macOS, and Windows builds
(x86_64, aarch64, …) are all processed the same way, so coverage tracks whatever upstream shipped.

## Published artifacts

Per LLVM release (tagged `v<llvm-version>` here), every platform gets:

- `llvm-<version>-<triple>-dev.zip` — `lib/*.a` (or `*.lib`), `include/`, `lib/cmake/`, `bin/llvm-config`,
  and an embedded `manifest.json`.
- `llvm-<version>-<triple>-manifest.json` — standalone, so you fetch a few-KB file to plan your closure
  *before* touching the zip.
- `index.json` — every platform for the release, with asset names, URLs, sha256s, and any platforms skipped
  (with reasons).

> GitHub release-asset downloads redirect to a CDN that supports byte ranges; the CLI verifies this with an
> `Accept-Ranges` check and falls back to a full download (with a warning) if a mirror ever doesn't.

## Status & contributing

🚧 **Early days.** The full specification and implementation plan live in the pinned issue — that's the best
place to understand the design or pick up a piece. Issues and PRs from anyone who consumes LLVM are very
welcome; the more projects this serves, the better it does its job.

## License & credit

The repackaged binaries are produced by and licensed under the
[LLVM license](https://llvm.org/LICENSE.txt) (Apache-2.0 WITH LLVM-exception). The tooling in this repo is
provided under its own license (see `LICENSE`). Thank you to the LLVM community for the toolchain that makes
all of this possible.
