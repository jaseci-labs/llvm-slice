# Manifest & index schema

Each published LLVM release (`v<version>` on this repo) ships, per platform:

- `llvm-<version>-<triple>-dev.zip` — the range-fetchable dev surface (static
  libs, headers, `lib/cmake/`, `bin/llvm-config`) plus an embedded
  `manifest.json`.
- `llvm-<version>-<triple>-manifest.json` — the standalone manifest, so a client
  fetches a few KB to plan a dependency closure *before* touching the zip.
- `index.json` — one per release, listing every platform and any skips.

All manifests carry `"schema_version": 1`.

## `manifest.json`

```jsonc
{
  "schema_version": 1,
  "llvm_version": "18.1.8",
  "triple": "x86_64-linux-gnu-ubuntu-18.04",
  "zip_asset": "llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04-dev.zip",
  "zip_sha256": "6b923ac5…",          // sha256 of the dev.zip (empty in the embedded copy)
  "upstream_tarball": "clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz",
  "upstream_sha256": "…",             // sha256 verified at download time ("" if upstream published none)
  "include_prefix": "include/",        // where headers live inside the zip
  "cmake_prefix": "lib/cmake/",        // where the CMake package files live inside the zip
  "targets_to_build": ["AArch64", "ARM", "X86", "…"],   // LLVM_TARGETS_TO_BUILD
  "libs": {
    "LLVMCore": {
      "file": "lib/libLLVMCore.a",     // path inside the zip, or null if header-only / absent
      "size": 12345678,                // bytes
      "sha256": "…",                   // sha256 of the member
      "deps": ["LLVMBinaryFormat", "LLVMDemangle", "LLVMRemarks",
               "LLVMSupport", "LLVMTargetParser"],       // internal LLVM target deps
      "external": ["-lpthread"]        // non-LLVM link requirements (see below)
    }
    // … one entry for every name in LLVM_AVAILABLE_LIBS
  }
}
```

### Field notes

- **`libs` is keyed by LLVM library target name** (as listed in
  `LLVM_AVAILABLE_LIBS`), not by `llvm-config` component aliases. Aliases like
  `engine`, `native`, `all-targets` are intentionally out of scope for v1.
- **`deps`** are *internal* edges — every entry resolves to another key in
  `libs` (and thus a file in the zip). Computed by parsing each target's
  `INTERFACE_LINK_LIBRARIES` in `LLVMExports.cmake` and keeping the entries that
  are themselves in `LLVM_AVAILABLE_LIBS`. CMake generator-expression wrappers
  such as `$<LINK_ONLY:LLVMPasses>` are unwrapped to their inner target.
- **`external`** are *non-LLVM* link requirements passed through verbatim:
  `-lpthread`, `rt`, `dl`, `m`, `ZLIB::ZLIB`, `Terminfo::terminfo`, `zstd`, … The
  consumer must satisfy these on their own link line (see
  [usage-cmake.md](usage-cmake.md) for the flag mapping).
- **`file` is `null`** when a target is header-only/interface (no
  `IMPORTED_LOCATION`), or when its `.a`/`.lib` was not present in the tarball.
  Its `deps` are still recorded.
- The manifest is **derived purely from text** (`LLVMConfig.cmake`,
  `LLVMExports.cmake`, `LLVMExports-*.cmake`). `llvm-config` is never executed,
  so foreign-platform manifests are produced identically on a Linux runner.
- The **embedded** copy inside the zip has `zip_sha256: ""` (an archive cannot
  contain its own hash); the standalone `manifest.json` has the real value.

## `index.json`

```jsonc
{
  "schema_version": 1,
  "llvm_version": "18.1.8",
  "generated_at": "2026-06-24T12:00:00+00:00",
  "platforms": [
    {
      "triple": "x86_64-linux-gnu-ubuntu-18.04",
      "skipped": false,
      "zip_asset": "llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04-dev.zip",
      "zip_sha256": "…",
      "zip_size": 803866563,
      "manifest_asset": "llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04-manifest.json",
      "upstream_tarball": "clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz",
      "upstream_sha256": "…",
      "lib_count": 209
    }
  ],
  "skipped": [
    { "triple": "powerpc64-ibm-aix-7.2",
      "reason": "no static component libraries present (likely shared-only libLLVM build)" }
  ]
}
```

Platforms that lacked a usable dev surface (no `lib/cmake/llvm`, or a shared-only
`libLLVM` with no component `.a`/`.lib`) appear under `skipped` with a reason
rather than failing the release.
