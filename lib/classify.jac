"""Classify upstream LLVM release assets.

The official llvm-project releases publish prebuilt binaries under two naming
families, and the set varies release-to-release (which is exactly why we
discover dynamically rather than hardcoding a platform list):

  1. clang+llvm-<version>-<triple>.tar.(xz|gz)   (the long-standing convention)
  2. LLVM-<version>-<OS>-<ARCH>.tar.xz           (newer releases, 19.x+)

Everything else (`.sig`, `.src.tar.xz`, `*-win64.exe`, ...) is not a
repackageable dev tarball. Function bodies live in impl/classify.impl.jac."""


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
def normalize_llvm_triple(os_tok: str, arch_tok: str) -> str;

# Return the extension ("tar.xz"/"tar.gz") or None if not a tarball.
def _strip_ext(name: str) -> str | None;

# Decide whether a release asset is a repackageable LLVM dev tarball, and if so,
# derive its (triple, family, ext). Returns None otherwise. Source tarballs
# (`*.src.tar.*`) are rejected even though they share a matching prefix.
def classify_asset(name: str, version: str) -> AssetKind | None;
