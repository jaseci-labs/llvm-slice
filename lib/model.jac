"""Shared data types for the llvm-slice toolchain.

These plain `obj` types are used by both the repackaging scripts (which build
manifests from extracted LLVM trees) and the client CLI (which parses published
manifests). Serialization helpers emit JSON keys in the documented schema order
(see docs/manifest-schema.md)."""

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

    def to_dict() -> dict {
        return {
            "file": self.file,
            "size": self.size,
            "sha256": self.sha256,
            "deps": self.deps,
            "external": self.external,
        };
    }
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

    def to_dict() -> dict {
        lib_dict: dict = {};
        for name in sorted(self.libs.keys()) {
            lib_dict[name] = self.libs[name].to_dict();
        }
        return {
            "schema_version": self.schema_version,
            "llvm_version": self.llvm_version,
            "triple": self.triple,
            "zip_asset": self.zip_asset,
            "zip_sha256": self.zip_sha256,
            "upstream_tarball": self.upstream_tarball,
            "upstream_sha256": self.upstream_sha256,
            "include_prefix": self.include_prefix,
            "cmake_prefix": self.cmake_prefix,
            "targets_to_build": self.targets_to_build,
            "libs": lib_dict,
        };
    }
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

    def to_dict() -> dict {
        return {
            "triple": self.triple,
            "asset_name": self.asset_name,
            "url": self.url,
            "ext": self.ext,
            "family": self.family,
            "size": self.size,
            "upstream_sha256": self.upstream_sha256,
        };
    }
}


# A platform that was discovered but could not be repackaged.
obj SkippedPlatform {
    has triple: str;
    has reason: str;

    def to_dict() -> dict {
        return {"triple": self.triple, "reason": self.reason};
    }
}


# Rehydrate a manifest's `libs` object back into LibEntry instances (used by the
# client when parsing a published manifest). Values come from json.loads as
# `any`, so each is explicitly cast at the boundary.
def lib_entries_from_json(libs: dict) -> dict {
    out: dict = {};
    for raw_name in libs.keys() {
        name: str = str(raw_name);
        raw = libs[raw_name];
        file_v = raw["file"] if "file" in raw else None;
        file_val: str | None = str(file_v) if file_v is not None else None;
        deps_raw = raw["deps"] if "deps" in raw else [];
        ext_raw = raw["external"] if "external" in raw else [];
        deps: list[str] = [str(x) for x in deps_raw];
        external: list[str] = [str(x) for x in ext_raw];
        size_v = raw["size"] if "size" in raw else 0;
        sha_v = raw["sha256"] if "sha256" in raw else "";
        out[name] = LibEntry(
            name=name,
            file=file_val,
            size=int(size_v),
            sha256=str(sha_v),
            deps=deps,
            external=external,
        );
    }
    return out;
}


# ISO-8601 UTC timestamp, used to stamp index.json.
def utc_now_iso() -> str {
    return datetime.now(timezone.utc).isoformat();
}
