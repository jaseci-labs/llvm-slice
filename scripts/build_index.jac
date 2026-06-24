"""Assemble a release-level index.json from the per-platform repackage records.

Reads the newline-delimited JSON records emitted by repackage.jac (one per
platform, including skips) from a file or stdin and produces:

  {"schema_version": 1, "llvm_version": V, "generated_at": ISO,
   "platforms": [ {triple, zip_asset, zip_sha256, zip_size, manifest_asset,
                   upstream_tarball, upstream_sha256, lib_count}, ... ],
   "skipped":   [ {triple, reason}, ... ]}

Usage:
  jac run scripts/build_index.jac --version V [--records records.jsonl] [-o index.json]
  cat records.jsonl | jac run scripts/build_index.jac --version V
"""

import sys;
import json;
import from lib.model { utc_now_iso }
import from lib.shell { stdin_read }


def _read_records(path: str) -> list[str] {
    if path == "" {
        return stdin_read().splitlines();
    }
    f = open(path, "r");
    data: str = str(f.read());
    f.close();
    return data.splitlines();
}


with entry {
    argv: list[str] = sys.argv[1:];
    version: str = "";
    records_path: str = "";
    out_path: str = "";
    i: int = 0;
    while i < len(argv) {
        tok: str = argv[i];
        has_next: bool = (i + 1) < len(argv);
        nxt: str = argv[i + 1] if has_next else "";
        if tok == "--version" { version = nxt; i += 1; }
        elif tok == "--records" { records_path = nxt; i += 1; }
        elif tok == "-o" or tok == "--out" { out_path = nxt; i += 1; }
        i += 1;
    }

    platforms: list = [];
    skipped: list = [];
    for line in _read_records(records_path) {
        s: str = line.strip();
        if s == "" {
            continue;
        }
        rec: dict = dict(json.loads(s));
        if "skipped" in rec and bool(rec["skipped"]) {
            skipped.append({"triple": str(rec["triple"]), "reason": str(rec["reason"]) if "reason" in rec else ""});
        } else {
            platforms.append(rec);
        }
    }

    index: dict = {
        "schema_version": 1,
        "llvm_version": version,
        "generated_at": utc_now_iso(),
        "platforms": platforms,
        "skipped": skipped,
    };
    text: str = json.dumps(index, indent=2);

    if out_path != "" {
        wf = open(out_path, "w");
        wf.write(text);
        wf.close();
    }
    print(text);
}
