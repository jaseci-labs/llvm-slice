#!/bin/sh
# Build LLVM <version> from source against musl and install its dev surface to
# <prefix>. musl has no upstream LLVM release, so this slice is built (not
# repackaged) and handed to repackage.jac --work-dir like any other platform.
# Runs in Alpine; g++/libstdc++ matches upstream's Linux ABI and the consumer's
# musl shim. All targets, for parity with the official release.
#
# Usage: build_llvm_musl.sh <prefix> <version> [targets]
set -eux

PREFIX="$1"
VERSION="$2"
TARGETS="${3:-all}"

apk add --no-cache build-base cmake samurai git python3 \
    zlib-dev zstd-dev libxml2-dev

SRC=/mnt/llvm-src
BUILD=/mnt/llvm-build
git clone --depth 1 --branch "llvmorg-${VERSION}" \
    https://github.com/llvm/llvm-project "$SRC"
# Pin the exact source commit for provenance (the workflow records it).
git -C "$SRC" rev-parse HEAD > "${PREFIX}.source-sha"

# Static component .a only -- BUILD_SHARED_LIBS=OFF (per-component .so) and the
# two DYLIB flags (single libLLVM.so) -- with the same external codecs upstream
# enables so LLVMConfig records the matching -lz/-lzstd/-lxml2 link deps.
cmake -S "$SRC/llvm" -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DLLVM_ENABLE_PROJECTS="" \
    -DLLVM_TARGETS_TO_BUILD="$TARGETS" \
    -DLLVM_ENABLE_ZLIB=FORCE_ON \
    -DLLVM_ENABLE_ZSTD=FORCE_ON \
    -DLLVM_ENABLE_LIBXML2=FORCE_ON \
    -DLLVM_BUILD_LLVM_DYLIB=OFF \
    -DLLVM_LINK_LLVM_DYLIB=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DCMAKE_INSTALL_PREFIX="$PREFIX"

cmake --build "$BUILD" --target install

# Keep only the dev surface (lib/, include/, bin/llvm-config); build_dev_zip
# zips the whole tree, so a full install would bloat the slice with LLVM's tools.
find "$PREFIX/bin" -mindepth 1 ! -name 'llvm-config' -exec rm -rf {} + 2>/dev/null || true
rm -rf "$PREFIX/share" "$PREFIX/libexec"

# Guard against a glibc leak. Static .a carry no GLIBC_ version refs (those bind
# at link time), so assert on llvm-config -- the one linked artifact the same
# toolchain produced; a glibc build would tag its dynamic symbols GLIBC_*.
if objdump -T "$PREFIX/bin/llvm-config" 2>/dev/null | grep -q "GLIBC_"; then
    echo "ERROR: llvm-config references GLIBC_ symbols -- build is not musl" >&2
    exit 1
fi
