"""Manifest loading and slice fetching.

`load_manifest` pulls the small standalone manifest (a few KB) so a closure can
be planned before touching the multi-hundred-MB zip. `fetch_slice` computes the
closure and pulls ONLY those members (plus optional include/ and lib/cmake/)
from the release zip via HTTP Range. Asset URLs default to this repo's GitHub
release download dir; `--base-url` overrides for local testing. Bodies live in
impl/fetcher.impl.jac."""

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


def resolve_repo(repo: str) -> str;
def asset_base(version: str, repo: str, base_override: str) -> str;
def manifest_asset(version: str, triple: str) -> str;
def zip_asset(version: str, triple: str) -> str;
def http_get(url: str) -> bytes;
def load_manifest(version: str, triple: str, repo: str, base_override: str) -> FetchedManifest;
def fetch_slice(
    version: str, triple: str, repo: str, base_override: str,
    roots: list[str], want_headers: bool, want_cmake: bool, out_dir: str
) -> FetchReport;
