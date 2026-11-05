#!/bin/sh
# musl for one architecture, built by musl's own configure and make with Clang:
# its headers and the static C library with its start files.
#
#   runtimes/musl.sh <x86_64|aarch64> <out>
#
# Writes <out>/include and <out>/lib (libc.a, crt1.o, rcrt1.o, Scrt1.o, crti.o,
# crtn.o, and the empty libm.a, libpthread.a, ... musl installs beside libc.a).
. "$(dirname "$0")/lib.sh"
arch="$1"
out="$(mkdir -p "$2" && cd "$2" && pwd)"
llvm_toolchain

src="$WORK/musl-$arch"
unpack musl-1.2.6.tar.gz "$src"
for p in musl-CVE-2026-40200.patch musl-CVE-2026-107891.patch; do
    (cd "$src" && patch -p1 < "$(fetch "$p")")
done

triple="$arch-linux-musl"
build="$WORK/musl-build-$arch"
rm -rf "$build" "$out"
mkdir -p "$build"
# Static only: neojac links musl programs statically. Clang compiles PIE by
# default, so libc.a also links into static PIE programs (rcrt1.o).
(cd "$build" && "$src/configure" \
    --target="$triple" \
    --prefix=/ \
    --disable-shared \
    CC="$LLVM/bin/clang --target=$triple -fuse-ld=lld" \
    AR="$LLVM/bin/llvm-ar" \
    RANLIB="$LLVM/bin/llvm-ranlib" \
    LIBCC=)
make -s -C "$build" -j"$JOBS"
make -s -C "$build" DESTDIR="$out" install
for f in libc.a crt1.o rcrt1.o Scrt1.o crti.o crtn.o; do test -f "$out/lib/$f"; done
test -f "$out/include/bits/alltypes.h"
log "$triple: $(du -sh "$out/lib/libc.a" | cut -f1) libc.a"
