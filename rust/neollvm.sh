#!/bin/sh
# The LLVM library rustc is built against: LLVM with rustc's LLVM wrapper,
# one shared library exporting only C symbols (LLVM's C API and the wrapper's
# LLVMRust* functions), named libneollvm, as neojac's libneollvm is (neojac
# builds the same wrapper into it, from the same rustc release, against the
# same LLVM). rustc's binaries load neojac's at run time; this one runs the
# compiler the build makes, and is what its binaries link against.
#
#   rust/neollvm.sh <platform> <rust-src> <out>
#
# <rust-src> is rustc's source tree. Writes <out>/libneollvm.so (or .dylib)
# and <out>/exports.txt, the LLVM* functions it exports:
#
#   linux-x86_64, linux-aarch64   from the libc++ LLVM slice and the
#       runtimes' zlib and zstd, with Zig's c++ at the slice's glibc 2.17
#       floor (soname libneollvm.so)
#   macos-aarch64                 from LLVM's official macOS archives (ThinLTO
#       bitcode, which LLD lowers with the LLVM it is) and the runtimes' zlib,
#       zstd and libxml2, with the LLVM release's Clang and LLD and the SDK,
#       for macOS 14.0 (install name @rpath/libneollvm.dylib)
#
# The library exports what rustc names (its LLVM bindings) and the slice or
# the wrapper defines: references to those keep their translation units in
# the link, and the export list exports LLVM*.
RUNTIMES_DIR="$(cd "$(dirname "$0")/../runtimes" && pwd)"
. "$RUNTIMES_DIR/lib.sh"
SOURCES="$RUNTIMES_DIR/sources.txt $RUNTIMES_DIR/../rust/sources.txt"
platform="$1"
src="$(cd "$2" && pwd)"
out="$(mkdir -p "$3" && cd "$3" && pwd)"
case "$platform" in
    linux-x86_64 | linux-aarch64) slice_zip="llvm-22.1.8-${platform#linux-}-linux-libcxx-lld-r2-dev.zip" ;;
    macos-aarch64) slice_zip=llvm-22.1.8-aarch64-apple-darwin-dev.zip ;;
    *) die "usage: rust/neollvm.sh linux-x86_64|linux-aarch64|macos-aarch64 <rust-src> <out>" ;;
esac

slice="$WORK/llvm-slice-$platform"
if [ ! -f "$slice/include/llvm-c/Core.h" ]; then
    rm -rf "$slice"
    mkdir -p "$slice"
    # Assigned first: a failed fetch stops the script.
    zip="$(fetch "$slice_zip")"
    (cd "$slice" && unzip -q "$zip" 'lib/libLLVM*.a' 'include/*')
fi
host="$WORK/runtimes-host-$platform"
if [ ! -d "$host" ]; then
    mkdir -p "$host.part"
    zip="$(fetch llvm-22.1.8-runtimes-dev.zip)"
    (cd "$host.part" && unzip -q -j "$zip" "host/$platform/*")
    mv "$host.part" "$host"
fi

b="$WORK/neollvm-build-$platform"
rm -rf "$b"
mkdir -p "$b/obj"

# Each platform's compiler and the flags of LLVM's release build (rustc_llvm's
# build script takes them from llvm-config --cxxflags); the wrapper's
# functions carry no export annotation, so it compiles with default
# visibility, and the export list narrows what is exported.
case "$platform" in
    linux-*)
        arch="${platform#linux-}"
        cxx="zig c++ -target $arch-linux-gnu.2.17"
        cc="zig cc -target $arch-linux-gnu.2.17"
        nm=nm
        flags="-fPIC"
        ;;
    macos-*)
        llvm_toolchain
        sdk="$(xcrun --sdk macosx --show-sdk-path)"
        cxx="$LLVM/bin/clang++ -target arm64-apple-macos14.0 -isysroot $sdk"
        cc="$LLVM/bin/clang -target arm64-apple-macos14.0 -isysroot $sdk"
        nm="$LLVM/bin/llvm-nm"
        flags=""
        ;;
esac
for f in CoverageMappingWrapper Linker PassWrapper RustWrapper SymbolWrapper; do
    # shellcheck disable=SC2086
    $cxx -c $flags -O2 -g0 -std=c++17 -fno-rtti -fno-exceptions -DNDEBUG -Wno-deprecated-declarations \
        -I "$slice/include" "$src/compiler/rustc_llvm/llvm-wrapper/$f.cpp" -o "$b/obj/$f.o"
done

# What rustc names (its extern blocks' functions, and the target initializers
# its init_target! macro declares), and what is defined to export: of the
# names, the functions LLVM or the wrapper defines.
cat "$src/compiler/rustc_llvm/src/lib.rs" "$src"/compiler/rustc_codegen_llvm/src/llvm/*.rs \
    | grep -oE '\bLLVM[A-Za-z0-9_]+' | sort -u > "$b/declared.txt"
$nm --defined-only "$slice"/lib/libLLVM*.a "$b"/obj/*.o 2> /dev/null \
    | awk '$2 == "T" { print $3 }' | sed 's/^_//' | grep '^LLVM' | sort -u > "$b/defined.txt"
comm -12 "$b/declared.txt" "$b/defined.txt" > "$b/anchored.txt"
log "rustc names $(wc -l < "$b/declared.txt") LLVM* identifiers; $(wc -l < "$b/anchored.txt") are functions LLVM defines"
{
    echo "/* Every LLVM* function rustc names that LLVM or the wrapper defines. */"
    sed 's/.*/extern void &(void);/' "$b/anchored.txt"
    echo "__attribute__((used)) void *const neollvm_rustc_anchors[] = {"
    sed 's/.*/    (void *)\&&,/' "$b/anchored.txt"
    echo "};"
} > "$b/anchors.c"
# shellcheck disable=SC2086
$cc -c $flags -O2 -g0 "$b/anchors.c" -o "$b/obj/anchors.o"

case "$platform" in
    linux-*)
        lib="$out/libneollvm.so"
        printf '{\n  global:\n    LLVM*;\n  local:\n    *;\n};\n' > "$b/exports.map"
        # The archives reference each other circularly; -s: no symbol table
        # but the dynamic one, which the exports are in.
        # shellcheck disable=SC2086
        $cxx -shared -s -o "$lib" "$b"/obj/*.o -Wl,--start-group "$slice"/lib/libLLVM*.a \
            "$host/libz.a" "$host/libzstd.a" -Wl,--end-group -Wl,--version-script="$b/exports.map" \
            -Wl,-soname,libneollvm.so
        nm -D --defined-only "$lib" | awk '{ print $3 }' | grep '^LLVM' | sort -u > "$out/exports.txt"
        ;;
    macos-*)
        lib="$out/libneollvm.dylib"
        # shellcheck disable=SC2086
        $cxx -dynamiclib -fuse-ld=lld -o "$lib" "$b"/obj/*.o "$slice"/lib/libLLVM*.a \
            "$host/libz.a" "$host/libzstd.a" "$host/libxml2.a" -Wl,-exported_symbol,_LLVM* \
            -Wl,-install_name,@rpath/libneollvm.dylib
        "$nm" --defined-only --extern-only "$lib" | awk '{ print $3 }' | sed 's/^_//' \
            | grep '^LLVM' | sort -u > "$out/exports.txt"
        ;;
esac
missing="$(comm -23 "$b/anchored.txt" "$out/exports.txt")"
[ -z "$missing" ] || die "libneollvm does not export: $missing"
log "$(basename "$lib") exports $(wc -l < "$out/exports.txt") LLVM* functions"
