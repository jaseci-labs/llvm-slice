#!/bin/sh
# The C libraries CPython's standard library is built on, for one platform:
# zlib, bzip2, xz's liblzma, Zstandard, SQLite, libffi and OpenSSL, each a
# static library built by its own build system (SQLite's amalgamation is one
# file, compiled as SQLite's documentation says). Every object is compiled
# -fvisibility=hidden and no library's API asks for default visibility, so a
# program that exports its own C API (an interpreter linked with
# --export-dynamic) exports none of theirs, and a wheel bundling its own copy
# of one never binds to these. check_hidden.py proves it.
#
#   cpython/clibs.sh <platform> <out>
#
#   linux-x86_64, linux-aarch64   natively, in a manylinux_2_28 container: its
#                                 GCC, against glibc 2.28 (neojac's CPython
#                                 links against 2.29); PYTHON names a Python 3
#   macos-aarch64, macos-x86_64   on macOS, the LLVM release's Clang and the
#                                 runner's SDK, for macOS 14.0 (neojac's floor)
#   windows-x86_64                on Linux, the LLVM release's Clang and the
#                                 mingw-w64 runtimes/mingw.sh builds (its <out>
#                                 is MINGW_SYSROOT), against the Universal CRT
#
# Writes <out>/include/ (every library's public headers), <out>/lib/lib*.a and
# <out>/licenses/<library>/.
CPYTHON_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIMES_DIR="$CPYTHON_DIR/../runtimes"
SOURCES="$CPYTHON_DIR/sources.txt $RUNTIMES_DIR/sources.txt"
. "$RUNTIMES_DIR/lib.sh"
platform="$1"
out="$(mkdir -p "$2" && cd "$2" && pwd)"
rm -rf "${out:?}"/*
mkdir -p "$out/include" "$out/lib" "$out/licenses"

# host: configure's --host ("" for a native build); CC, AR, RANLIB, CFLAGS:
# what every build compiles with, and LDFLAGS what a configure check links
# with besides; ossl: OpenSSL's Configure target.
host=""
RC=""
LDFLAGS=""
PYTHON="${PYTHON:-python3}"
hidden="-fvisibility=hidden"
case "$platform" in
    linux-x86_64 | linux-aarch64)
        arch="${platform#linux-}"
        [ "$(uname -m)" = "$arch" ] || die "$platform builds natively; this is $(uname -m)"
        CC=gcc AR=ar RANLIB=ranlib
        CFLAGS="-O2 -fPIC $hidden"
        ossl="linux-$arch"
        check="readelf"
        ;;
    macos-aarch64 | macos-x86_64)
        arch="${platform#macos-}"
        march="$arch"
        [ "$arch" = aarch64 ] && march=arm64
        llvm_toolchain
        sdk="$(xcrun --sdk macosx --show-sdk-path)"
        CC="$LLVM/bin/clang -target $march-apple-macos14.0 -isysroot $sdk"
        AR="$LLVM/bin/llvm-ar" RANLIB="$LLVM/bin/llvm-ranlib"
        CFLAGS="-O2 $hidden"
        host="$arch-apple-darwin"
        ossl="darwin64-$march-cc"
        check="$LLVM/bin/llvm-nm"
        ;;
    windows-x86_64)
        llvm_toolchain
        [ -d "${MINGW_SYSROOT:-}/x86_64-w64-mingw32" ] || die "MINGW_SYSROOT is not runtimes/mingw.sh's output"
        # As runtimes/mingw.sh builds zlib for Windows (compiler-rt's builtins
        # are where it put them, in the Clang's resource directory); the link's
        # own flags apart, which a compile would warn are unused (and xz's
        # configure refuses flags that warn).
        CC="$LLVM/bin/clang --target=x86_64-w64-mingw32 --sysroot=$MINGW_SYSROOT"
        LDFLAGS="-fuse-ld=lld -rtlib=compiler-rt -unwindlib=none"
        AR="$LLVM/bin/llvm-ar" RANLIB="$LLVM/bin/llvm-ranlib"
        RC="$LLVM/bin/llvm-windres --target=pe-x86-64 -I$MINGW_SYSROOT/x86_64-w64-mingw32/include"
        # PE has no symbol visibility: what a DLL exports is what it says.
        CFLAGS="-O2"
        host=x86_64-w64-mingw32
        ossl=mingw64
        check=""
        ;;
    *) die "unknown platform '$platform'" ;;
esac
export CC AR RANLIB CFLAGS LDFLAGS
# Windows' resource compiler, for the version resources xz's and OpenSSL's
# builds compile.
[ -z "$RC" ] || export RC
log "$platform: $CC $CFLAGS${LDFLAGS:+ (linking $LDFLAGS)}"

licenses() { # licenses <library> <file>...
    name="$1"
    shift
    mkdir -p "$out/licenses/$name"
    cp "$@" "$out/licenses/$name/"
}

# zlib: its configure (static only), or on Windows its MinGW makefile.
src="$WORK/zlib"
unpack zlib-1.4.tar.gz "$src"
if [ "$platform" = windows-x86_64 ]; then
    make -s -C "$src" -f win32/Makefile.gcc libz.a CC="$CC" CFLAGS="$CFLAGS" AR="$AR" ARFLAGS=rcs
    cp "$src/libz.a" "$out/lib/"
    cp "$src/zlib.h" "$src/zconf.h" "$out/include/"
else
    (cd "$src" && CHOST="$host" ./configure --static --prefix="$out")
    make -s -C "$src" -j"$JOBS" libz.a
    make -s -C "$src" install
fi
licenses zlib "$src/LICENSE"

# bzip2: its Makefile's library.
src="$WORK/bzip2"
unpack bzip2-1.0.8.tar.gz "$src"
make -s -C "$src" -j"$JOBS" libbz2.a CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="$CFLAGS -D_FILE_OFFSET_BITS=64"
cp "$src/libbz2.a" "$out/lib/"
cp "$src/bzlib.h" "$out/include/"
licenses bzip2 "$src/LICENSE"

# xz's liblzma: its configure, without its programs. gl_cv_cc_visibility=no:
# liblzma's API takes no default visibility of its own (HAVE_VISIBILITY 0).
src="$WORK/xz"
unpack xz-5.8.1.tar.gz "$src"
b="$WORK/xz-build"
rm -rf "$b" && mkdir -p "$b"
(cd "$b" && "$src/configure" -q ${host:+--host="$host"} --prefix="$out" \
    --disable-shared --enable-static --with-pic \
    --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo \
    --disable-lzma-links --disable-scripts --disable-doc --disable-nls \
    gl_cv_cc_visibility=no)
make -s -C "$b" -j"$JOBS"
make -s -C "$b/src/liblzma" install
licenses xz "$src/COPYING" "$src/COPYING.0BSD"

# Zstandard: its library's Makefile, multithreaded, without the legacy formats
# or the deprecated API; its API without the default visibility its headers
# give it (CPPFLAGS from the environment, which its Makefile adds to).
src="$WORK/zstd"
unpack zstd-1.5.7.tar.gz "$src"
CPPFLAGS="-DZSTDLIB_VISIBLE= -DZSTDERRORLIB_VISIBLE= -DZDICTLIB_VISIBLE=" \
    make -s -C "$src/lib" -j"$JOBS" libzstd.a-mt ZSTD_LEGACY_SUPPORT=0 ZSTD_LIB_DEPRECATED=0
make -s -C "$src/lib" install-static install-includes PREFIX="$out" LIBDIR="$out/lib" INCLUDEDIR="$out/include"
licenses zstd "$src/LICENSE"

# SQLite: its amalgamation, with what python.org's interpreters enable.
src="$WORK/sqlite"
unpack sqlite-autoconf-3530400.tar.gz "$src"
# shellcheck disable=SC2086
$CC $CFLAGS -c "$src/sqlite3.c" -o "$WORK/sqlite3.o" \
    -DSQLITE_THREADSAFE=1 -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS \
    -DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE \
    -DSQLITE_ENABLE_GEOPOLY -DSQLITE_ENABLE_MATH_FUNCTIONS -DSQLITE_ENABLE_DBSTAT_VTAB \
    -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_OMIT_DEPRECATED
rm -f "$out/lib/libsqlite3.a"
$AR rcs "$out/lib/libsqlite3.a" "$WORK/sqlite3.o"
cp "$src/sqlite3.h" "$src/sqlite3ext.h" "$out/include/"
# SQLite is in the public domain, as sqlite3.h's own header says.
licenses sqlite "$src/sqlite3.h"

# libffi: its configure.
src="$WORK/libffi"
unpack libffi-3.4.8.tar.gz "$src"
b="$WORK/libffi-build"
rm -rf "$b" && mkdir -p "$b"
(cd "$b" && "$src/configure" -q ${host:+--host="$host"} --prefix="$out" \
    --disable-shared --enable-static --with-pic --disable-docs --disable-multi-os-directory)
make -s -C "$b" -j"$JOBS"
make -s -C "$b" install
licenses libffi "$src/LICENSE"

# OpenSSL: its Configure, libcrypto and libssl alone, without assembly (its
# ciphers and digests in portable C) and without loadable modules, engines or
# the legacy provider. Linux and macOS read certificates from /etc/ssl.
src="$WORK/openssl"
unpack openssl-3.5.8.tar.gz "$src"
dir="--openssldir=/etc/ssl"
[ "$platform" = windows-x86_64 ] && dir=""
# The flags go on Configure's command line, which adds them to the target's
# own; CFLAGS in the environment would replace those.
# shellcheck disable=SC2086
(cd "$src" && env -u CFLAGS perl ./Configure "$ossl" no-shared no-tests no-docs no-apps \
    no-module no-engine no-dso no-legacy no-asm $dir --prefix="$out" --libdir=lib $CFLAGS)
make -s -C "$src" -j"$JOBS" build_libs
make -s -C "$src" install_dev
licenses openssl "$src/LICENSE.txt"

# The static libraries and their headers alone: no shared libraries,
# pkg-config or CMake files, programs or manuals.
rm -rf "$out/bin" "$out/share" "$out/lib/pkgconfig" "$out/lib/cmake" "$out/lib"/*.la
for f in libz.a libbz2.a liblzma.a libzstd.a libsqlite3.a libffi.a libcrypto.a libssl.a; do
    test -f "$out/lib/$f" || die "no $f"
done
extra="$(ls "$out/lib" | grep -v -E '^lib(z|bz2|lzma|zstd|sqlite3|ffi|crypto|ssl)\.a$' || true)"
[ -z "$extra" ] || die "unexpected in lib/: $extra"
if [ -n "$check" ]; then
    "$PYTHON" -I "$CPYTHON_DIR/check_hidden.py" "$check" "$out"/lib/*.a
fi
log "$platform: $(du -sh "$out" | cut -f1)"
