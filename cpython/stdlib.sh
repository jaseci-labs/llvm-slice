#!/bin/sh
# CPython's standard library, as the interpreter a toolchain builds from
# CPython's C ships it, and the frozen modules that C compiles in, which a
# native build of the release writes (Programs/_freeze_module): CPython's own
# configure and make, with the host's C compiler. And typeshed's stubs of
# that standard library.
#
#   cpython/stdlib.sh <out>
#
# Writes <out>/lib/python3.15/, <out>/frozen/Python/frozen_modules/ and
# <out>/typeshed/ (cpython/stdlib.py says what each holds).
CPYTHON_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIMES_DIR="$CPYTHON_DIR/../runtimes"
SOURCES="$CPYTHON_DIR/sources.txt $RUNTIMES_DIR/sources.txt"
. "$RUNTIMES_DIR/lib.sh"
out="$(mkdir -p "$1" && cd "$1" && pwd)"

src="$WORK/cpython"
unpack Python-3.15.2.tar.xz "$src"
b="$WORK/cpython-build"
rm -rf "$b" && mkdir -p "$b"
(cd "$b" && "$src/configure" -q --disable-test-modules --without-ensurepip)
# Only what the frozen modules need: Programs/_freeze_module, the interpreter
# it bootstraps, and the headers they write.
targets="$(grep -o '^Python/frozen_modules/[^:]*\.h' "$b/Makefile" | sort -u)"
[ -n "$targets" ] || die "CPython's Makefile names no frozen modules"
# shellcheck disable=SC2086
make -s -C "$b" -j"$JOBS" $targets
ts="$WORK/typeshed"
unpack typeshed-13ffe24f8b9d0069a7a45c42eed3f5513e1472a1.tar.gz "$ts"
python3 -I "$CPYTHON_DIR/stdlib.py" "$src" "$b" "$ts" "$out"
