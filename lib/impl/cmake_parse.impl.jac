"""Implementations for lib/cmake_parse.jac (sees its `re`, `os`, LibEntry imports)."""

impl _split_semicolon_list(raw: str) -> list[str] {
    out: list[str] = [];
    for piece in re.split(r"[;\s]+", raw.strip()) {
        p: str = str(piece).strip();
        if p != "" {
            out.append(p);
        }
    }
    return out;
}


impl parse_version(text: str) -> str {
    m = re.search(r"set\(LLVM_PACKAGE_VERSION\s+([^)\s]+)\)", text);
    if m is None {
        return "";
    }
    return str(m.group(1)).strip();
}


impl parse_available_libs(text: str) -> list[str] {
    m = re.search(r"set\(LLVM_AVAILABLE_LIBS\s+([^)]*)\)", text);
    if m is None {
        return [];
    }
    return _split_semicolon_list(str(m.group(1)));
}


impl parse_targets(text: str) -> list[str] {
    m = re.search(r"set\(LLVM_TARGETS_TO_BUILD\s+([^)]*)\)", text);
    if m is None {
        return [];
    }
    return _split_semicolon_list(str(m.group(1)));
}


impl parse_link_libraries(text: str) -> dict {
    out: dict = {};
    # `\s+` already spans the newline between PROPERTIES and the property, so no
    # DOTALL flag is needed (and passing one trips Jac's overload resolution).
    pat: str = r'set_target_properties\((\S+)\s+PROPERTIES\s+INTERFACE_LINK_LIBRARIES\s+"([^"]*)"';
    for m in re.finditer(pat, text) {
        target: str = str(m.group(1));
        entries: list[str] = [];
        for e in str(m.group(2)).split(";") {
            v: str = e.strip();
            if v != "" {
                entries.append(v);
            }
        }
        out[target] = entries;
    }
    return out;
}


impl _normalize_location(raw: str) -> str {
    # Normalize Windows backslashes FIRST, then drop a leading ${VAR}/ prefix --
    # otherwise a `${_IMPORT_PREFIX}\lib\X.lib` path would not match the stripper.
    p: str = raw.replace("\\", "/");
    return re.sub(r"^\$\{[^}]*\}/", "", p);
}


impl parse_imported_locations(text: str) -> dict {
    out: dict = {};
    # `[^)]` matches newlines, keeping the match inside one block; no DOTALL flag.
    # The config suffix is optional: match IMPORTED_LOCATION_RELEASE/_DEBUG/... AND
    # the plain config-independent IMPORTED_LOCATION.
    pat: str = r'set_target_properties\((\S+)\s+PROPERTIES[^)]*?IMPORTED_LOCATION(?:_\w+)?\s+"([^"]*)"';
    for m in re.finditer(pat, text) {
        out[str(m.group(1))] = _normalize_location(str(m.group(2)));
    }
    return out;
}


impl _unwrap_dep(raw: str) -> str {
    s: str = raw;
    if s.startswith("\\") {
        s = s[1:];
    }
    m = re.search(r"^\$<[A-Za-z_]+:(.+)>$", s);
    if m is not None {
        return str(m.group(1)).strip();
    }
    return raw;
}


impl build_lib_entries(available: list[str], links: dict, locations: dict) -> dict {
    avail_set: set = set(available);
    out: dict = {};
    for name in available {
        raw_deps = links[name] if name in links else [];
        deps: list[str] = [];
        external: list[str] = [];
        for d_any in raw_deps {
            d: str = _unwrap_dep(str(d_any));
            if d in avail_set {
                if d not in deps {
                    deps.append(d);
                }
            } else {
                if d not in external {
                    external.append(d);
                }
            }
        }
        loc_v = locations[name] if name in locations else None;
        file_val: str | None = str(loc_v) if loc_v is not None else None;
        out[name] = LibEntry(name=name, file=file_val, deps=deps, external=external);
    }
    return out;
}


impl _read(path: str) -> str {
    f = open(path, "r");
    data = f.read();
    f.close();
    return str(data);
}


impl has_dev_surface(cmake_llvm_dir: str) -> bool {
    cfg: bool = os.path.isfile(os.path.join(cmake_llvm_dir, "LLVMConfig.cmake"));
    exp: bool = os.path.isfile(os.path.join(cmake_llvm_dir, "LLVMExports.cmake"));
    return cfg and exp;
}


impl parse_cmake_dir(cmake_llvm_dir: str) -> ParsedPackage {
    config_text: str = _read(os.path.join(cmake_llvm_dir, "LLVMConfig.cmake"));
    exports_text: str = _read(os.path.join(cmake_llvm_dir, "LLVMExports.cmake"));

    available: list[str] = parse_available_libs(config_text);
    links: dict = parse_link_libraries(exports_text);

    locations: dict = {};
    for fn in sorted(os.listdir(cmake_llvm_dir)) {
        if fn.startswith("LLVMExports-") and fn.endswith(".cmake") {
            loc: dict = parse_imported_locations(_read(os.path.join(cmake_llvm_dir, fn)));
            for k in loc.keys() {
                if k not in locations {
                    locations[k] = loc[k];
                }
            }
        }
    }

    return ParsedPackage(
        version=parse_version(config_text),
        targets=parse_targets(config_text),
        available=available,
        libs=build_lib_entries(available, links, locations),
    );
}
