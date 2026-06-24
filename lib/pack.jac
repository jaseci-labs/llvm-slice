"""File measurement and reproducible-ish zip building for the repackager.

Hashing, stat, and zip construction live in a `::py::` block (stdlib file/zip
objects are untyped at the Jac boundary); the exposed Jac functions take and
return plain typed values."""

::py::
import os
import hashlib
import zipfile

_FIXED_TIME = (1980, 1, 1, 0, 0, 0)


def _sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _measure(work_dir, rel_paths):
    out = {}
    for rp in rel_paths:
        full = os.path.join(work_dir, *rp.split("/"))
        if os.path.isfile(full):
            out[rp] = {"size": os.path.getsize(full), "sha256": _sha256_file(full), "missing": False}
        else:
            out[rp] = {"size": 0, "sha256": "", "missing": True}
    return out


def _build_dev_zip(work_dir, out_zip, manifest_text):
    # Deterministic ordering + fixed timestamps so re-runs of the same input
    # produce byte-identical archives.
    workroot = os.path.realpath(work_dir)
    skipped = 0
    entries = []
    for root, dirs, files in os.walk(work_dir):
        dirs.sort()
        for fn in files:
            full = os.path.join(root, fn)
            # Some LLVM packages ship symlinks (e.g. lib/python*/lldb/* -> bin/*)
            # whose targets we don't extract. Skip dangling symlinks, and skip
            # symlinks resolving outside the tree so we never capture host files.
            if os.path.islink(full):
                real = os.path.realpath(full)
                if not (real == workroot or real.startswith(workroot + os.sep)):
                    skipped += 1
                    continue
            if not os.path.isfile(full):
                skipped += 1
                continue
            rel = os.path.relpath(full, work_dir).replace(os.sep, "/")
            entries.append((full, rel))
    entries.sort(key=lambda x: x[1])

    with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for full, rel in entries:
            zi = zipfile.ZipInfo(rel, date_time=_FIXED_TIME)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = (0o644 & 0xFFFF) << 16
            with open(full, "rb") as f:
                z.writestr(zi, f.read())
        mzi = zipfile.ZipInfo("manifest.json", date_time=_FIXED_TIME)
        mzi.compress_type = zipfile.ZIP_DEFLATED
        mzi.external_attr = (0o644 & 0xFFFF) << 16
        z.writestr(mzi, manifest_text)

    return {"size": os.path.getsize(out_zip), "sha256": _sha256_file(out_zip), "skipped_symlinks": skipped}
::py::


# sha256 hex digest of a file.
def sha256_file(path: str) -> str {
    return str(_sha256_file(path));
}


# Measure size + sha256 for each relative path under work_dir. Returns a dict
# rel_path -> {size, sha256, missing}.
def measure(work_dir: str, rel_paths: list[str]) -> dict {
    return dict(_measure(work_dir, rel_paths));
}


# Build a reproducible dev zip of the whole work_dir tree plus an embedded
# manifest.json. Returns {size, sha256} of the produced zip.
def build_dev_zip(work_dir: str, out_zip: str, manifest_text: str) -> dict {
    return dict(_build_dev_zip(work_dir, out_zip, manifest_text));
}
