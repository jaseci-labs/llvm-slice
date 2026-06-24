"""Implementations for lib/model.jac (sees the head module's imports)."""

impl LibEntry.to_dict() -> dict {
    return {
        "file": self.file,
        "size": self.size,
        "sha256": self.sha256,
        "deps": self.deps,
        "external": self.external,
    };
}


impl Manifest.to_dict() -> dict {
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


impl PlatformAsset.to_dict() -> dict {
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


impl SkippedPlatform.to_dict() -> dict {
    return {"triple": self.triple, "reason": self.reason};
}


impl lib_entries_from_json(libs: dict) -> dict[str, LibEntry] {
    out: dict[str, LibEntry] = {};
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


impl utc_now_iso() -> str {
    return datetime.now(timezone.utc).isoformat();
}
