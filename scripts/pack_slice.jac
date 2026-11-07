"""Pack a slice's tree as a range-fetchable zip plus its manifest, the same zip
format as the dev slices: one DEFLATE member per file and a central
directory, so a client fetches the members it needs by HTTP range requests.

  --kind runtimes   the runtimes tree (runtimes/assemble.sh's output), for
                    LLVM version V: llvm-<V>-runtimes-dev.zip and
                    llvm-<V>-runtimes-manifest.json
  --kind cpython    the CPython slice's tree (cpython/README.md), for CPython
                    version V: cpython-<V>-dev.zip and cpython-<V>-manifest.json

The manifest (docs/manifest-schema.md) lists every member's size and sha256,
so a client checks each member it fetches against a manifest it pinned by
hash.

Usage:
  jac run scripts/pack_slice.jac --kind KIND --tree DIR --version V --revision N [--out-dir DIR]

Prints the manifest's sha256 and the zip's size, the two values a client pins.
"""

import sys;
import os;
import json;
import from lib.pack { measure, build_dev_zip, sha256_file }
import from lib.shell { eprint }


with entry {
    argv: list[str] = sys.argv[1:];
    kind: str = "";
    tree: str = "";
    version: str = "";
    revision: int = 0;
    out_dir: str = "./out";
    i: int = 0;
    while i < len(argv) {
        tok: str = argv[i];
        nxt: str = argv[i + 1] if (i + 1) < len(argv) else "";
        if tok == "--kind" { kind = nxt; i += 1; }
        elif tok == "--tree" { tree = nxt; i += 1; }
        elif tok == "--version" { version = nxt; i += 1; }
        elif tok == "--revision" { revision = int(nxt); i += 1; }
        elif tok == "--out-dir" { out_dir = nxt; i += 1; }
        i += 1;
    }
    if kind not in ["runtimes", "cpython"] or tree == "" or version == "" or revision < 1 {
        eprint("usage: pack_slice.jac --kind runtimes|cpython --tree DIR --version V --revision N [--out-dir DIR]");
        sys.exit(2);
    }
    # The assets' names, and the manifest's field naming the version.
    stem: str = f"llvm-{version}-runtimes" if kind == "runtimes" else f"cpython-{version}";
    version_key: str = "llvm_version" if kind == "runtimes" else "cpython_version";

    rels: list[str] = [];
    for walked in os.walk(tree) {
        for fn in walked[2] {
            full: str = os.path.join(str(walked[0]), str(fn));
            rels.append(os.path.relpath(full, tree).replace(os.sep, "/"));
        }
    }
    rels.sort();
    measured: dict[str, dict] = measure(tree, rels);
    files: dict[str, dict] = {};
    for rel in rels {
        m: dict[str, object] = dict(measured[rel]);
        files[rel] = {"size": m["size"], "sha256": m["sha256"]};
    }

    zip_name: str = f"{stem}-dev.zip";
    manifest: dict[str, object] = {
        "schema_version": 1,
        "kind": kind,
        version_key: version,
        "revision": revision,
        "zip_asset": zip_name,
        "zip_sha256": "",
        "files": files,
    };
    os.makedirs(out_dir, exist_ok=True);
    zip_path: str = os.path.join(out_dir, zip_name);
    z: dict[str, object] = build_dev_zip(tree, zip_path, json.dumps(manifest, indent=2, sort_keys=True));
    manifest["zip_sha256"] = z["sha256"];
    man_path: str = os.path.join(out_dir, f"{stem}-manifest.json");
    with open(man_path, "w") as f {
        f.write(json.dumps(manifest, indent=2, sort_keys=True));
    }
    print(json.dumps({
        "zip_asset": zip_name,
        "zip_size": z["size"],
        "zip_sha256": z["sha256"],
        "manifest_sha256": sha256_file(man_path),
        "files": len(rels),
    }));
}
