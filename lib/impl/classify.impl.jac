"""Implementations for lib/classify.jac."""

impl normalize_llvm_triple(os_tok: str, arch_tok: str) -> str {
    arch: str = _ARCH_MAP[arch_tok] if arch_tok in _ARCH_MAP else arch_tok.lower();
    os_part: str = _OS_MAP[os_tok] if os_tok in _OS_MAP else os_tok.lower();
    # macOS/Windows conventions read <arch>-<os>; keep that order uniformly.
    return f"{arch}-{os_part}";
}


impl _strip_ext(name: str) -> str | None {
    if name.endswith(".tar.xz") {
        return "tar.xz";
    }
    if name.endswith(".tar.gz") {
        return "tar.gz";
    }
    return None;
}


impl classify_asset(name: str, version: str) -> AssetKind | None {
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
