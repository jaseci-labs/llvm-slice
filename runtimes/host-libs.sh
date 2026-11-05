#!/bin/sh
# The libraries LLVM's official macOS and Windows archives reference but do not
# ship, as static libraries, so a consumer links the archives without the
# system's copies: each built by its own CMake, with the options LLVM's release
# builds use.
#
#   runtimes/host-libs.sh macos-aarch64 <out>    zlib, zstd and libxml2 for
#       macOS 14.0 and later (LLVM's Clang and the macOS SDK; run on macOS)
#   runtimes/host-libs.sh windows-x86_64 <out>   libxml2 for MSVC against the
#       static runtime (/MT), the libxml2 build_llvm_release.bat makes (run in a
#       Visual Studio developer environment)
#
# Writes the static libraries to <out>/lib.
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
    # Ninja, or $CMAKE_GENERATOR (NMake Makefiles in a Visual Studio
    # developer environment).
    # shellcheck disable=SC2086
    cmake -G "${CMAKE_GENERATOR:-Ninja}" -S "$srcdir" -B "$b" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$out" -DCMAKE_POLICY_DEFAULT_CMP0091=NEW \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 $common "$@"
    cmake --build "$b" --config Release
    cmake --install "$b" --config Release
}

# libxml2's sources, without its test data (whose symbolic links Windows' tar
# cannot make, and which the library's build does not read).
unpack_libxml2() {
    unpack libxml2-v2.9.12.tar.gz "$WORK/libxml2" --exclude='*/test/*'
}

case "$platform" in
    macos-aarch64)
        llvm_toolchain
        sdk="$(xcrun --sdk macosx --show-sdk-path)"
        common="-DCMAKE_C_COMPILER=$LLVM/bin/clang -DCMAKE_AR=$LLVM/bin/llvm-ar
            -DCMAKE_RANLIB=$LLVM/bin/llvm-ranlib -DCMAKE_OSX_SYSROOT=$sdk
            -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
            -DCMAKE_C_FLAGS=-fvisibility=hidden"
        unpack zlib-1.3.1.tar.gz "$WORK/zlib"
        cmake_build zlib "$WORK/zlib" -DZLIB_BUILD_EXAMPLES=OFF
        unpack zstd-1.5.7.tar.gz "$WORK/zstd"
        cmake_build zstd "$WORK/zstd/build/cmake" -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON \
            -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_TESTS=OFF -DZSTD_LEGACY_SUPPORT=OFF
        unpack_libxml2
        # shellcheck disable=SC2086
        cmake_build libxml2 "$WORK/libxml2" $xml_options
        # Static libraries only: zlib's build also makes a shared one.
        find "$out/lib" -name '*.dylib' -exec rm -f {} +
        for f in libz.a libzstd.a libxml2.a; do test -f "$out/lib/$f"; done
        ;;
    windows-x86_64)
        common="-DCMAKE_C_COMPILER=cl -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded"
        unpack_libxml2
        # shellcheck disable=SC2086
        cmake_build libxml2 "$WORK/libxml2" $xml_options
        ls "$out/lib"
        ;;
    *) die "platform is macos-aarch64 or windows-x86_64" ;;
esac
# Only the static libraries: a link needs nothing else.
find "$out/lib" -mindepth 1 ! -name "*.a" ! -name "*.lib" -exec rm -rf {} +
rm -rf "$out/include" "$out/share" "$out/bin"
log "$platform: $(ls "$out/lib" | tr '\n' ' ')"
