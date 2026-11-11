#!/bin/sh
# The libraries LLVM's archives reference but do not ship, as static
# libraries, so a consumer links the archives without the system's copies:
# each built by its own CMake, with the options LLVM's release builds use.
#
#   runtimes/host-libs.sh macos-aarch64 <out>    zlib, zstd and libxml2 for
#       macOS 14.0 and later (LLVM's Clang and the macOS SDK; run on macOS)
#   runtimes/host-libs.sh linux-x86_64 <out>     zlib and zstd for the libc++
#   runtimes/host-libs.sh linux-aarch64 <out>    slices (build-libcxx.yml), at
#       their glibc 2.17 floor, position-independent (a consumer links them
#       into a shared library with the archives): Zig's cc, the compiler that
#       builds those slices, from any Linux host
#   runtimes/host-libs.sh windows-x86_64 <out>   zlib (its MinGW makefile) and
#       zstd for the Windows libc++ slice (llvm/windows.sh): the LLVM release's
#       Clang against the mingw-w64 runtimes/mingw.sh builds (MINGW_SYSROOT
#       names its <out>), from Linux
#
# Writes the static libraries to <out>/lib and their headers to <out>/include,
# which a build of LLVM against them reads.
. "$(dirname "$0")/lib.sh"
platform="$1"
out="$(mkdir -p "$2" && cd "$2" && pwd)"
rm -rf "$out/lib" "$out/include"

# LLVM's release options for libxml2 (llvm/utils/release/build_llvm_release.bat):
# what LLVMWindowsManifest uses, and nothing that needs another library.
xml_options="-DBUILD_SHARED_LIBS=OFF -DLIBXML2_WITH_C14N=OFF -DLIBXML2_WITH_CATALOG=OFF
    -DLIBXML2_WITH_DEBUG=OFF -DLIBXML2_WITH_DOCB=OFF -DLIBXML2_WITH_FTP=OFF -DLIBXML2_WITH_HTML=OFF
    -DLIBXML2_WITH_HTTP=OFF -DLIBXML2_WITH_ICONV=OFF -DLIBXML2_WITH_ICU=OFF -DLIBXML2_WITH_ISO8859X=OFF
    -DLIBXML2_WITH_LEGACY=OFF -DLIBXML2_WITH_LZMA=OFF -DLIBXML2_WITH_MEM_DEBUG=OFF
    -DLIBXML2_WITH_MODULES=OFF -DLIBXML2_WITH_OUTPUT=ON -DLIBXML2_WITH_PATTERN=OFF
    -DLIBXML2_WITH_PROGRAMS=OFF -DLIBXML2_WITH_PUSH=OFF -DLIBXML2_WITH_PYTHON=OFF
    -DLIBXML2_WITH_READER=OFF -DLIBXML2_WITH_REGEXPS=OFF -DLIBXML2_WITH_RUN_DEBUG=OFF
    -DLIBXML2_WITH_SAX1=ON -DLIBXML2_WITH_SCHEMAS=OFF -DLIBXML2_WITH_SCHEMATRON=OFF
    -DLIBXML2_WITH_TESTS=OFF -DLIBXML2_WITH_THREADS=ON -DLIBXML2_WITH_THREAD_ALLOC=OFF
    -DLIBXML2_WITH_TREE=ON -DLIBXML2_WITH_VALID=OFF -DLIBXML2_WITH_WRITER=OFF
    -DLIBXML2_WITH_XINCLUDE=OFF -DLIBXML2_WITH_XPATH=OFF -DLIBXML2_WITH_XPTR=OFF -DLIBXML2_WITH_ZLIB=OFF"

# cmake_build <name> <source dir> <cmake args...>: configure, build and install
# into $out.
cmake_build() {
    name="$1"
    srcdir="$2"
    shift 2
    b="$WORK/host-$name"
    rm -rf "$b"
    # shellcheck disable=SC2086
    cmake -G Ninja -S "$srcdir" -B "$b" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$out" -DCMAKE_POLICY_DEFAULT_CMP0091=NEW \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 $common "$@"
    cmake --build "$b" --config Release
    cmake --install "$b" --config Release
}

# zlib and zstd, as static libraries only.
zlib_zstd() {
    unpack zlib-1.3.1.tar.gz "$WORK/zlib"
    cmake_build zlib "$WORK/zlib" -DZLIB_BUILD_EXAMPLES=OFF
    unpack zstd-1.5.7.tar.gz "$WORK/zstd"
    cmake_build zstd "$WORK/zstd/build/cmake" -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON \
        -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_TESTS=OFF -DZSTD_LEGACY_SUPPORT=OFF
}

