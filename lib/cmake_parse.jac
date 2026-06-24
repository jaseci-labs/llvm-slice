"""Parse LLVM's CMake package files to recover the inter-library dependency
graph WITHOUT executing `llvm-config`.

This is the central correctness trick of the project: `llvm-config` is a
host-arch binary we cannot run for a foreign platform on a Linux runner, but
the CMake package files under `lib/cmake/llvm/` are plain text and identical in
format across every platform LLVM ships. We read:

  * LLVMConfig.cmake        -> LLVM_AVAILABLE_LIBS (the authoritative target set),
                               LLVM_PACKAGE_VERSION, LLVM_TARGETS_TO_BUILD
  * LLVMExports.cmake       -> per-target INTERFACE_LINK_LIBRARIES (the edges)
  * LLVMExports-*.cmake     -> per-target IMPORTED_LOCATION_* (target -> file)

An edge whose name is in LLVM_AVAILABLE_LIBS is an INTERNAL dependency (resolves
to a file in this zip); anything else (`-lpthread`, `m`, `dl`, `rt`,
`ZLIB::ZLIB`, `Terminfo::terminfo`, ...) is an EXTERNAL requirement the consumer
must satisfy on their own link line, and is preserved verbatim."""

import re;
import os;
import from lib.model { LibEntry }


obj ParsedPackage {
    has version: str;
    has targets: list[str];
    has available: list[str];
    has libs: dict[str, LibEntry];
}


def _split_semicolon_list(raw: str) -> list[str] {
    out: list[str] = [];
    for piece in re.split(r"[;\s]+", raw.strip()) {
        p: str = str(piece).strip();
        if p != "" {
            out.append(p);
        }
    }
    return out;
}


def parse_version(text: str) -> str {
    m = re.search(r"set\(LLVM_PACKAGE_VERSION\s+([^)\s]+)\)", text);
    if m is None {
        return "";
    }
    return str(m.group(1)).strip();
}


def parse_available_libs(text: str) -> list[str] {
    m = re.search(r"set\(LLVM_AVAILABLE_LIBS\s+([^)]*)\)", text);
    if m is None {
        return [];
    }
    return _split_semicolon_list(str(m.group(1)));
}


def parse_targets(text: str) -> list[str] {
    m = re.search(r"set\(LLVM_TARGETS_TO_BUILD\s+([^)]*)\)", text);
    if m is None {
        return [];
    }
    return _split_semicolon_list(str(m.group(1)));
}


# target name -> ordered list of raw INTERFACE_LINK_LIBRARIES entries.
def parse_link_libraries(text: str) -> dict {
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


def _normalize_location(raw: str) -> str {
    # Drop a leading ${VAR}/ install-prefix and normalize Windows backslashes.
    p: str = re.sub(r"^\$\{[^}]*\}/", "", raw);
    return p.replace("\\", "/");
}


# target name -> path inside the install prefix (e.g. lib/libLLVMCore.a). Handles
# any config suffix (IMPORTED_LOCATION_RELEASE, _RELWITHDEBINFO, ...). The
# `[^)]*?` keeps the match inside one set_target_properties(...) block.
def parse_imported_locations(text: str) -> dict {
    out: dict = {};
    # `[^)]` matches newlines, keeping the match inside one block; no DOTALL flag.
    pat: str = r'set_target_properties\((\S+)\s+PROPERTIES[^)]*?IMPORTED_LOCATION_\w+\s+"([^"]*)"';
    for m in re.finditer(pat, text) {
        out[str(m.group(1))] = _normalize_location(str(m.group(2)));
    }
    return out;
}


# Unwrap a CMake generator expression to its inner target/flag. Installed
# LLVMExports files wrap link-only deps as `\$<LINK_ONLY:LLVMPasses>` (the `$`
# is backslash-escaped in the exported file). The inner name is what must be
# classified as internal-vs-external, otherwise internal deps reachable only
# through such an edge are dropped from the closure. Plain entries pass through.
def _unwrap_dep(raw: str) -> str {
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


# Split each available target's link entries into internal deps vs external
# requirements, and attach its on-disk file (or None if header-only).
def build_lib_entries(available: list[str], links: dict, locations: dict) -> dict {
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


def _read(path: str) -> str {
    f = open(path, "r");
    data = f.read();
    f.close();
    return str(data);
}


# A platform has a usable dev surface only if both the config and the exports
# file are present.
def has_dev_surface(cmake_llvm_dir: str) -> bool {
    cfg: bool = os.path.isfile(os.path.join(cmake_llvm_dir, "LLVMConfig.cmake"));
    exp: bool = os.path.isfile(os.path.join(cmake_llvm_dir, "LLVMExports.cmake"));
    return cfg and exp;
}


# Read every relevant CMake file in lib/cmake/llvm/ and build the fully-resolved
# package model (file sizes/sha256 are filled later by the repackager, which has
# the actual files).
def parse_cmake_dir(cmake_llvm_dir: str) -> ParsedPackage {
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
