"""Shared data types for the llvm-slice toolchain.

These plain `obj` types are used by both the repackaging scripts (which build
manifests from extracted LLVM trees) and the client CLI (which parses published
manifests). Method and free-function bodies live in impl/model.impl.jac."""

import from datetime { datetime, timezone }


# One LLVM library target: its on-disk file inside the zip plus its dependency
# edges, split into internal LLVM targets and external link requirements.
obj LibEntry {
    has name: str;
    has file: str | None = None;   # path inside the zip, e.g. "lib/libLLVMCore.a"; null if header-only/missing
    has size: int = 0;
    has sha256: str = "";
    has deps: list[str] = [];      # internal LLVM target deps (resolve to files in this zip)
    has external: list[str] = [];  # non-LLVM link requirements, passed through verbatim

    def to_dict() -> dict;
}


# The per-platform manifest, keyed by LLVM library target name.
obj Manifest {
    has llvm_version: str;
    has triple: str;
    has schema_version: int = 1;
    has zip_asset: str = "";
    has zip_sha256: str = "";
    has upstream_tarball: str = "";
    has upstream_sha256: str = "";
    has include_prefix: str = "include/";
    has cmake_prefix: str = "lib/cmake/";
    has targets_to_build: list[str] = [];
    has libs: dict[str, LibEntry] = {};

    def to_dict() -> dict;
}


# A discovered upstream release asset that we can repackage.
obj PlatformAsset {
    has triple: str;
    has asset_name: str;       # upstream file name
    has url: str;              # browser_download_url
    has ext: str;              # "tar.xz" | "tar.gz"
    has family: str;           # "clang+llvm" | "LLVM"
    has size: int = 0;
    has upstream_sha256: str = "";   # from the GitHub asset digest if published, else ""

    def to_dict() -> dict;
}


# A platform that was discovered but could not be repackaged.
obj SkippedPlatform {
    has triple: str;
    has reason: str;

    def to_dict() -> dict;
}


# Rehydrate a manifest's `libs` object into LibEntry instances (used by the
# client when parsing a published manifest).
def lib_entries_from_json(libs: dict) -> dict[str, LibEntry];

# ISO-8601 UTC timestamp, used to stamp index.json.
def utc_now_iso() -> str;
