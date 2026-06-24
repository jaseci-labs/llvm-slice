"""Implementations for scripts/discover.jac."""

impl resolve_latest() -> str {
    out: str = run([
        "gh", "api", "repos/llvm/llvm-project/releases", "--paginate",
        "-q", ".[] | select(.prerelease==false) | .tag_name"
    ]);
    for line in out.splitlines() {
        t: str = line.strip();
        if t.startswith("llvmorg-") {
            v: str = t[len("llvmorg-"):];
            if "-" not in v {   # skip rc/alpha/beta suffixes
                return v;
            }
        }
    }
    return "";
}


impl _matches(triple: str, filt: str) -> bool {
    for tok in filt.split(",") {
        t: str = tok.strip();
        if t != "" and t in triple {
            return True;
        }
    }
    return False;
}


impl discover(version: str, filt: str) -> dict {
    raw: str = run(["gh", "api", f"repos/llvm/llvm-project/releases/tags/llvmorg-{version}"]);
    data: dict = dict(json.loads(raw));
    assets: list = list(data["assets"]);

    platforms: list = [];
    for asset in assets {
        a: dict = dict(asset);
        name: str = str(a["name"]);
        kind = classify_asset(name, version);
        if kind is None {
            continue;
        }
        if filt != "" and not _matches(kind.triple, filt) {
            continue;
        }
        sha: str = "";
        if "digest" in a and a["digest"] is not None {
            d: str = str(a["digest"]);
            if d.startswith("sha256:") {
                sha = d[len("sha256:"):];
            }
        }
        pa = PlatformAsset(
            triple=kind.triple,
            asset_name=name,
            url=str(a["browser_download_url"]),
            ext=kind.ext,
            family=kind.family,
            size=int(a["size"]) if "size" in a else 0,
            upstream_sha256=sha,
        );
        platforms.append(pa.to_dict());
    }
    return {"version": version, "platforms": platforms};
}
