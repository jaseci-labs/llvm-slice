#!/bin/sh
# mingw-w64 for x86_64 Windows against the Universal CRT, built by its own
# configure and make with Clang (the order llvm-mingw builds it in): the
# headers, the CRT (start files, libmingw32.a, libmingwex.a, the import
# libraries), compiler-rt's builtins, winpthreads, then LLVM's C++ runtime;
# and zlib, by its own MinGW makefile.
#
#   runtimes/mingw.sh <out>
#
# Writes <out>/x86_64-w64-mingw32/{include,lib} (the sysroot) and <out>/cxx
# (llvm-runtimes.sh's output for the target).
. "$(dirname "$0")/lib.sh"
out="$(mkdir -p "$1" && cd "$1" && pwd)"
llvm_toolchain

triple=x86_64-w64-mingw32
src="$WORK/mingw-w64"
unpack mingw-w64-v14.0.0.tar.bz2 "$src"
# Two fixes to its headers, which its master lacks too (runtimes/patches/):
# <intrin.h> after <cpuid.h>, and the Universal CRT's per-thread invalid
# parameter handler, which its import libraries export but no header declared.
for p in mingw-w64-intrin-cpuid-order.patch mingw-w64-thread-local-invalid-parameter-handler.patch; do
    (cd "$src" && patch -p1 < "$RUNTIMES_DIR/patches/$p")
done
rm -rf "$out/$triple"
prefix="$out/$triple"
cc="$LLVM/bin/clang --target=$triple --sysroot=$out -fuse-ld=lld -rtlib=compiler-rt -unwindlib=none"
tools="AR=$LLVM/bin/llvm-ar RANLIB=$LLVM/bin/llvm-ranlib DLLTOOL=$LLVM/bin/llvm-dlltool NM=$LLVM/bin/llvm-nm STRIP=$LLVM/bin/llvm-strip"
# winpthreads compiles its version resource, against the headers above.
rc="$LLVM/bin/llvm-windres --target=pe-x86-64 -I$prefix/include"

# Windows 10 and the Universal CRT by default, as neojac targets them.
b="$WORK/mingw-headers"
rm -rf "$b" && mkdir -p "$b"
(cd "$b" && "$src/mingw-w64-headers/configure" --host="$triple" --prefix="$prefix" \
    --enable-idl --with-default-win32-winnt=0xa00 --with-default-msvcrt=ucrt)
make -s -C "$b" install

b="$WORK/mingw-crt"
rm -rf "$b" && mkdir -p "$b"
# shellcheck disable=SC2086
(cd "$b" && "$src/mingw-w64-crt/configure" --host="$triple" --prefix="$prefix" \
    --disable-lib32 --enable-lib64 --disable-libarm32 --disable-libarm64 \
    --with-default-msvcrt=ucrt CC="$cc" CFLAGS=-O2 $tools)
make -s -C "$b" -j"$JOBS"
make -s -C "$b" install

# compiler-rt's builtins, where Clang finds them for the target, so the
# libraries that follow link their configure checks.
MINGW_SYSROOT="$out" sh "$RUNTIMES_DIR/llvm-runtimes.sh" "$triple" "$out/builtins" builtins
res="$("$LLVM/bin/clang" -print-resource-dir)"
mkdir -p "$res/lib/windows"
cp "$out/builtins/lib/libclang_rt.builtins.a" "$res/lib/windows/libclang_rt.builtins-x86_64.a"

b="$WORK/mingw-winpthreads"
rm -rf "$b" && mkdir -p "$b"
# shellcheck disable=SC2086
(cd "$b" && "$src/mingw-w64-libraries/winpthreads/configure" --host="$triple" --prefix="$prefix" \
    --enable-static --disable-shared CC="$cc" CFLAGS=-O2 RC="$rc" $tools)
make -s -C "$b" -j"$JOBS"
make -s -C "$b" install

MINGW_SYSROOT="$out" sh "$RUNTIMES_DIR/llvm-runtimes.sh" "$triple" "$out/cxx" cxx

# zlib, which Windows ships no DLL of: its own MinGW build (win32/Makefile.gcc)
# of the static library, with its headers, so C programs and neojac's own
# (whose zlib module needs it) link it into themselves.
z="$WORK/zlib-mingw"
unpack zlib-1.3.1.tar.gz "$z"
# shellcheck disable=SC2086
make -s -C "$z" -f win32/Makefile.gcc libz.a CC="$cc" CFLAGS="-O2 -Wall" AR="$LLVM/bin/llvm-ar" ARFLAGS=rcs
cp "$z/libz.a" "$prefix/lib/libz.a"
cp "$z/zlib.h" "$z/zconf.h" "$prefix/include/"

for f in crt2.o crt2u.o dllcrt2.o libmingw32.a libmingwex.a libmoldname.a libucrt.a libkernel32.a libwinpthread.a libz.a; do
    test -f "$prefix/lib/$f" || die "mingw-w64 installed no $f"
done
log "$triple: $(ls "$prefix/lib" | wc -l) libraries, $(du -sh "$prefix/lib" | cut -f1)"
