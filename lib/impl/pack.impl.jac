"""Implementations for lib/pack.jac (sees its os/hashlib/zipfile imports)."""

impl sha256_file(path: str) -> str {
    h = hashlib.sha256();
    f = open(path, "rb");
    while True {
        chunk: bytes = f.read(1048576);
        if len(chunk) == 0 {
            break;
        }
        h.update(chunk);
    }
    f.close();
    return str(h.hexdigest());
}


impl measure(work_dir: str, rel_paths: list[str]) -> dict {
    out: dict = {};
    for rp in rel_paths {
        full: str = os.path.join(work_dir, rp);
        if os.path.isfile(full) {
            out[rp] = {"size": os.path.getsize(full), "sha256": sha256_file(full), "missing": False};
        } else {
            out[rp] = {"size": 0, "sha256": "", "missing": True};
        }
    }
    return out;
}


impl build_dev_zip(work_dir: str, out_zip: str, manifest_text: str) -> dict {
    workroot: str = os.path.realpath(work_dir);
    skipped: int = 0;
    # Collect (rel, full); sorting by the tuple sorts by rel for a stable order.
    entries: list[tuple] = [];
    for walked in os.walk(work_dir) {
        dir_root: str = str(walked[0]);
        files = walked[2];
        for fn in files {
            full: str = os.path.join(dir_root, str(fn));
            # Some LLVM packages ship symlinks (e.g. lib/python*/lldb/* -> bin/*)
            # whose targets we don't extract. Skip dangling symlinks, and skip
            # symlinks resolving outside the tree so we never capture host files.
            if os.path.islink(full) {
                real: str = os.path.realpath(full);
                if not (real == workroot or real.startswith(workroot + os.sep)) {
                    skipped += 1;
                    continue;
                }
            }
            if not os.path.isfile(full) {
                skipped += 1;
                continue;
            }
            rel: str = os.path.relpath(full, work_dir).replace(os.sep, "/");
            entries.append((rel, full));
        }
    }
    entries.sort();

    zf = zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=6);
    for e in entries {
        rel_e: str = str(e[0]);
        full_e: str = str(e[1]);
        zi = zipfile.ZipInfo(rel_e, date_time=_FIXED_TIME);
        zi.compress_type = int(zipfile.ZIP_DEFLATED);
        rf = open(full_e, "rb");
        zf.writestr(zi, rf.read());
        rf.close();
    }
    mzi = zipfile.ZipInfo("manifest.json", date_time=_FIXED_TIME);
    mzi.compress_type = int(zipfile.ZIP_DEFLATED);
    zf.writestr(mzi, manifest_text);
    zf.close();

    return {"size": os.path.getsize(out_zip), "sha256": sha256_file(out_zip), "skipped_symlinks": skipped};
}
