#!/bin/sh
# LLVM, Clang and LLD for Windows, as static archives built from the pinned
# sources on Linux: mingw-w64 against the Universal CRT, with LLVM's libc++,
# compiler-rt and libunwind (llvm-mingw's toolchain, MSYS2's CLANG64), the C++
# runtime of every other neojac platform.
#
#   llvm/windows.sh <install> [<targets>]
#
# Installs the dev surface into <install>, the tree scripts/repackage.jac
# --work-dir packs as a slice: lib/ (the archives, lib/cmake/, Clang's resource
# headers), include/ and nothing else. <targets> is LLVM_TARGETS_TO_BUILD
# (default: all).
#
# The compiler is the LLVM release's Clang, for x86_64-w64-mingw32, against
# what runtimes/mingw.sh builds (the sysroot, compiler-rt's builtins and the
# C++ runtime), so the archives use the C++ runtime a consumer links them with:
# runtimes/llvm-runtimes.sh's libc++ for the target, which the runtimes slice
# ships. LLVM compresses with zlib and zstd, the static builds
# runtimes/host-libs.sh makes for Windows, which the runtimes slice ships as
# host/windows-x86_64/. No other external library is referenced.
RUNTIMES_DIR="$(cd "$(dirname "$0")/../runtimes" && pwd)"
. "$RUNTIMES_DIR/lib.sh"
install="$(mkdir -p "$1" && cd "$1" && pwd)"
targets="${2:-all}"
llvm_toolchain
llvm_sources

triple=x86_64-w64-mingw32
mingw="$WORK/mingw"
sh "$RUNTIMES_DIR/mingw.sh" "$mingw"
MINGW_SYSROOT="$mingw" sh "$RUNTIMES_DIR/host-libs.sh" windows-x86_64 "$WORK/host-windows-x86_64"

# CMake takes one path per compiler. The C++ runtime is named outright: its
# headers ahead of the C library's, and its libraries when a configure check
# or a native-tool-free target links.
wrap="$WORK/mingw-wrap"
rm -rf "$wrap"
mkdir -p "$wrap"
cxx="$mingw/cxx"
base="--target=$triple --sysroot=$mingw -fuse-ld=lld -rtlib=compiler-rt -unwindlib=none -Qunused-arguments"
printf '#!/bin/sh\nexec "%s/bin/clang" %s "$@"\n' "$LLVM" "$base" > "$wrap/cc"
printf '#!/bin/sh\nexec "%s/bin/clang++" %s -nostdinc++ -isystem "%s/include/c++/v1" -nostdlib++ "$@" -L"%s/lib" -lc++ -lc++abi -lunwind\n' \
    "$LLVM" "$base" "$cxx" "$cxx" > "$wrap/c++"
printf '#!/bin/sh\nexec "%s/bin/llvm-windres" --target=pe-x86-64 -I"%s/%s/include" "$@"\n' "$LLVM" "$mingw" "$triple" > "$wrap/rc"
chmod +x "$wrap/cc" "$wrap/c++" "$wrap/rc"

build="$WORK/llvm-windows"
rm -rf "$build" "$install"
mkdir -p "$install"
# Static archives only, no shared libLLVM, no tools, tests or examples: what
# the official release archives carry of LLVM, Clang and LLD. Its own tools
# (the TableGens) are built for this machine, with its compiler.
cmake -G Ninja -S "$LLVM_SRC/llvm" -B "$build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install" \
    -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_SYSTEM_PROCESSOR=x86_64 \
    -DCMAKE_C_COMPILER="$wrap/cc" \
    -DCMAKE_CXX_COMPILER="$wrap/c++" \
    -DCMAKE_RC_COMPILER="$wrap/rc" \
    -DCMAKE_AR="$LLVM/bin/llvm-ar" \
    -DCMAKE_RANLIB="$LLVM/bin/llvm-ranlib" \
    -DLLVM_HOST_TRIPLE=x86_64-w64-windows-gnu \
    -DLLVM_TARGETS_TO_BUILD="$targets" \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_ENABLE_RUNTIMES="" \
    -DLLVM_BUILD_LLVM_DYLIB=OFF \
    -DLLVM_LINK_LLVM_DYLIB=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_BUILD_TOOLS=OFF \
    -DLLVM_INCLUDE_TOOLS=ON \
    -DCLANG_BUILD_TOOLS=OFF \
    -DCLANG_INCLUDE_TESTS=OFF \
    -DCLANG_INCLUDE_DOCS=OFF \
    -DCLANG_BUILD_EXAMPLES=OFF \
    -DLLVM_ENABLE_BINDINGS=OFF \
    -DLLVM_ENABLE_ZLIB=FORCE_ON \
    -DLLVM_ENABLE_ZSTD=FORCE_ON \
    -DLLVM_USE_STATIC_ZSTD=ON \
    -DCMAKE_PREFIX_PATH="$WORK/host-windows-x86_64" \
    -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_ENABLE_LIBEDIT=OFF \
    -DLLVM_ENABLE_LIBPFM=OFF \
    -DLLVM_ENABLE_CURL=OFF \
    -DLLVM_ENABLE_HTTPLIB=OFF \
    -DCROSS_TOOLCHAIN_FLAGS_NATIVE="-DCMAKE_C_COMPILER=$LLVM/bin/clang;-DCMAKE_CXX_COMPILER=$LLVM/bin/clang++"
ninja -C "$build" -j"$JOBS" install

# The dev surface: no executables, no import libraries of DLLs (Clang's
# libclang), only the static archives.
rm -rf "$install/bin" "$install/share" "$install/libexec"
find "$install/lib" -maxdepth 1 \( -name '*.dll' -o -name '*.dll.a' \) -exec rm -f {} +
test -f "$install/lib/cmake/llvm/LLVMConfig.cmake"
test -f "$install/lib/cmake/llvm/LLVMExports.cmake"
for f in ZLIB ZSTD; do
    grep -q "#define LLVM_ENABLE_$f 1" "$install/include/llvm/Config/llvm-config.h" \
        || die "LLVM_ENABLE_$f is off"
done
for lib in LLVMCore LLVMSupport clangBasic clangDriver clangFrontend clangCodeGen \
           lldCommon lldCOFF lldELF lldMachO lldMinGW lldWasm; do
    test -f "$install/lib/lib$lib.a" || die "no lib$lib.a"
done
test -f "$install/include/clang/Driver/Driver.h"
test -f "$install/lib/clang/${LLVM_VERSION%%.*}/include/stddef.h"
log "x86_64-windows: $(ls "$install/lib"/*.a | wc -l) archives, $(du -sh "$install/lib" | cut -f1)"
