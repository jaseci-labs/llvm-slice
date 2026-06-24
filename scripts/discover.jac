"""Discover the repackageable platforms for an LLVM release.

Queries upstream release assets via `gh api`, classifies each into a triple
(handling both the clang+llvm-* and LLVM-* naming families and .tar.xz/.tar.gz),
applies an optional filter, and prints a JSON document:

  {"version": "18.1.8", "platforms": [ {triple, asset_name, url, ext, family,
                                        size, upstream_sha256}, ... ]}

The repackage workflow turns `.platforms` into a build matrix. Platforms are
never hardcoded -- whatever upstream published is what we emit. Bodies live in
impl/discover.impl.jac.

Usage:
  jac run scripts/discover.jac <version|latest> [--filter substr1,substr2]
"""

import sys;
import json;
import from lib.shell { run, eprint }
import from lib.classify { classify_asset }
import from lib.model { PlatformAsset }


# Resolve the newest non-prerelease llvmorg-X.Y.Z tag to its bare version.
def resolve_latest() -> str;
def _matches(triple: str, filt: str) -> bool;
def discover(version: str, filt: str) -> dict;


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
