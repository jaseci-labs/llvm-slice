#!/bin/sh
# What a linker needs to target any glibc release from 2.17 on, without one:
#
#   <out>/abilist/<arch>.abilist  every symbol each library of every release
#       from 2.17 to 2.44 exports, at every version node it is exported at,
#       with the releases that export it (abilists.py merges glibc's own lists,
#       the test data of its ABI checks)
#   <out>/abilist/VERSION  the newest release
#   <out>/include/{generic-glibc,x86-linux-gnu,aarch64-linux-gnu}  glibc's
#       headers as Zig 0.17.0 curates them: one set for every release, whose
#       declarations follow -D__GLIBC_MINOR__
#
#   runtimes/glibc-data.sh <out>
. "$(dirname "$0")/lib.sh"
out="$(mkdir -p "$1" && cd "$1" && pwd)"

trees=""
for minor in $(seq 17 44); do
    src="$WORK/glibc-abi-2.$minor"
    unpack "glibc-2.$minor.tar.xz" "$src" "*/sysdeps/unix/sysv/linux/x86_64/*.abilist" \
        "*/sysdeps/unix/sysv/linux/aarch64/*.abilist" "*/version.h"
    trees="$trees $src"
done
rm -rf "$out/abilist"
# shellcheck disable=SC2086
python3 "$RUNTIMES_DIR/abilists.py" "$out/abilist" $trees

zig="$WORK/zig"
unpack zig-x86_64-linux-0.17.0.tar.xz "$zig" "*/lib/libc/include/generic-glibc/*" \
    "*/lib/libc/include/x86-linux-gnu/*" "*/lib/libc/include/aarch64-linux-gnu/*" "*/LICENSE"
rm -rf "$out/include"
mkdir -p "$out/include"
for d in generic-glibc x86-linux-gnu aarch64-linux-gnu; do
    cp -R "$zig/lib/libc/include/$d" "$out/include/$d"
done
cp "$zig/LICENSE" "$out/include/LICENSE.zig"
log "abilists to glibc $(cat "$out/abilist/VERSION"); $(find "$out/include" -name '*.h' | wc -l) glibc headers"
