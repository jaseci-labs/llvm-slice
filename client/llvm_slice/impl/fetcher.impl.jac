"""Implementations for client/llvm_slice/fetcher.jac."""

impl resolve_repo(repo: str) -> str {
    if repo != "" {
        return repo;
    }
    env = os.environ.get("LLVM_SLICE_REPO");
    return str(env) if env is not None else DEFAULT_REPO;
}


impl asset_base(version: str, repo: str, base_override: str) -> str {
    if base_override != "" {
        return base_override[:-1] if base_override.endswith("/") else base_override;
    }
    return f"https://github.com/{repo}/releases/download/v{version}";
}


impl manifest_asset(version: str, triple: str) -> str {
    return f"llvm-{version}-{triple}-manifest.json";
}


impl zip_asset(version: str, triple: str) -> str {
    return f"llvm-{version}-{triple}-dev.zip";
}


impl http_get(url: str) -> bytes {
    r = urlopen(url);
    data = r.read();
    r.close();
    return bytes(data);
}


impl load_manifest(version: str, triple: str, repo: str, base_override: str) -> FetchedManifest {
    base: str = asset_base(version, resolve_repo(repo), base_override);
    url: str = f"{base}/{manifest_asset(version, triple)}";
    raw: bytes = http_get(url);
    data: dict = dict(json.loads(raw));
    if "libs" not in data {
        raise RuntimeError(f"manifest at {url} is missing the required 'libs' field");
    }
    libs = lib_entries_from_json(dict(data["libs"]));
    zip_a: str = str(data["zip_asset"]) if ("zip_asset" in data and data["zip_asset"] is not None) else zip_asset(version, triple);
    inc: str = str(data["include_prefix"]) if ("include_prefix" in data and data["include_prefix"] is not None) else "include/";
    cm: str = str(data["cmake_prefix"]) if ("cmake_prefix" in data and data["cmake_prefix"] is not None) else "lib/cmake/";
    ver: str = str(data["llvm_version"]) if ("llvm_version" in data and data["llvm_version"] is not None) else version;
    trip: str = str(data["triple"]) if ("triple" in data and data["triple"] is not None) else triple;
    return FetchedManifest(
        version=ver,
        triple=trip,
        zip_asset=zip_a,
        include_prefix=inc,
        cmake_prefix=cm,
        libs=libs,
    );
}


impl fetch_slice(
    version: str, triple: str, repo: str, base_override: str,
    roots: list[str], want_headers: bool, want_cmake: bool, out_dir: str
) -> FetchReport {
    fm: FetchedManifest = load_manifest(version, triple, repo, base_override);
    res = resolve_closure(fm.libs, roots);

    base: str = asset_base(version, resolve_repo(repo), base_override);
    # Use the manifest's recorded zip asset name (falling back to the default
    # pattern), so a manifest with a non-standard zip_asset still resolves.
    zname: str = fm.zip_asset if fm.zip_asset != "" else zip_asset(version, triple);
    zurl: str = f"{base}/{zname}";

    # The library members to pull are exactly the closure entries that have a file.
    lib_members: list[str] = [];
    for name in res.closure {
        fpath: str | None = fm.libs[name].file;
        if fpath is not None {
            lib_members.append(fpath);
        }
    }

    rep: dict = fetch_members(
        zurl, lib_members, fm.include_prefix, fm.cmake_prefix, want_headers, want_cmake, out_dir
    );

    return FetchReport(
        members=int(rep["members"]),
        bytes_fetched=int(rep["bytes_fetched"]),
        full_size=int(rep["full_size"]),
        closure=res.closure,
        external=res.external,
        missing=res.missing,
        range_supported=bool(rep["range_supported"]),
        warning=str(rep["warning"]),
    );
}
