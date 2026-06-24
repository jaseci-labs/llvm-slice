"""Parse LLVM's CMake package files to recover the inter-library dependency
graph WITHOUT executing `llvm-config`.

`llvm-config` is a host-arch binary we cannot run for a foreign platform on a
Linux runner, but the CMake package files under `lib/cmake/llvm/` are plain text
and identical across every platform LLVM ships:

  * LLVMConfig.cmake     -> LLVM_AVAILABLE_LIBS, LLVM_PACKAGE_VERSION, targets
  * LLVMExports.cmake    -> per-target INTERFACE_LINK_LIBRARIES (the edges)
  * LLVMExports-*.cmake  -> per-target IMPORTED_LOCATION_* (target -> file)

An edge in LLVM_AVAILABLE_LIBS is an INTERNAL dependency; anything else
(`-lpthread`, `ZLIB::ZLIB`, ...) is an EXTERNAL requirement, preserved verbatim.
Function bodies live in impl/cmake_parse.impl.jac."""

import re;
import os;
import from lib.model { LibEntry }


obj ParsedPackage {
    has version: str;
    has targets: list[str];
    has available: list[str];
    has libs: dict[str, LibEntry];
}


def _split_semicolon_list(raw: str) -> list[str];
def parse_version(text: str) -> str;
def parse_available_libs(text: str) -> list[str];
def parse_targets(text: str) -> list[str];

# target name -> ordered list of raw INTERFACE_LINK_LIBRARIES entries.
def parse_link_libraries(text: str) -> dict;

def _normalize_location(raw: str) -> str;

# target name -> path inside the install prefix (e.g. lib/libLLVMCore.a). Handles
# any config suffix (IMPORTED_LOCATION_RELEASE/_DEBUG/...) and the plain form.
def parse_imported_locations(text: str) -> dict;

# Unwrap a CMake generator expression (e.g. `\$<LINK_ONLY:LLVMPasses>`) to its
# inner target/flag; plain entries pass through.
def _unwrap_dep(raw: str) -> str;

# Split each available target's link entries into internal deps vs external
# requirements, and attach its on-disk file (or None if header-only).
def build_lib_entries(available: list[str], links: dict, locations: dict) -> dict;

def _read(path: str) -> str;

# A platform has a usable dev surface only if config and exports are present.
def has_dev_surface(cmake_llvm_dir: str) -> bool;

# Read every relevant CMake file in lib/cmake/llvm/ and build the package model
# (file sizes/sha256 are filled later by the repackager).
def parse_cmake_dir(cmake_llvm_dir: str) -> ParsedPackage;
