"""Round-trip test for the range reader: serve a zip over a local range-capable
HTTP server and prove a single-member fetch transfers far fewer bytes than the
whole archive (acceptance criterion 3)."""

import os;
import tempfile;

::py::
import http.server
import threading
import zipfile
import os as _os
import functools


class _RangeHandler(http.server.SimpleHTTPRequestHandler):
    """Minimal Range-aware static handler (stdlib's default ignores Range)."""

    def do_HEAD(self):
        path = self.translate_path(self.path)
        if not _os.path.isfile(path):
            self.send_error(404)
            return
        size = _os.path.getsize(path)
        self.send_response(200)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(size))
        self.send_header("Content-Type", "application/zip")
        self.end_headers()

    def do_GET(self):
        path = self.translate_path(self.path)
        if not _os.path.isfile(path):
            self.send_error(404)
            return
        size = _os.path.getsize(path)
        rng = self.headers.get("Range")
        with open(path, "rb") as f:
            if rng and rng.startswith("bytes="):
                start_s, _, end_s = rng[len("bytes="):].partition("-")
                start = int(start_s) if start_s else 0
                end = int(end_s) if end_s else size - 1
                end = min(end, size - 1)
                f.seek(start)
                data = f.read(end - start + 1)
                self.send_response(206)
                self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            else:
                data = f.read()
                self.send_response(200)
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Length", str(size))
                self.end_headers()
                self.wfile.write(data)

    def log_message(self, *a):
        pass


def _make_zip(dirpath):
    zpath = _os.path.join(dirpath, "test.zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("lib/libSmall.a", b"x" * 1000)
        z.writestr("lib/libBig.a", _os.urandom(2_000_000))  # incompressible, ~2MB
        z.writestr("include/foo.h", b"// header line\n" * 200)
    return zpath


def _serve(dirpath):
    handler = functools.partial(_RangeHandler, directory=dirpath)
    httpd = http.server.HTTPServer(("127.0.0.1", 0), handler)
    port = httpd.server_address[1]
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    return (httpd, port)


def _make_evil_zip(dirpath):
    zpath = _os.path.join(dirpath, "evil.zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("lib/ok.a", b"ok" * 100)
        z.writestr("../escape.a", b"pwned")  # zip-slip attempt
    return zpath
::py::


test "range fetch transfers far fewer bytes than the full archive" {
    d = tempfile.mkdtemp();
    _make_zip(d);
    full_size = os.path.getsize(os.path.join(d, "test.zip"));

    served = _serve(d);
    httpd = served[0];
    port = served[1];
    url = f"http://127.0.0.1:{port}/test.zip";

    zp = open_remote_zip(url);
    zf = zp[0];
    reader = zp[1];

    assert reader.range_supported;
    data = zf.read("lib/libSmall.a");
    assert len(data) == 1000;

    fetched = reader.bytes_fetched;
    # We fetched the central directory + one ~1KB member, never the 2MB member.
    assert fetched < full_size, f"fetched {fetched} should be < full {full_size}";
    assert fetched < 100000, f"fetched {fetched} should be a tiny fraction of {full_size}";

    httpd.shutdown();
}

test "zip-slip path traversal is blocked" {
    d = tempfile.mkdtemp();
    _make_evil_zip(d);
    served = _serve(d);
    httpd = served[0];
    port = served[1];
    url = f"http://127.0.0.1:{port}/evil.zip";
    outdir = os.path.join(d, "extract");

    rep: dict = fetch_members(url, ["lib/ok.a", "../escape.a"], "include/", "lib/cmake/", False, False, outdir);
    unsafe: list = list(rep["unsafe_members"]);
    assert "../escape.a" in unsafe;
    assert int(rep["members"]) == 1;                                   # only lib/ok.a written
    assert os.path.isfile(os.path.join(outdir, "lib", "ok.a"));
    assert not os.path.exists(os.path.join(d, "escape.a"));            # nothing escaped out_dir
    httpd.shutdown();
}

test "fetching everything still works and matches the full size ballpark" {
    d = tempfile.mkdtemp();
    _make_zip(d);
    served = _serve(d);
    httpd = served[0];
    port = served[1];
    url = f"http://127.0.0.1:{port}/test.zip";

    zp = open_remote_zip(url);
    zf = zp[0];
    names = zf.namelist();
    assert "lib/libBig.a" in names;
    assert "include/foo.h" in names;
    big = zf.read("lib/libBig.a");
    assert len(big) == 2000000;

    httpd.shutdown();
}
