"""Manifest loading and slice fetching.

`load_manifest` pulls the small standalone manifest (a few KB) so a closure can
be planned before touching the multi-hundred-MB zip. `fetch_slice` then computes
the closure and pulls ONLY those members (plus optional include/ and lib/cmake/
trees) out of the release zip via HTTP Range requests.

Asset URLs default to this repo's GitHub release download directory
(`https://github.com/<repo>/releases/download/v<version>/...`); `--base-url`
overrides that for local testing (a directory served over http:// or file://)."""

import json;
import os;
import from urllib.request { urlopen }
import from lib.model { LibEntry, lib_entries_from_json }
import from client.llvm_slice.resolve { resolve_closure }
import from client.llvm_slice.rangezip { fetch_members }

glob DEFAULT_REPO: str = "jaseci-labs/llvm-slice";


obj FetchedManifest {
    has version: str;
    has triple: str;
    has zip_asset: str = "";
    has include_prefix: str = "include/";
    has cmake_prefix: str = "lib/cmake/";
    has libs: dict[str, LibEntry] = {};
}


obj FetchReport {
    has members: int = 0;
    has bytes_fetched: int = 0;
    has full_size: int = 0;
    has closure: list[str] = [];
    has external: list[str] = [];
    has missing: list[str] = [];
    has range_supported: bool = True;
    has warning: str = "";
}


def resolve_repo(repo: str) -> str {
    if repo != "" {
        return repo;
    }
    env = os.environ.get("LLVM_SLICE_REPO");
    return str(env) if env is not None else DEFAULT_REPO;
}


def asset_base(version: str, repo: str, base_override: str) -> str {
    if base_override != "" {
        return base_override[:-1] if base_override.endswith("/") else base_override;
    }
    return f"https://github.com/{repo}/releases/download/v{version}";
}


def manifest_asset(version: str, triple: str) -> str {
    return f"llvm-{version}-{triple}-manifest.json";
}


def zip_asset(version: str, triple: str) -> str {
    return f"llvm-{version}-{triple}-dev.zip";
}


def http_get(url: str) -> bytes {
    r = urlopen(url);
    data = r.read();
    r.close();
    return bytes(data);
}


def load_manifest(version: str, triple: str, repo: str, base_override: str) -> FetchedManifest {
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


def fetch_slice(
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
