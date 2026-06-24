"""Implementations for scripts/repackage.jac."""

impl parse_opts(argv: list[str]) -> Opts {
    o: Opts = Opts();
    i: int = 0;
    while i < len(argv) {
        tok: str = argv[i];
        has_next: bool = (i + 1) < len(argv);
        nxt: str = argv[i + 1] if has_next else "";
        if tok == "--version" { o.version = nxt; i += 1; }
        elif tok == "--triple" { o.triple = nxt; i += 1; }
        elif tok == "--asset-url" { o.asset_url = nxt; i += 1; }
        elif tok == "--asset-name" { o.asset_name = nxt; i += 1; }
        elif tok == "--ext" { o.ext = nxt; i += 1; }
        elif tok == "--expected-sha256" { o.expected_sha256 = nxt; i += 1; }
        elif tok == "--work-dir" { o.work_dir = nxt; i += 1; }
        elif tok == "--out-dir" { o.out_dir = nxt; i += 1; }
        elif tok == "--keep-work" { o.keep_work = True; }
        i += 1;
    }
    return o;
}


impl log(msg: str) -> None {
    eprint(msg);
}


impl emit_skip(triple: str, reason: str) -> None {
    log(f"SKIP {triple}: {reason}");
    print(json.dumps({"triple": triple, "skipped": True, "reason": reason}));
}


impl prepare_tree(o: Opts) -> str {
    if o.work_dir != "" {
        return o.work_dir;
    }
    work_root: str = os.path.join(o.out_dir, "_work", o.triple);
    tree: str = os.path.join(work_root, "tree");
    os.makedirs(tree, exist_ok=True);
    tarball: str = os.path.join(work_root, f"src.{o.ext}");

    log(f"downloading {o.asset_url}");
    run(["curl", "-sSL", "-o", tarball, o.asset_url]);

    actual: str = sha256_file(tarball);
    if o.expected_sha256 != "" and actual != o.expected_sha256 {
        raise RuntimeError(f"sha256 mismatch: expected {o.expected_sha256}, got {actual}");
    }
    o.expected_sha256 = actual;   # record the verified hash

    log("extracting dev surface (lib/, include/, bin/llvm-config)");
    run([
        "tar", "-xf", tarball, "-C", tree, "--strip-components=1", "--wildcards",
        "*/lib/*", "*/include/*", "*/bin/llvm-config*"
    ]);
    os.remove(tarball);
    return tree;
}
