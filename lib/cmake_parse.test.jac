"""Tests for the CMake parser, using fixtures that mirror the exact text of
real LLVM 18.1.8 package files (verified against the upstream tarball)."""

glob CONFIG_TEXT: str = """
set(LLVM_VERSION_MAJOR 18)
set(LLVM_VERSION_MINOR 1)
set(LLVM_VERSION_PATCH 8)
set(LLVM_PACKAGE_VERSION 18.1.8)
set(LLVM_AVAILABLE_LIBS LLVMDemangle;LLVMSupport;LLVMBinaryFormat;LLVMRemarks;LLVMTargetParser;LLVMCore;LLVMHeaderOnly)
set(LLVM_TARGETS_TO_BUILD AArch64;ARM;X86)
set(LLVM_INCLUDE_DIRS "${LLVM_INSTALL_PREFIX}/include")
""";

glob EXPORTS_TEXT: str = """
# Create imported target LLVMDemangle
add_library(LLVMDemangle STATIC IMPORTED)

# Create imported target LLVMSupport
add_library(LLVMSupport STATIC IMPORTED)

set_target_properties(LLVMSupport PROPERTIES
  INTERFACE_LINK_LIBRARIES "rt;dl;-lpthread;m;ZLIB::ZLIB;Terminfo::terminfo;LLVMDemangle"
)

# Create imported target llvm-tblgen
add_executable(llvm-tblgen IMPORTED)

# Create imported target LLVMCore
add_library(LLVMCore STATIC IMPORTED)

set_target_properties(LLVMCore PROPERTIES
  INTERFACE_LINK_LIBRARIES "-lpthread;LLVMBinaryFormat;LLVMDemangle;LLVMRemarks;LLVMSupport;LLVMTargetParser"
)
""";

glob RELEASE_TEXT: str = """
# Import target "LLVMDemangle" for configuration "Release"
set_property(TARGET LLVMDemangle APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(LLVMDemangle PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_RELEASE "CXX"
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/lib/libLLVMDemangle.a"
  )

# Import target "LLVMCore" for configuration "Release"
set_property(TARGET LLVMCore APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(LLVMCore PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_RELEASE "CXX"
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/lib/libLLVMCore.a"
  )
""";


test "version parses" {
    assert parse_version(CONFIG_TEXT) == "18.1.8";
}

test "available libs parse" {
    libs = parse_available_libs(CONFIG_TEXT);
    assert "LLVMCore" in libs;
    assert "LLVMSupport" in libs;
    assert len(libs) == 7;
}

test "targets parse" {
    t = parse_targets(CONFIG_TEXT);
    assert t == ["AArch64", "ARM", "X86"];
}

test "link libraries parse with internal/external mix" {
    links = parse_link_libraries(EXPORTS_TEXT);
    assert "LLVMCore" in links;
    assert "LLVMSupport" in links;
    # Executables (llvm-tblgen) must not appear.
    assert "llvm-tblgen" not in links;
    # LLVMDemangle has no set_target_properties block -> not in the link map.
    assert "LLVMDemangle" not in links;
}

test "imported locations parse and strip prefix" {
    locs = parse_imported_locations(RELEASE_TEXT);
    assert locs["LLVMCore"] == "lib/libLLVMCore.a";
    assert locs["LLVMDemangle"] == "lib/libLLVMDemangle.a";
}

test "lib entries split deps vs external correctly" {
    available = parse_available_libs(CONFIG_TEXT);
    links = parse_link_libraries(EXPORTS_TEXT);
    locs = parse_imported_locations(RELEASE_TEXT);
    entries = build_lib_entries(available, links, locs);

    core = entries["LLVMCore"];
    assert core.deps == ["LLVMBinaryFormat", "LLVMDemangle", "LLVMRemarks", "LLVMSupport", "LLVMTargetParser"];
    assert core.external == ["-lpthread"];
    assert core.file == "lib/libLLVMCore.a";

    support = entries["LLVMSupport"];
    assert support.deps == ["LLVMDemangle"];
    assert support.external == ["rt", "dl", "-lpthread", "m", "ZLIB::ZLIB", "Terminfo::terminfo"];

    # A target with no IMPORTED_LOCATION is header-only -> file is None.
    ho = entries["LLVMHeaderOnly"];
    assert ho.file is None;
    assert ho.deps == [];
    assert ho.external == [];
}

test "generator-expression deps are unwrapped to internal targets" {
    available = ["LLVMCore", "LLVMPasses", "LLVMSupport"];
    links: dict = {};
    # Mirror the real exported form: an escaped $<LINK_ONLY:...> wrapping an
    # internal target, alongside a plain internal dep and a real external flag.
    links["LLVMCore"] = ["\\$<LINK_ONLY:LLVMPasses>", "LLVMSupport", "-lpthread"];
    entries = build_lib_entries(available, links, {});
    core = entries["LLVMCore"];
    assert core.deps == ["LLVMPasses", "LLVMSupport"];
    assert core.external == ["-lpthread"];
}
