"""Range-fetch individual members out of a remote ZIP.

A ZIP central directory lets an HTTP client pull single members without
downloading the whole archive -- the entire reason this project repackages
tar.xz into zip. We lean on the stdlib `zipfile` (which parses the central
directory and inflates) and supply only the minimal piece it needs: a seekable
file object whose reads are served by HTTP Range requests. This keeps the
client dependency-light (no remotezip/unzip-http needed) while still doing real
partial fetches.

GitHub release-asset downloads redirect to a CDN that supports byte ranges; the
reader verifies `Accept-Ranges: bytes` up front and, if a mirror ever lacks it,
falls back to a single full download (recording a warning) so correctness never
depends on range support."""

::py::
import urllib.request
import zipfile


class HTTPRangeReader:
    """A seekable, read-only file object backed by HTTP Range requests.

    Tracks `bytes_fetched` (bytes actually transferred) vs `size` (the full
    asset length) so callers can prove a partial fetch moved fewer bytes than a
    full download."""

    def __init__(self, url, timeout=60):
        self.url = url
        self.timeout = timeout
        self.pos = 0
        self.bytes_fetched = 0
        self.range_supported = True
        self.warning = ""
        self._buf = None  # populated only in the full-download fallback

        try:
            req = urllib.request.Request(url, method="HEAD")
            with urllib.request.urlopen(req, timeout=timeout) as r:
                self.final_url = r.geturl()
                self.size = int(r.headers.get("Content-Length", "0") or 0)
                accept = (r.headers.get("Accept-Ranges", "") or "").lower()
                self.range_supported = (accept == "bytes")
        except Exception as e:
            self.final_url = url
            self.size = 0
            self.range_supported = False
            self.warning = "HEAD request failed: " + str(e)

        if self.size <= 0:
            self.range_supported = False
            if not self.warning:
                self.warning = "server did not report Content-Length"

    # --- file-object protocol used by zipfile ---
    def seekable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, offset, whence=0):
        if whence == 0:
            self.pos = offset
        elif whence == 1:
            self.pos = self.pos + offset
        elif whence == 2:
            self.pos = self.size + offset
        return self.pos

    def _ensure_full(self):
        if self._buf is None:
            with urllib.request.urlopen(self.final_url, timeout=self.timeout) as r:
                data = r.read()
            self._buf = data
            self.size = len(data)
            self.bytes_fetched += len(data)

    def read(self, n=-1):
        if not self.range_supported:
            self._ensure_full()
            if n is None or n < 0:
                chunk = self._buf[self.pos:]
            else:
                chunk = self._buf[self.pos:self.pos + n]
            self.pos += len(chunk)
            return chunk

        if n is None or n < 0:
            end = self.size - 1
        else:
            end = min(self.pos + n - 1, self.size - 1)
        if self.size <= 0 or end < self.pos:
            return b""
        # Accumulate until the full requested range is satisfied: a server may
        # legitimately return a 206 shorter than requested, which would otherwise
        # misalign zipfile's view of the stream.
        chunks = []
        cur = self.pos
        while cur <= end:
            req = urllib.request.Request(self.final_url, headers={"Range": "bytes=%d-%d" % (cur, end)})
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                part = r.read()
            if not part:
                break
            chunks.append(part)
            self.bytes_fetched += len(part)
            cur += len(part)
        data = b"".join(chunks)
        self.pos += len(data)
        return data


def _open(url):
    reader = HTTPRangeReader(url)
    zf = zipfile.ZipFile(reader)
    return (zf, reader)


def _fetch_slice_py(url, lib_members, include_prefix, cmake_prefix, want_headers, want_cmake, out_dir):
    """Open the remote zip, select the requested library members (plus optional
    include/ and lib/cmake/ trees), range-fetch only those, and write them under
    out_dir preserving zip-internal paths. Returns transfer accounting."""
    import os as _os
    reader = HTTPRangeReader(url)
    zf = zipfile.ZipFile(reader)
    names = zf.namelist()

    selected, seen = [], set()
    for m in lib_members:
        if m and m not in seen:
            selected.append(m)
            seen.add(m)
    if want_headers or want_cmake:
        for n in names:
            if n.endswith("/"):
                continue
            hit = (want_headers and n.startswith(include_prefix)) or (want_cmake and n.startswith(cmake_prefix))
            if hit and n not in seen:
                selected.append(n)
                seen.add(n)

    _os.makedirs(out_dir, exist_ok=True)
    out_root = _os.path.realpath(out_dir)
    written, missing, unsafe = 0, [], []
    for m in selected:
        # Guard against zip-slip: a malicious member name like "../../etc/x" must
        # never escape out_dir.
        dest = _os.path.normpath(_os.path.join(out_dir, *m.split("/")))
        real_dest = _os.path.realpath(dest)
        if real_dest != out_root and not real_dest.startswith(out_root + _os.sep):
            unsafe.append(m)
            continue
        try:
            data = zf.read(m)
        except KeyError:
            missing.append(m)
            continue
        parent = _os.path.dirname(dest)
        if parent:
            _os.makedirs(parent, exist_ok=True)
        with open(dest, "wb") as f:
            f.write(data)
        written += 1

    return {
        "members": written,
        "missing_members": missing,
        "unsafe_members": unsafe,
        "bytes_fetched": reader.bytes_fetched,
        "full_size": reader.size,
        "range_supported": reader.range_supported,
        "warning": reader.warning,
    }
::py::


# Open a remote zip and return (ZipFile, HTTPRangeReader). The reader exposes
# `.size`, `.bytes_fetched`, `.range_supported`, `.warning`. The pair crosses the
# Python boundary, so it is typed Any for callers to unpack.
def open_remote_zip(url: str) -> Any {
    pair: Any = _open(url);
    return pair;
}


# Range-fetch the selected members of a remote zip into out_dir and return a
# transfer-accounting dict: members, missing_members, bytes_fetched, full_size,
# range_supported, warning. All zipfile interaction stays inside Python.
def fetch_members(
    url: str, lib_members: list[str], include_prefix: str, cmake_prefix: str,
    want_headers: bool, want_cmake: bool, out_dir: str
) -> dict {
    rep: dict = dict(_fetch_slice_py(
        url, lib_members, include_prefix, cmake_prefix, want_headers, want_cmake, out_dir
    ));
    return rep;
}
