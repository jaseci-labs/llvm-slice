"""Range-fetch individual members out of a remote ZIP.

A ZIP central directory lets an HTTP client pull single members without
downloading the whole archive -- the reason this project repackages tar.xz into
zip. We lean on the stdlib `zipfile` (central-directory parsing + inflate) and
supply a seekable file object, `HTTPRangeReader`, whose reads are served by HTTP
Range requests. No third-party deps and no inline Python.

GitHub release-asset downloads redirect to a CDN that supports byte ranges; the
reader verifies `Accept-Ranges: bytes` up front and, if a mirror ever lacks it,
falls back to a single full download (recording a warning). Bodies live in
impl/rangezip.impl.jac."""

import os;
import zipfile;
import from urllib.request { urlopen, Request }


# A seekable, read-only file object backed by HTTP Range requests. Tracks
# `bytes_fetched` (bytes actually transferred) vs `size` (the full asset length)
# so callers can prove a partial fetch moved fewer bytes than a full download.
obj HTTPRangeReader {
    has url: str;
    has timeout: int = 60;
    has pos: int = 0;
    has bytes_fetched: int = 0;
    has range_supported: bool = True;
    has warning: str = "";
    has size: int = 0;
    has final_url: str = "";
    has buf: bytes | None = None;   # populated only in the full-download fallback

    # Probe the asset with a HEAD request (size + Accept-Ranges) at construction.
    def postinit() -> None;

    # --- file-object protocol used by zipfile ---
    def seekable() -> bool;
    def tell() -> int;
    def seek(offset: int, whence: int = 0) -> int;
    def _ensure_full() -> None;
    def read(n: int = -1) -> bytes;
}


# Range-fetch the selected members of a remote zip into out_dir and return a
# transfer-accounting dict: members, missing_members, unsafe_members,
# bytes_fetched, full_size, range_supported, warning.
def fetch_members(
    url: str, lib_members: list[str], include_prefix: str, cmake_prefix: str,
    want_headers: bool, want_cmake: bool, out_dir: str
) -> dict;