case "$platform" in
    macos-aarch64)
        llvm_toolchain
        sdk="$(xcrun --sdk macosx --show-sdk-path)"
        common="-DCMAKE_C_COMPILER=$LLVM/bin/clang -DCMAKE_AR=$LLVM/bin/llvm-ar
            -DCMAKE_RANLIB=$LLVM/bin/llvm-ranlib -DCMAKE_OSX_SYSROOT=$sdk
            -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
            -DCMAKE_C_FLAGS=-fvisibility=hidden"
        zlib_zstd
        # libxml2's sources, without its test data, which the library's build
        # does not read.
        unpack libxml2-v2.9.12.tar.gz "$WORK/libxml2" --exclude='*/test/*'
        # shellcheck disable=SC2086
        cmake_build libxml2 "$WORK/libxml2" $xml_options
        # Static libraries only: zlib's build also makes a shared one.
        find "$out/lib" -name '*.dylib' -exec rm -f {} +
        for f in libz.a libzstd.a libxml2.a; do test -f "$out/lib/$f"; done
        ;;
    linux-x86_64 | linux-aarch64)
        arch="${platform#linux-}"
        z="$WORK/zig-$arch"
        mkdir -p "$z"
        # CMake takes one path per tool: Zig's, wrapped. No debug info, as in
        # the slices' own archives.
        printf '#!/bin/sh\nexec zig cc -target %s-linux-gnu.2.17 "$@" -g0\n' "$arch" > "$z/cc"
        printf '#!/bin/sh\nexec zig ar "$@"\n' > "$z/ar"
        printf '#!/bin/sh\nexec zig ranlib "$@"\n' > "$z/ranlib"
        chmod +x "$z/cc" "$z/ar" "$z/ranlib"
        common="-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=$arch -DCMAKE_C_COMPILER=$z/cc
            -DCMAKE_AR=$z/ar -DCMAKE_RANLIB=$z/ranlib -DCMAKE_POSITION_INDEPENDENT_CODE=ON
            -DCMAKE_C_FLAGS=-fvisibility=hidden"
        zlib_zstd
        # Static libraries only: zlib's build also makes a shared one.
        find "$out/lib" -name '*.so*' -exec rm -f {} +
        for f in libz.a libzstd.a; do test -f "$out/lib/$f"; done
        ;;
    windows-x86_64)
        llvm_toolchain
        [ -d "${MINGW_SYSROOT:-}/x86_64-w64-mingw32" ] || die "MINGW_SYSROOT is not runtimes/mingw.sh's output"
        cc="$LLVM/bin/clang --target=x86_64-w64-mingw32 --sysroot=$MINGW_SYSROOT"
        # zlib by its own MinGW makefile, the static library alone, as
        # runtimes/mingw.sh builds it for Windows' programs.
        unpack zlib-1.3.1.tar.gz "$WORK/zlib"
        make -s -C "$WORK/zlib" -f win32/Makefile.gcc libz.a CC="$cc" CFLAGS="-O2 -Wall" \
            AR="$LLVM/bin/llvm-ar" ARFLAGS=rcs
        mkdir -p "$out/lib" "$out/include"
        cp "$WORK/zlib/libz.a" "$out/lib/"
        cp "$WORK/zlib/zlib.h" "$WORK/zlib/zconf.h" "$out/include/"
        common="-DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=x86_64
            -DCMAKE_C_COMPILER=$LLVM/bin/clang -DCMAKE_C_COMPILER_TARGET=x86_64-w64-mingw32
            -DCMAKE_SYSROOT=$MINGW_SYSROOT -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
            -DCMAKE_AR=$LLVM/bin/llvm-ar -DCMAKE_RANLIB=$LLVM/bin/llvm-ranlib"
        unpack zstd-1.5.7.tar.gz "$WORK/zstd"
        cmake_build zstd "$WORK/zstd/build/cmake" -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON \
            -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_TESTS=OFF -DZSTD_LEGACY_SUPPORT=OFF
        for f in libz.a libzstd.a; do test -f "$out/lib/$f"; done
        ;;
    *) die "platform is macos-aarch64, linux-x86_64, linux-aarch64 or windows-x86_64" ;;
esac
# The static libraries, and their headers: a link needs nothing else.
find "$out/lib" -mindepth 1 ! -name "*.a" ! -name "*.lib" -exec rm -rf {} +
rm -rf "$out/share" "$out/bin"
log "$platform: $(ls "$out/lib" | tr '\n' ' ')"
