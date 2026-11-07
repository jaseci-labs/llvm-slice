#!/bin/sh
# The LLVM library rustc is built against: LLVM with rustc's LLVM wrapper,
# one shared library exporting only C symbols (LLVM's C API and the wrapper's
# LLVMRust* functions), named libneollvm, as neojac's libneollvm is (neojac
# builds the same wrapper into it, from the same rustc release, against the
# same LLVM). rustc's binaries load neojac's at run time; this one runs the
# compiler the build makes and uses, and gives every host a library to link.
#
#   rust/neollvm.sh <rust-src> <out>
#
# <rust-src> is rustc's source tree. Writes:
#
#   <out>/x86_64-unknown-linux-gnu/libneollvm.so   the library, linked from
#       the libc++ LLVM slice (linux-x86_64) and the runtimes' zlib and zstd
#       with Zig's c++ at the slice's glibc 2.17 floor
#   <out>/exports.txt                              the LLVM* functions it
#       exports
#   <out>/<host>/                                  for every other host rustc
#       is built for, a library to link against that exports exactly those:
#       libneollvm.so (aarch64-unknown-linux-gnu), libneollvm.dylib
#       (aarch64-apple-darwin), libneollvm.dll.a, the import library of
#       libneollvm.dll (x86_64-pc-windows-gnullvm)
#
# The library exports what rustc names (its LLVM bindings) and the slice or
# the wrapper defines: references to those keep their
# translation units in the link, and a version script exports LLVM*.
RUNTIMES_DIR="$(cd "$(dirname "$0")/../runtimes" && pwd)"
. "$RUNTIMES_DIR/lib.sh"
SOURCES="$RUNTIMES_DIR/sources.txt $RUNTIMES_DIR/../rust/sources.txt"
src="$(cd "$1" && pwd)"
out="$(mkdir -p "$2" && cd "$2" && pwd)"

slice="$WORK/llvm-slice"
if [ ! -f "$slice/include/llvm-c/Core.h" ]; then
    rm -rf "$slice"
    mkdir -p "$slice"
    # Assigned first: a failed fetch stops the script.
    zip="$(fetch llvm-22.1.8-x86_64-linux-libcxx-lld-r2-dev.zip)"
    (cd "$slice" && unzip -q "$zip" 'lib/*.a' 'include/*')
fi
host="$WORK/runtimes-host"
if [ ! -f "$host/libzstd.a" ]; then
    rm -rf "$host"
    mkdir -p "$host"
    zip="$(fetch llvm-22.1.8-runtimes-dev.zip)"
    (cd "$host" && unzip -q -j "$zip" 'host/linux-x86_64/*')
fi

b="$WORK/neollvm"
rm -rf "$b"
mkdir -p "$b/obj" "$out/x86_64-unknown-linux-gnu"

# The wrapper, with LLVM's release flags (rustc_llvm's build script takes them
# from llvm-config --cxxflags), default visibility (its functions carry no
# export annotation) and no debug info.
for f in CoverageMappingWrapper Linker PassWrapper RustWrapper SymbolWrapper; do
    zig c++ -target x86_64-linux-gnu.2.17 -c -fPIC -O2 -g0 -std=c++17 -fno-rtti -fno-exceptions \
        -DNDEBUG -Wno-deprecated-declarations -I "$slice/include" \
        "$src/compiler/rustc_llvm/llvm-wrapper/$f.cpp" -o "$b/obj/$f.o"
done

# What rustc names (its extern blocks' functions, and the target initializers
# its init_target! macro declares), and what is defined to export: of the
# names, the functions LLVM or the wrapper defines.
cat "$src/compiler/rustc_llvm/src/lib.rs" "$src"/compiler/rustc_codegen_llvm/src/llvm/*.rs \
    | grep -oE '\bLLVM[A-Za-z0-9_]+' | sort -u > "$b/declared.txt"
nm --defined-only "$slice"/lib/libLLVM*.a "$b"/obj/*.o 2> /dev/null \
    | awk '$2 == "T" { print $3 }' | grep '^LLVM' | sort -u > "$b/defined.txt"
comm -12 "$b/declared.txt" "$b/defined.txt" > "$b/anchored.txt"
log "rustc names $(wc -l < "$b/declared.txt") LLVM* identifiers; $(wc -l < "$b/anchored.txt") are functions LLVM defines"
{
    echo "/* Every LLVM* function rustc declares that LLVM or the wrapper defines. */"
    sed 's/.*/extern void &(void);/' "$b/anchored.txt"
    echo "__attribute__((used)) void *const neollvm_rustc_anchors[] = {"
    sed 's/.*/    (void *)\&&,/' "$b/anchored.txt"
    echo "};"
} > "$b/anchors.c"
zig cc -target x86_64-linux-gnu.2.17 -c -fPIC -O2 -g0 "$b/anchors.c" -o "$b/obj/anchors.o"
printf '{\n  global:\n    LLVM*;\n  local:\n    *;\n};\n' > "$b/exports.map"

# The archives reference each other circularly; -s: no symbol table but the
# dynamic one, which the exports are in.
zig c++ -target x86_64-linux-gnu.2.17 -shared -s -o "$out/x86_64-unknown-linux-gnu/libneollvm.so" \
    "$b"/obj/*.o -Wl,--start-group "$slice"/lib/libLLVM*.a "$host/libz.a" "$host/libzstd.a" \
    -Wl,--end-group -Wl,--version-script="$b/exports.map" -Wl,-soname,libneollvm.so
nm -D --defined-only "$out/x86_64-unknown-linux-gnu/libneollvm.so" | awk '{ print $3 }' \
    | grep '^LLVM' | sort -u > "$out/exports.txt"
missing="$(comm -23 "$b/anchored.txt" "$out/exports.txt")"
[ -z "$missing" ] || die "libneollvm does not export: $missing"
log "libneollvm.so exports $(wc -l < "$out/exports.txt") LLVM* functions"

# Every other host's library to link against: the same exports, defined by a
# stub, under the name and install name the real library has there.
{
    echo "/* The functions libneollvm exports, to link against. */"
    sed 's/.*/void &(void) {}/' "$out/exports.txt"
} > "$b/stub.c"
mkdir -p "$out/aarch64-unknown-linux-gnu" "$out/aarch64-apple-darwin" "$out/x86_64-pc-windows-gnullvm"
zig cc -target aarch64-linux-gnu.2.17 -shared -fPIC -g0 "$b/stub.c" -Wl,-soname,libneollvm.so \
    -o "$out/aarch64-unknown-linux-gnu/libneollvm.so"
zig cc -target aarch64-macos -shared -g0 "$b/stub.c" -Wl,-install_name,@rpath/libneollvm.dylib \
    -o "$out/aarch64-apple-darwin/libneollvm.dylib"
{
    echo "LIBRARY libneollvm.dll"
    echo "EXPORTS"
    sed 's/.*/    &/' "$out/exports.txt"
} > "$b/neollvm.def"
zig dlltool -m i386:x86-64 -d "$b/neollvm.def" -D libneollvm.dll \
    -l "$out/x86_64-pc-windows-gnullvm/libneollvm.dll.a"
log "link libraries for $(cd "$out" && ls -d */ | tr -d / | tr '\n' ' ')"
