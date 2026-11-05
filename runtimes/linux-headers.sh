#!/bin/sh
# Linux's user-space API headers for x86_64 and arm64, as the kernel's own
# `make headers_install` writes them.
#
#   runtimes/linux-headers.sh <out>
#
# Writes <out>/x86_64/include and <out>/aarch64/include. Needs make and a host
# C compiler (the kernel's scripts are built for the host).
. "$(dirname "$0")/lib.sh"
out="$(mkdir -p "$1" && cd "$1" && pwd)"

src="$WORK/linux"
unpack linux-7.0.tar.xz "$src"
for pair in x86_64:x86_64 aarch64:arm64; do
    arch="${pair%%:*}"
    karch="${pair#*:}"
    rm -rf "$out/$arch"
    make -s -C "$src" ARCH="$karch" INSTALL_HDR_PATH="$out/$arch" headers_install
    test -f "$out/$arch/include/linux/version.h"
    test -d "$out/$arch/include/asm"
    log "$arch: $(find "$out/$arch/include" -name '*.h' | wc -l) headers"
done
