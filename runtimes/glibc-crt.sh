#!/bin/sh
# The files glibc links into every program it runs, for one glibc release on the
# machine's own architecture: crt1.o, Scrt1.o, crti.o, crtn.o, libc_nonshared.a
# and, for a release before 2.28, libpthread_nonshared.a (pthread_atfork, which
# libpthread.so's linker script links from it until 2.28 moved it into
# libc_nonshared.a), from a full build of that release by its own configure and
# make.
#
#   runtimes/glibc-crt.sh <version> <out>
#
# glibc builds only with GCC, and an old release only with a GCC and binutils
# of its time: run this in a distribution of the release's era (the workflow
# uses centos:7 for 2.17, fedora:34 for 2.33 and fedora:35 for 2.34), with gcc,
# make, gawk, bison, perl and python3 installed.
. "$(dirname "$0")/lib.sh"
version="$1"
out="$(mkdir -p "$2" && cd "$2" && pwd)"

src="$WORK/glibc-$version"
build="$WORK/glibc-build-$version"
unpack "glibc-$version.tar.xz" "$src"
rm -rf "$build"
mkdir -p "$build"
# Optimized as glibc requires, without debug info (configure's default CFLAGS
# are -g -O2). Into a prefix of its own, never installed: the build writes some
# headers to <prefix>/include as it goes, and with /usr there 2.17 rewrites the
# stdc-predef.h GCC includes in every compilation, and so rebuilds forever.
(cd "$build" && "$src/configure" --prefix="$WORK/glibc-prefix-$version" --disable-werror --disable-profile CFLAGS=-O2 CXXFLAGS=-O2)
make -s -C "$build" -j"$JOBS"
for f in csu/crt1.o csu/Scrt1.o csu/crti.o csu/crtn.o libc_nonshared.a; do
    cp "$build/$f" "$out/"
done
if [ -f "$build/nptl/libpthread_nonshared.a" ]; then
    cp "$build/nptl/libpthread_nonshared.a" "$out/"
fi
if readelf -S --wide "$out"/*.o "$out"/*.a | grep -q '\.debug_info'; then
    die "glibc $version: the start files carry debug info"
fi
log "glibc $version ($(uname -m)): $(ls "$out" | tr '\n' ' ')"
