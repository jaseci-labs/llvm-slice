# llvm-slice

**Link the parts of LLVM you actually use — without downloading the parts you don't.**

If your project statically links a *subset* of LLVM's libraries, you've probably paid the LLVM tax: to get a
few `.a`/`.lib` files you download a multi-gigabyte `clang+llvm-*.tar.xz`, decompress the whole thing, and
throw away 95% of it. `llvm-slice` exists to make that unnecessary for **any** project, on **any** platform
LLVM ships — by turning the official releases into artifacts you can fetch *piece by piece*.

> 🙌 **This is community infrastructure, not a fork.** For the platforms LLVM publishes, we do **not** build,
> patch, or reconfigure LLVM -- we repackage the binaries LLVM already ships so they're cheaper to consume.
> All credit for the toolchain belongs to the [LLVM project](https://llvm.org).
>
> The one exception is the **libc++ Linux slice** (`*-linux-libcxx`): upstream ships no libc++ Linux build,
> so consumers that link the archives with a libc++ toolchain have nothing to repackage. That single variant
> is built from unmodified upstream LLVM sources (`build-libcxx.yml`); it is a stock LLVM configured with
> `-DLLVM_ENABLE_LIBCXX=ON`, not a patch or fork.

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

1. **Downloads** the official tarball — both upstream naming families are handled
   (`clang+llvm-<version>-<triple>.tar.{xz,gz}` and the newer
   `LLVM-<version>-<OS>-<ARCH>.tar.xz`); platforms are discovered dynamically, never hardcoded.
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

## Install

The primary path needs **no Python** — `install.sh` fetches a self-contained
`jac` runtime plus llvm-slice and drops a `llvm-slice` command on your PATH
(supported: linux-x86_64, linux-aarch64, macos-aarch64):

```bash
curl -fsSL https://raw.githubusercontent.com/jaseci-labs/llvm-slice/main/install.sh | sh
```

Pin a version with `LLVM_SLICE_REF=tool-v0.1.0`; relocate the install with
`LLVM_SLICE_PREFIX` / `LLVM_SLICE_BINDIR` (defaults `~/.llvm-slice` and
`~/.local/bin`).

On any platform with Python ≥ 3.10, install from PyPI instead — this adds the
`llvm-slice` command to a Jac-enabled environment (the runtime is the
still-on-PyPI `jaclang`):

```bash
pip install jaclang llvm-slice
```

Or run straight from a checkout with the `jac` toolchain on PATH: `bin/llvm-slice …`
(a thin wrapper around `jac run llvm_slice/cli.jac`).

## Quickstart

The whole tool is written in [Jac](https://jaseci.org) and is dependency-light —
it uses only the Python standard library (`urllib`, `zipfile`, `json`,
`hashlib`) plus the system `tar`/`gh`.

```bash
# 1. See what's available for a platform
llvm-slice list --version 18.1.8 --triple x86_64-linux-gnu-ubuntu-18.04

# 2. Compute the closure for the libs you link (+ the external link flags you'll need)
llvm-slice resolve --version 18.1.8 --triple x86_64-linux-gnu-ubuntu-18.04 \
  --libs LLVMOrcJIT,LLVMX86CodeGen
# closure: 57 libraries (static link order, dependents first)
#   LLVMX86CodeGen LLVMX86Desc … LLVMCore LLVMSupport LLVMDemangle
# external link requirements: -lpthread rt dl m ZLIB::ZLIB Terminfo::terminfo

# 3. Fetch ONLY those members over HTTP Range requests
llvm-slice fetch --version 18.1.8 --triple x86_64-linux-gnu-ubuntu-18.04 \
  --libs LLVMOrcJIT,LLVMX86CodeGen --headers --cmake -o ./out
# fetched 120 members (57 libs in closure) -> ./out
# transferred ~35 MB of ~804 MB (≈4% of the full zip)
```

You get back a directory you can point CMake at (`CMAKE_PREFIX_PATH` / `LLVM_DIR`) or feed to a raw link
line — having transferred a fraction of the bytes a full tarball would cost. See
[`docs/usage-cmake.md`](docs/usage-cmake.md) for both consumption paths and
[`docs/manifest-schema.md`](docs/manifest-schema.md) for the manifest format.

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

## How releases are produced (and kept current)

For upstream-published platforms, everything runs in GitHub Actions and no LLVM is ever rebuilt:

- **`repackage.yml`** (manual `workflow_dispatch`): a `discover` job queries
  upstream and emits a dynamic build matrix; one `repackage` job per platform
  downloads → verifies sha256 → stream-extracts the dev surface → parses the
  CMake files → emits the dev zip + manifest; a `publish` job assembles
  `index.json` and uploads everything to the `v<version>` release (idempotently,
  so re-runs never fail on duplicate assets).
- **`watch-upstream.yml`** (daily schedule): resolves the newest stable LLVM
  release and, if it isn't published here yet, dispatches `repackage.yml` for it
  — so the payload stays current automatically.
- **`ci.yml`**: `jac check` + `jac test` on every push/PR.

Because repackaging is **execution-free**, every upstream platform is processed
on a single `ubuntu-latest` runner.

- **`build-libcxx.yml`** (manual `workflow_dispatch`): the one build path. It
  compiles stock upstream LLVM with `zig c++` pinned to `x86_64-linux-gnu.2.17`
  (libc++ ABI + a glibc 2.17 floor, no container), then feeds the install tree
  through the same `repackage.jac --work-dir` path so the `*-linux-libcxx` slice
  comes out in the identical zip + manifest format. x86_64 first.

The CLI tool itself is released independently of the LLVM payload, on a
`tool-v<version>` tag (distinct from the `v<llvm-version>` payload tags):

- **`publish-pypi.yml`** (on a `tool-v*` tag): builds the wheel with `jac
  bundle` and uploads it to PyPI. One-time setup: add a `PYPI_API_TOKEN`
  repository secret.
- **`release-native.yml`** (on a `tool-v*` tag): smoke-tests `install.sh` on
  Linux and macOS, then publishes the GitHub release with the installer
  attached. No secret required.

## Repository layout

```
llvm_slice/ the CLI package (published to PyPI): cli · resolve (object-spatial
            closure) · rangezip · fetcher · model
lib/        repackaging-side Jac: asset classifier, CMake parser, shell/zip helpers
scripts/    discover.jac · repackage.jac · build_index.jac  (run from the repo root)
bin/        llvm-slice   wrapper around the CLI for local checkouts
install.sh  no-Python curl installer (jac runtime + sources)
docs/       manifest-schema.md · usage-cmake.md
.github/    workflows/   repackage · watch-upstream · ci · publish-pypi · release-native
```

Develop with `jac check <file>` and `jac test <module>.jac`. The dependency
closure is modeled with Jac's object-spatial walkers (an off-`root` LibNode /
DependsOn graph) — see `llvm_slice/resolve.jac`.

## Contributing

Issues and PRs from anyone who consumes LLVM are very welcome; the more projects
this serves, the better it does its job. The original design brief lives in the
repo's first issue.

## License & credit

The repackaged binaries are produced by and licensed under the
[LLVM license](https://llvm.org/LICENSE.txt) (Apache-2.0 WITH LLVM-exception). The tooling in this repo is
provided under its own license (see `LICENSE`). Thank you to the LLVM community for the toolchain that makes
all of this possible.
