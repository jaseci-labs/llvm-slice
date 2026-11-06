#!/bin/sh
# Lay the built pieces out as the runtimes tree, then check that every target's
# runtime links against its C library (check_links.py).
#
#   runtimes/assemble.sh <in> <out>
#
# <in> holds the other scripts' outputs: linux-headers/, musl-<arch>/, glibc/,
# glibc-crt/<arch>-<version>/, rt-<triple>/ (the four Linux triples), mingw/,
# darwin/, host-macos-aarch64/ and host-windows-x86_64/. The tree:
#
#   SOURCES.txt                      every pinned input, and the macOS SDK
#   libc/include/<dir>/              C library headers: <arch>-linux-musl,
#                                    <arch>-linux-kernel, generic-glibc,
#                                    x86-linux-gnu, aarch64-linux-gnu, mingw-w64,
#                                    darwin
#   libc/glibc/abilist/<arch>.abilist, libc/glibc/abilist/VERSION
#   libc/darwin/libSystem.tbd
#   libc/darwin/System/Library/Frameworks/<name>.framework/{Headers/,<name>.tbd}
#                                    the macOS frameworks programs link besides
#                                    libSystem, where a link's -syslibroot
#                                    libc/darwin finds them
#   libc/darwin/usr/lib/<name>.tbd   the libraries they re-export (libobjc), at
#                                    their install names
#   libcxx/include/                  libc++'s headers (and libc++abi's)
#   libunwind/include/
#   targets/<target>/                each target's libraries and start files, and
#                                    include/__config_site, libc++'s configuration
#   host/<platform>/                 what LLVM's own archives link on that host
. "$(dirname "$0")/lib.sh"
in="$(cd "$1" && pwd)"
out="$(mkdir -p "$2" && cd "$2" && pwd)"
llvm_toolchain
rm -rf "$out"/*

inc="$out/libc/include"
mkdir -p "$inc" "$out/libc/glibc" "$out/libc/darwin" "$out/libcxx" "$out/libunwind" "$out/targets" "$out/host"

for arch in x86_64 aarch64; do
    cp -R "$in/linux-headers/$arch/include" "$inc/$arch-linux-kernel"
    cp -R "$in/musl-$arch/include" "$inc/$arch-linux-musl"
done
for d in generic-glibc x86-linux-gnu aarch64-linux-gnu; do cp -R "$in/glibc/include/$d" "$inc/$d"; done
cp "$in/glibc/include/LICENSE.zig" "$inc/generic-glibc/LICENSE.zig"
cp -R "$in/glibc/abilist" "$out/libc/glibc/abilist"
# The headers a C or C++ compiler reads; the IDL sources are for an IDL compiler.
mkdir -p "$inc/mingw-w64"
(cd "$in/mingw/x86_64-w64-mingw32/include" && tar -cf - --exclude '*.idl' .) | (cd "$inc/mingw-w64" && tar -xf -)
cp -R "$in/darwin/include" "$inc/darwin"
cp "$in/darwin/libSystem.tbd" "$out/libc/darwin/libSystem.tbd"
mkdir -p "$out/libc/darwin/System/Library"
cp -R "$in/darwin/frameworks" "$out/libc/darwin/System/Library/Frameworks"
if [ -d "$in/darwin/root" ]; then
    cp -R "$in/darwin/root/." "$out/libc/darwin/"
fi

# libc++'s headers are the same for every target but for its configuration.
cp -R "$in/rt-x86_64-linux-gnu/include/c++/v1" "$out/libcxx/include"
rm "$out/libcxx/include/__config_site"
mkdir -p "$out/libunwind/include"
for f in libunwind.h unwind.h unwind_arm_ehabi.h unwind_itanium.h __libunwind_config.h libunwind.modulemap mach-o; do
    if [ -e "$in/rt-x86_64-linux-gnu/include/$f" ]; then
        cp -R "$in/rt-x86_64-linux-gnu/include/$f" "$out/libunwind/include/"
    fi
done
test -f "$out/libunwind/include/libunwind.h"

# target_runtime <target> <dir>: LLVM's runtime libraries and libc++'s
# configuration, after checking the target's headers match the shared ones.
target_runtime() {
    t="$out/targets/$1"
    mkdir -p "$t/include"
    cp "$2"/lib/*.a "$t/"
    if [ -d "$2/include/c++/v1" ]; then
        diff -r -x __config_site "$2/include/c++/v1" "$out/libcxx/include" > /dev/null ||
            die "$1: libc++'s headers differ from the other targets' beyond __config_site"
        cp "$2/include/c++/v1/__config_site" "$t/include/__config_site"
    fi
}

for arch in x86_64 aarch64; do
    t="$out/targets/$arch-linux-musl"
    target_runtime "$arch-linux-musl" "$in/rt-$arch-linux-musl"
    for f in libc.a crt1.o rcrt1.o Scrt1.o crti.o crtn.o; do cp "$in/musl-$arch/lib/$f" "$t/"; done

    t="$out/targets/$arch-linux-gnu"
    target_runtime "$arch-linux-gnu" "$in/rt-$arch-linux-gnu"
    for v in 2.17 2.33 2.34; do
        mkdir -p "$t/glibc-$v"
        cp "$in/glibc-crt/$arch-$v"/* "$t/glibc-$v/"
    done
done

t="$out/targets/x86_64-windows-gnu"
mkdir -p "$t"
cp "$in/mingw/x86_64-w64-mingw32/lib"/*.a "$in/mingw/x86_64-w64-mingw32/lib"/*.o "$t/"
cp "$in/mingw/builtins/lib/libclang_rt.builtins.a" "$in/mingw/cxx/lib/"
target_runtime x86_64-windows-gnu "$in/mingw/cxx"

for arch in aarch64 x86_64; do
    target_runtime "$arch-macos" "$in/darwin/$arch"
done

# WebAssembly: wasi-sdk's own build of wasi-libc and compiler-rt's builtins.
t="$out/targets/wasm32-wasi"
mkdir -p "$t"
unpack wasi-sysroot-34.0.tar.gz "$WORK/wasi-sysroot" "*/lib/wasm32-wasip1/*.a"
unpack libclang_rt-34.0.tar.gz "$WORK/wasi-rt" "*/wasm32-unknown-wasip1/*"
for f in libc.a libdl.a libwasi-emulated-getpid.a libwasi-emulated-mman.a \
         libwasi-emulated-process-clocks.a libwasi-emulated-signal.a; do
    cp "$WORK/wasi-sysroot/lib/wasm32-wasip1/$f" "$t/"
done
cp "$WORK/wasi-rt/wasm32-unknown-wasip1/libclang_rt.builtins.a" "$t/"

for p in macos-aarch64 windows-x86_64; do
    mkdir -p "$out/host/$p"
    cp "$in/host-$p/lib"/* "$out/host/$p/"
done

{
    echo "# Built from these pinned inputs (runtimes/sources.txt):"
    grep -v '^#' "$RUNTIMES_DIR/sources.txt" | grep -v '^$'
    echo "# macOS SDK $(cat "$in/darwin/SDK_VERSION") (headers, and the stubs of libSystem and the frameworks)"
} > "$out/SOURCES.txt"

python3 "$RUNTIMES_DIR/check_links.py" "$out" "$LLVM/bin/llvm-nm"
log "$(du -sh "$out" | cut -f1) in $(find "$out" -type f | wc -l) files"
