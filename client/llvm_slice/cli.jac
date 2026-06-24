"""llvm-slice: fetch only the LLVM static libraries you link.

  llvm-slice list    --version V --triple T
  llvm-slice resolve --version V --triple T --libs LLVMOrcJIT,LLVMX86CodeGen
  llvm-slice fetch   --version V --triple T --libs ... [--headers] [--cmake] -o DIR

Run from the repo root:  jac run client/llvm_slice/cli.jac <subcommand> ...
Asset source defaults to the GitHub releases of jaseci-labs/llvm-slice; override
the repo with --repo or env LLVM_SLICE_REPO, or point --base-url at a local
directory served over http:// (or file://) for testing.

Args are parsed by hand (rather than argparse) because the stdlib argparse
objects surface as untyped at the Jac boundary; a small typed parser keeps the
whole CLI strictly typed."""

import sys;
import from client.llvm_slice.fetcher { load_manifest, fetch_slice }
import from client.llvm_slice.resolve { resolve_closure }


obj Args {
    has cmd: str = "";
    has version: str = "";
    has triple: str = "";
    has repo: str = "";
    has base_url: str = "";
    has libs: str = "";
    has out: str = "./out";
    has headers: bool = False;
    has cmake: bool = False;
    has ok: bool = True;
    has error: str = "";
}


def _split_libs(s: str) -> list[str] {
    out: list[str] = [];
    for p in s.split(",") {
        v: str = p.strip();
        if v != "" {
            out.append(v);
        }
    }
    return out;
}


def _pct(part: int, whole: int) -> str {
    if whole <= 0 {
        return "n/a";
    }
    val: float = 100.0 * float(part) / float(whole);
    return f"{val:.2f}%";
}


def parse_args(argv: list[str]) -> Args {
    a: Args = Args();
    if len(argv) == 0 {
        a.ok = False;
        a.error = "no subcommand given";
        return a;
    }
    a.cmd = argv[0];
    i: int = 1;
    while i < len(argv) {
        tok: str = argv[i];
        has_next: bool = (i + 1) < len(argv);
        nxt: str = argv[i + 1] if has_next else "";
        if tok == "--version" {
            a.version = nxt; i += 1;
        } elif tok == "--triple" {
            a.triple = nxt; i += 1;
        } elif tok == "--repo" {
            a.repo = nxt; i += 1;
        } elif tok == "--base-url" {
            a.base_url = nxt; i += 1;
        } elif tok == "--libs" {
            a.libs = nxt; i += 1;
        } elif tok == "-o" or tok == "--out" {
            a.out = nxt; i += 1;
        } elif tok == "--headers" {
            a.headers = True;
        } elif tok == "--cmake" {
            a.cmake = True;
        } else {
            a.ok = False;
            a.error = "unknown argument: " + tok;
            return a;
        }
        i += 1;
    }
    return a;
}


def _require_common(a: Args) -> bool {
    if a.version == "" or a.triple == "" {
        print("error: --version and --triple are required");
        return False;
    }
    return True;
}


def cmd_list(a: Args) -> int {
    if not _require_common(a) {
        return 2;
    }
    fm = load_manifest(a.version, a.triple, a.repo, a.base_url);
    print(f"LLVM {fm.version}  {fm.triple}  ({len(fm.libs)} libraries)");
    for name in sorted(fm.libs.keys()) {
        e = fm.libs[name];
        marker: str = e.file if e.file is not None else "(header-only)";
        print(f"  {name}  ->  {marker}");
    }
    return 0;
}


def cmd_resolve(a: Args) -> int {
    if not _require_common(a) {
        return 2;
    }
    if a.libs == "" {
        print("error: --libs is required for resolve");
        return 2;
    }
    fm = load_manifest(a.version, a.triple, a.repo, a.base_url);
    roots: list[str] = _split_libs(a.libs);
    res = resolve_closure(fm.libs, roots);
    if len(res.missing) > 0 {
        print("WARNING: requested libs not in manifest: " + ", ".join(res.missing));
    }
    print(f"closure: {len(res.closure)} libraries (static link order, dependents first)");
    print("  " + " ".join(res.closure));
    print(f"external link requirements: {len(res.external)}");
    print("  " + " ".join(res.external));
    return 0;
}


def cmd_fetch(a: Args) -> int {
    if not _require_common(a) {
        return 2;
    }
    if a.libs == "" {
        print("error: --libs is required for fetch");
        return 2;
    }
    roots: list[str] = _split_libs(a.libs);
    rep = fetch_slice(
        a.version, a.triple, a.repo, a.base_url,
        roots, a.headers, a.cmake, a.out
    );
    if len(rep.missing) > 0 {
        print("WARNING: requested libs not in manifest: " + ", ".join(rep.missing));
    }
    if not rep.range_supported {
        print("WARNING: server did not support range requests; downloaded the full zip. " + rep.warning);
    }
    print(f"fetched {rep.members} members ({len(rep.closure)} libs in closure) -> {a.out}");
    print(f"transferred {rep.bytes_fetched} of {rep.full_size} bytes ({_pct(rep.bytes_fetched, rep.full_size)} of the full zip)");
    if len(rep.external) > 0 {
        print("external link requirements: " + " ".join(rep.external));
    }
    return 0;
}


def usage() -> None {
    print("usage: llvm-slice <list|resolve|fetch> --version V --triple T [options]");
    print("  list     --version V --triple T");
    print("  resolve  --version V --triple T --libs A,B,C");
    print("  fetch    --version V --triple T --libs A,B,C [--headers] [--cmake] -o DIR");
    print("options: --repo owner/name | --base-url URL");
}


with entry {
    a: Args = parse_args(sys.argv[1:]);
    rc: int = 0;
    if not a.ok {
        print("error: " + a.error);
        usage();
        rc = 2;
    } elif a.cmd == "list" {
        rc = cmd_list(a);
    } elif a.cmd == "resolve" {
        rc = cmd_resolve(a);
    } elif a.cmd == "fetch" {
        rc = cmd_fetch(a);
    } else {
        usage();
        rc = 2;
    }
    sys.exit(rc);
}
