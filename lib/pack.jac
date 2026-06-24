"""File measurement and reproducible-ish zip building for the repackager.
Bodies live in impl/pack.impl.jac."""

import os;
import hashlib;
import zipfile;


# Fixed timestamp so re-runs of the same input produce identical zips.
glob _FIXED_TIME: tuple = (1980, 1, 1, 0, 0, 0);


# sha256 hex digest of a file.
def sha256_file(path: str) -> str;

# Measure size + sha256 for each relative path under work_dir. Returns a dict
# rel_path -> {size, sha256, missing}.
def measure(work_dir: str, rel_paths: list[str]) -> dict;

# Build a reproducible dev zip of the whole work_dir tree plus an embedded
# manifest.json, skipping dangling/escaping symlinks. Returns {size, sha256,
# skipped_symlinks} of the produced zip.
def build_dev_zip(work_dir: str, out_zip: str, manifest_text: str) -> dict;
