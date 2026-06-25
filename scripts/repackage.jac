"""Repackage one platform's official LLVM tarball into a range-fetchable dev zip
plus a dependency manifest. Never rebuilds LLVM -- only consumes the official
artifact.

Steps: download (or reuse an extracted tree) -> verify sha256 -> stream-extract
only the dev surface (lib/, include/, bin/llvm-config) -> parse the CMake package
files -> measure each static lib -> emit manifest.json + llvm-<v>-<t>-dev.zip.

If a platform lacks a usable dev surface (no lib/cmake/llvm, or a shared-only
libLLVM with no component libs), it is SKIPPED with a recorded reason rather
than failing. Bodies live in impl/repackage.impl.jac.

Usage:
  jac run scripts/repackage.jac --version V --triple T \\
      ( --asset-url URL --ext tar.xz [--expected-sha256 SHA] | --work-dir DIR ) \\
      [--asset-name NAME] [--out-dir DIR] [--keep-work]

Prints a one-line JSON record describing the result (consumed by build_index).
Run from the repo root.
"""

import sys;
import os;
import json;
import from lib.shell { run, eprint }
import from lib.cmake_parse { parse_cmake_dir, has_dev_surface }
import from lib.pack { measure, build_dev_zip, sha256_file }
import from llvm_slice.model { Manifest, LibEntry }


obj Opts {
    has version: str = "";
    has triple: str = "";
    has asset_url: str = "";
    has asset_name: str = "";
    has ext: str = "tar.xz";
    has expected_sha256: str = "";
    has work_dir: str = "";
    has out_dir: str = "./out";
    has keep_work: bool = False;
}


def parse_opts(argv: list[str]) -> Opts;
def log(msg: str) -> None;
def emit_skip(triple: str, reason: str) -> None;

# Download + stream-extract only the dev surface into work_root/tree, returning
# that prefix directory. The tarball is removed afterward to bound disk use.
def prepare_tree(o: Opts) -> str;


with entry {
    o: Opts = parse_opts(sys.argv[1:]);
    if o.version == "" or o.triple == "" {
        log("error: --version and --triple are required");
        sys.exit(2);
    }
    if o.asset_url == "" and o.work_dir == "" {
        log("error: one of --asset-url or --work-dir is required");
        sys.exit(2);
    }
    if o.asset_name == "" {
        o.asset_name = f"clang+llvm-{o.version}-{o.triple}.{o.ext}";
    }
    os.makedirs(o.out_dir, exist_ok=True);

    prefix: str = prepare_tree(o);
    cmake_dir: str = os.path.join(prefix, "lib", "cmake", "llvm");

    if not has_dev_surface(cmake_dir) {
        emit_skip(o.triple, "no lib/cmake/llvm dev surface (LLVMConfig/LLVMExports missing)");
        sys.exit(0);
    }

    log("parsing CMake package files");
    pkg = parse_cmake_dir(cmake_dir);

    # Measure each referenced static library; drop ones absent from the tarball.
    rel_paths: list[str] = [];
    for name in pkg.libs.keys() {
        e: LibEntry = pkg.libs[name];
        if e.file is not None {
            rel_paths.append(e.file);
        }
    }
    meas: dict = measure(prefix, rel_paths);
    present: int = 0;
    for name in pkg.libs.keys() {
        e: LibEntry = pkg.libs[name];
        if e.file is not None and e.file in meas {
            info: dict = dict(meas[e.file]);
            if bool(info["missing"]) {
                e.file = None;
            } else {
                e.size = int(info["size"]);
                e.sha256 = str(info["sha256"]);
                present += 1;
            }
        }
    }

    if present == 0 {
        emit_skip(o.triple, "no static component libraries present (likely shared-only libLLVM build)");
        sys.exit(0);
    }

    zip_name: str = f"llvm-{o.version}-{o.triple}-dev.zip";
    manifest_name: str = f"llvm-{o.version}-{o.triple}-manifest.json";
    zip_path: str = os.path.join(o.out_dir, zip_name);
    manifest_path: str = os.path.join(o.out_dir, manifest_name);

    m: Manifest = Manifest(
        llvm_version=pkg.version if pkg.version != "" else o.version,
        triple=o.triple,
        zip_asset=zip_name,
        upstream_tarball=o.asset_name,
        upstream_sha256=o.expected_sha256,
        targets_to_build=pkg.targets,
        libs=pkg.libs,
    );

    # Build the zip with an embedded manifest (zip_sha256 left empty -- a zip
    # cannot contain its own hash); the standalone manifest gets the real hash.
    embedded_text: str = json.dumps(m.to_dict(), indent=2);
    log(f"building {zip_name}");
    zinfo: dict = build_dev_zip(prefix, zip_path, embedded_text);
    m.zip_sha256 = str(zinfo["sha256"]);

    wf = open(manifest_path, "w");
    wf.write(json.dumps(m.to_dict(), indent=2));
    wf.close();

    if not o.keep_work and o.work_dir == "" {
        run(["rm", "-rf", os.path.join(o.out_dir, "_work", o.triple)]);
    }

    log(f"done {o.triple}: {present} libs, zip {int(zinfo['size'])} bytes");
    print(json.dumps({
        "triple": o.triple,
        "skipped": False,
        "zip_asset": zip_name,
        "zip_sha256": m.zip_sha256,
        "zip_size": int(zinfo["size"]),
        "manifest_asset": manifest_name,
        "upstream_tarball": o.asset_name,
        "upstream_sha256": o.expected_sha256,
        "lib_count": present,
    }));
}
