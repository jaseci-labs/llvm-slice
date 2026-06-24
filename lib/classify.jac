"""Classify upstream LLVM release assets.

The official llvm-project releases publish prebuilt binaries under two naming
families, and the set varies release-to-release (which is exactly why we
discover dynamically rather than hardcoding a platform list):

  1. clang+llvm-<version>-<triple>.tar.(xz|gz)   (the long-standing convention)
       e.g. clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz
  2. LLVM-<version>-<OS>-<ARCH>.tar.xz           (newer releases, 19.x+)
       e.g. LLVM-22.1.8-Linux-X64.tar.xz, LLVM-22.1.8-macOS-ARM64.tar.xz

Everything else in a release (`.sig` signatures, `.src.tar.xz` sources,
`*-win64.exe` installers, sha files, ...) is not a repackageable dev tarball
and classify_asset returns None for it."""


obj AssetKind {
    has triple: str;
    has family: str;   # "clang+llvm" | "LLVM"
    has ext: str;      # "tar.xz" | "tar.gz"
}


# OS/ARCH tokens used by the newer `LLVM-<ver>-<OS>-<ARCH>` family, mapped to a
# conventional triple so downstream tooling sees one consistent identifier.
glob _OS_MAP: dict[str, str] = {
    "Linux": "linux",
    "macOS": "apple-darwin",
    "Windows": "pc-windows",
};
glob _ARCH_MAP: dict[str, str] = {
    "X64": "x86_64",
    "ARM64": "aarch64",
    "AArch64": "aarch64",
    "X86": "i686",
};


# Map an `LLVM-<ver>-<OS>-<ARCH>` pair to a conventional triple. Falls back to a
# lowercased `<arch>-<os>` when a token is unknown.
def normalize_llvm_triple(os_tok: str, arch_tok: str) -> str {
    arch: str = _ARCH_MAP[arch_tok] if arch_tok in _ARCH_MAP else arch_tok.lower();
    os_part: str = _OS_MAP[os_tok] if os_tok in _OS_MAP else os_tok.lower();
    # macOS/Windows conventions read <arch>-<os>; keep that order uniformly.
    return f"{arch}-{os_part}";
}


# Return the extension ("tar.xz"/"tar.gz") or None if not a tarball.
def _strip_ext(name: str) -> str | None {
    if name.endswith(".tar.xz") {
        return "tar.xz";
    }
    if name.endswith(".tar.gz") {
        return "tar.gz";
    }
    return None;
}


# Decide whether a release asset is a repackageable LLVM dev tarball, and if so,
# derive its (triple, family, ext). Returns None otherwise. Source tarballs
# (`*.src.tar.*`) are rejected even though they share a matching prefix.
def classify_asset(name: str, version: str) -> AssetKind | None {
    ext: str | None = _strip_ext(name);
    if ext is None {
        return None;
    }
    base: str = name[: len(name) - (len(ext) + 1)];  # drop ".tar.xz" / ".tar.gz"

    if base.endswith(".src") {
        return None;   # source distribution, not a binary dev surface
    }

    clang_prefix: str = f"clang+llvm-{version}-";
    if base.startswith(clang_prefix) {
        triple: str = base[len(clang_prefix):];
        if triple == "" {
            return None;
        }
        return AssetKind(triple=triple, family="clang+llvm", ext=ext);
    }

    llvm_prefix: str = f"LLVM-{version}-";
    if base.startswith(llvm_prefix) {
        rest: str = base[len(llvm_prefix):];
        parts: list[str] = rest.split("-");
        if len(parts) < 2 {
            return None;
        }
        os_tok: str = parts[0];
        arch_tok: str = "-".join(parts[1:]);
        return AssetKind(
            triple=normalize_llvm_triple(os_tok, arch_tok),
            family="LLVM",
            ext=ext,
        );
    }

    return None;
}
