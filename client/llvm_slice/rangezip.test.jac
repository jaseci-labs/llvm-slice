"""Round-trip tests for the range reader: serve a zip over a small idiomatic-Jac
range-capable socket server and prove a single-member fetch transfers far fewer
bytes than the whole archive, plus a zip-slip guard test."""

import os;
import socket;
import threading;
import tempfile;
import zipfile;


# A minimal Range-aware HTTP/1.1 server (stdlib http.server ignores Range, and
# subclassing it from Jac is awkward, so we speak just enough HTTP over a socket).
obj RangeServer {
    has sock: socket.socket;
    has port: int;
    has zpath: str;
    has running: bool = True;

    def stop() -> None {
        self.running = False;
        self.sock.close();
    }
}


def _handle(conn: socket.socket, zpath: str) -> None {
    req: bytes = conn.recv(8192);
    text: str = req.decode("latin-1");
    lines: list[str] = text.split("\r\n");
    first: list[str] = lines[0].split(" ") if len(lines) > 0 else [];
    method: str = first[0] if len(first) > 0 else "";

    rng: str = "";
    for line in lines {
        if line.lower().startswith("range:") and "=" in line {
            rng = line.split("=")[1].strip();
        }
    }

    f = open(zpath, "rb");
    body: bytes = f.read();
    f.close();
    size: int = len(body);

    if method == "HEAD" {
        conn.sendall(f"HTTP/1.1 200 OK\r\nContent-Length: {size}\r\nAccept-Ranges: bytes\r\n\r\n".encode());
        return;
    }
    if rng != "" {
        parts: list[str] = rng.split("-");
        start: int = int(parts[0]) if parts[0] != "" else 0;
        end: int = int(parts[1]) if len(parts) > 1 and parts[1] != "" else size - 1;
        if end > size - 1 {
            end = size - 1;
        }
        chunk: bytes = body[start: end + 1];
        head: bytes = f"HTTP/1.1 206 Partial Content\r\nContent-Range: bytes {start}-{end}/{size}\r\nContent-Length: {len(chunk)}\r\nAccept-Ranges: bytes\r\n\r\n".encode();
        conn.sendall(head + chunk);
    } else {
        head2: bytes = f"HTTP/1.1 200 OK\r\nContent-Length: {size}\r\nAccept-Ranges: bytes\r\n\r\n".encode();
        conn.sendall(head2 + body);
    }
}


def _loop(srv: RangeServer) -> None {
    while srv.running {
        try {
            pair = srv.sock.accept();
        } except Exception {
            return;
        }
        conn: socket.socket = pair[0];
        try {
            _handle(conn, srv.zpath);
        } except Exception {}
        conn.close();
    }
}


def start_range_server(zpath: str) -> RangeServer {
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM);
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1);
    s.bind(("127.0.0.1", 0));
    s.listen(8);
    port: int = int(s.getsockname()[1]);
    srv: RangeServer = RangeServer(sock=s, port=port, zpath=zpath);
    t = threading.Thread(target=_loop, args=(srv,));
    t.daemon = True;
    t.start();
    return srv;
}


def _make_zip(d: str) -> str {
    zpath: str = os.path.join(d, "test.zip");
    z = zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED);
    z.writestr("lib/libSmall.a", b"x" * 1000);
    z.writestr("lib/libBig.a", os.urandom(2000000));   # incompressible, ~2MB
    z.writestr("include/foo.h", b"// header line\n" * 200);
    z.close();
    return zpath;
}


def _make_evil_zip(d: str) -> str {
    zpath: str = os.path.join(d, "evil.zip");
    z = zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED);
    z.writestr("lib/ok.a", b"ok" * 100);
    z.writestr("../escape.a", b"pwned");   # zip-slip attempt
    z.close();
    return zpath;
}


test "range fetch transfers far fewer bytes than the full archive" {
    d: str = tempfile.mkdtemp();
    zpath: str = _make_zip(d);
    full_size: int = os.path.getsize(zpath);
    srv: RangeServer = start_range_server(zpath);

    reader = HTTPRangeReader(url=f"http://127.0.0.1:{srv.port}/test.zip");
    zf = zipfile.ZipFile(reader);
    assert reader.range_supported;
    data = zf.read("lib/libSmall.a");
    assert len(data) == 1000;

    fetched: int = reader.bytes_fetched;
    assert fetched < full_size, f"fetched {fetched} should be < full {full_size}";
    assert fetched < 100000, f"fetched {fetched} should be a tiny fraction of {full_size}";
    srv.stop();
}


test "fetching a large member still works" {
    d: str = tempfile.mkdtemp();
    zpath: str = _make_zip(d);
    srv: RangeServer = start_range_server(zpath);

    reader = HTTPRangeReader(url=f"http://127.0.0.1:{srv.port}/test.zip");
    zf = zipfile.ZipFile(reader);
    names = zf.namelist();
    assert "lib/libBig.a" in names;
    big = zf.read("lib/libBig.a");
    assert len(big) == 2000000;
    srv.stop();
}


test "zip-slip path traversal is blocked" {
    d: str = tempfile.mkdtemp();
    zpath: str = _make_evil_zip(d);
    srv: RangeServer = start_range_server(zpath);
    url: str = f"http://127.0.0.1:{srv.port}/evil.zip";
    outdir: str = os.path.join(d, "extract");

    rep: dict = fetch_members(url, ["lib/ok.a", "../escape.a"], "include/", "lib/cmake/", False, False, outdir);
    unsafe: list = list(rep["unsafe_members"]);
    assert "../escape.a" in unsafe;
    assert int(rep["members"]) == 1;
    assert os.path.isfile(os.path.join(outdir, "lib", "ok.a"));
    assert not os.path.exists(os.path.join(d, "escape.a"));
    srv.stop();
}
