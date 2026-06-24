"""Discover the repackageable platforms for an LLVM release.

Queries upstream release assets via `gh api`, classifies each into a triple
(handling both the clang+llvm-* and LLVM-* naming families and .tar.xz/.tar.gz),
applies an optional filter, and prints a JSON document:

  {"version": "18.1.8", "platforms": [ {triple, asset_name, url, ext, family,
                                        size, upstream_sha256}, ... ]}

The repackage workflow turns `.platforms` into a build matrix. Platforms are
never hardcoded -- whatever upstream published for that version is what we emit.

Usage:
  jac run scripts/discover.jac <version|latest> [--filter substr1,substr2]
"""

import sys;
import json;
import from lib.shell { run, eprint }
import from lib.classify { classify_asset }
import from lib.model { PlatformAsset }


# Resolve the newest non-prerelease llvmorg-X.Y.Z tag to its bare version.
def resolve_latest() -> str {
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


def _matches(triple: str, filt: str) -> bool {
    for tok in filt.split(",") {
        t: str = tok.strip();
        if t != "" and t in triple {
            return True;
        }
    }
    return False;
}


def discover(version: str, filt: str) -> dict {
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


with entry {
    argv: list[str] = sys.argv[1:];
    version: str = "";
    filt: str = "";
    i: int = 0;
    while i < len(argv) {
        tok: str = argv[i];
        has_next: bool = (i + 1) < len(argv);
        if tok == "--filter" {
            filt = argv[i + 1] if has_next else "";
            i += 1;
        } elif tok == "--version" {
            version = argv[i + 1] if has_next else "";
            i += 1;
        } elif not tok.startswith("--") {
            version = tok;
        }
        i += 1;
    }

    if version == "" or version == "latest" {
        version = resolve_latest();
    }
    if version == "" {
        eprint("error: could not resolve an LLVM version");
        sys.exit(1);
    }

    result: dict = discover(version, filt);
    print(json.dumps(result));
}
