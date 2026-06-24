"""Implementations for client/llvm_slice/rangezip.jac."""

impl HTTPRangeReader.postinit() -> None {
    self.final_url = self.url;
    try {
        req = Request(self.url, method="HEAD");
        r = urlopen(req, timeout=self.timeout);
        self.final_url = str(r.geturl());
        cl = r.headers.get("Content-Length", "0");
        self.size = int(cl) if cl is not None else 0;
        ar = r.headers.get("Accept-Ranges", "");
        self.range_supported = str(ar).lower() == "bytes" if ar is not None else False;
        r.close();
    } except Exception as e {
        self.size = 0;
        self.range_supported = False;
        self.warning = "HEAD request failed: " + str(e);
    }
    if self.size <= 0 {
        self.range_supported = False;
        if self.warning == "" {
            self.warning = "server did not report Content-Length";
        }
    }
}


impl HTTPRangeReader.seekable() -> bool {
    return True;
}


impl HTTPRangeReader.tell() -> int {
    return self.pos;
}


impl HTTPRangeReader.seek(offset: int, whence: int = 0) -> int {
    if whence == 0 {
        self.pos = offset;
    } elif whence == 1 {
        self.pos = self.pos + offset;
    } else {
        self.pos = self.size + offset;
    }
    return self.pos;
}


impl HTTPRangeReader._ensure_full() -> None {
    if self.buf is None {
        r = urlopen(self.final_url, timeout=self.timeout);
        data: bytes = bytes(r.read());
        r.close();
        self.buf = data;
        self.size = len(data);
        self.bytes_fetched = self.bytes_fetched + len(data);
    }
}


impl HTTPRangeReader.read(n: int = -1) -> bytes {
    if not self.range_supported {
        self._ensure_full();
        b: bytes = self.buf if self.buf is not None else b"";
        chunk: bytes = b[self.pos:] if n < 0 else b[self.pos: self.pos + n];
        self.pos = self.pos + len(chunk);
        return chunk;
    }
    end: int = self.size - 1 if n < 0 else min(self.pos + n - 1, self.size - 1);
    if self.size <= 0 or end < self.pos {
        return b"";
    }
    # Accumulate until the full requested range is satisfied: a server may
    # legitimately return a 206 shorter than requested, which would otherwise
    # misalign zipfile's view of the stream.
    parts: list[bytes] = [];
    cur: int = self.pos;
    while cur <= end {
        req = Request(self.final_url, headers={"Range": f"bytes={cur}-{end}"});
        r = urlopen(req, timeout=self.timeout);
        part: bytes = bytes(r.read());
        r.close();
        if len(part) == 0 {
            break;
        }
        parts.append(part);
        self.bytes_fetched = self.bytes_fetched + len(part);
        cur = cur + len(part);
    }
    data: bytes = b"".join(parts);
    self.pos = self.pos + len(data);
    return data;
}


impl fetch_members(
    url: str, lib_members: list[str], include_prefix: str, cmake_prefix: str,
    want_headers: bool, want_cmake: bool, out_dir: str
) -> dict {
    reader = HTTPRangeReader(url=url);
    zf = zipfile.ZipFile(reader);
    names = zf.namelist();

    selected: list[str] = [];
    seen: set = set();
    for m in lib_members {
        if m != "" and m not in seen {
            selected.append(m);
            seen.add(m);
        }
    }
    if want_headers or want_cmake {
        for nm in names {
            n: str = str(nm);
            if n.endswith("/") {
                continue;
            }
            hit: bool = (want_headers and n.startswith(include_prefix)) or (want_cmake and n.startswith(cmake_prefix));
            if hit and n not in seen {
                selected.append(n);
                seen.add(n);
            }
        }
    }

    os.makedirs(out_dir, exist_ok=True);
    out_root: str = os.path.realpath(out_dir);
    written: int = 0;
    missing: list[str] = [];
    unsafe: list[str] = [];
    for m in selected {
        # Guard against zip-slip: a member like "../../etc/x" must not escape out_dir.
        native: str = m.replace("/", os.sep);
        dest: str = os.path.normpath(os.path.join(out_dir, native));
        real_dest: str = os.path.realpath(dest);
        if real_dest != out_root and not real_dest.startswith(out_root + os.sep) {
            unsafe.append(m);
            continue;
        }
        try {
            data: bytes = zf.read(m);
        } except KeyError {
            missing.append(m);
            continue;
        }
        parent: str = os.path.dirname(dest);
        if parent != "" {
            os.makedirs(parent, exist_ok=True);
        }
        wf = open(dest, "wb");
        wf.write(data);
        wf.close();
        written += 1;
    }

    return {
        "members": written,
        "missing_members": missing,
        "unsafe_members": unsafe,
        "bytes_fetched": reader.bytes_fetched,
        "full_size": reader.size,
        "range_supported": reader.range_supported,
        "warning": reader.warning,
    };
}
