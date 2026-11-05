#!/bin/sh
# What a compiler needs to build and link macOS programs without Xcode, from the
# macOS SDK of the machine this runs on (the workflow's runner):
#
#   <out>/include          the SDK's usr/include, but for its libstdc++/libc++
#                          headers (c++/), which LLVM's own libc++ replaces
#   <out>/libSystem.tbd    the SDK's stub of libSystem, restricted to the
#                          architectures the pinned LLVM's TextAPI reads
#   <out>/SDK_VERSION
#   <out>/<arch>/lib       compiler-rt's builtins and LLVM's C++ runtime for
#                          macOS 14.0 and later, arm64 and x86_64
#
#   runtimes/darwin.sh <out>
. "$(dirname "$0")/lib.sh"
out="$(mkdir -p "$1" && cd "$1" && pwd)"
llvm_toolchain
llvm_sources

sdk="$(xcrun --sdk macosx --show-sdk-path)"
xcrun --sdk macosx --show-sdk-version > "$out/SDK_VERSION"
rm -rf "$out/include"
mkdir -p "$out/include"
(cd "$sdk/usr/include" && COPYFILE_DISABLE=1 tar -cf - --exclude ./c++ .) | (cd "$out/include" && tar -xf -)

# A recent SDK's stubs also list architectures (arm64e.x1) that the pinned
# LLVM's TextAPI does not know, and it then rejects the whole stub. Keep, in
# every target list, the targets whose architecture TextAPI knows
# (llvm/TextAPI/Architecture.def at the pinned LLVM). arm64 programs link
# against the arm64e entries, which TextAPI treats as compatible.
python3 "$RUNTIMES_DIR/tbd_targets.py" "$LLVM_SRC/llvm/include/llvm/TextAPI/Architecture.def" \
    "$sdk/usr/lib/libSystem.tbd" "$out/libSystem.tbd"

for arch in aarch64 x86_64; do
    triple="$(echo "$arch" | sed 's/^aarch64$/arm64/')-apple-macosx"
    SDKROOT="$sdk" sh "$RUNTIMES_DIR/llvm-runtimes.sh" "$triple" "$out/$arch-builtins" builtins
    SDKROOT="$sdk" sh "$RUNTIMES_DIR/llvm-runtimes.sh" "$triple" "$out/$arch" cxx
    cp "$out/$arch-builtins/lib/libclang_rt.builtins.a" "$out/$arch/lib/"
    rm -rf "$out/$arch-builtins"
done

# The stub must be one LLD reads: link a program against it, for both arches,
# resolving what libSystem re-exports inside the stub (an empty system root), as
# a link on a machine without the SDK does.
mkdir -p "$WORK/empty-root"
printf 'int main(void) { return 0; }\n' > "$WORK/tbd-check.c"
for t in arm64-apple-macosx14.0 x86_64-apple-macosx14.0; do
    "$LLVM/bin/clang" -target "$t" -nostdinc -isystem "$out/include" -c "$WORK/tbd-check.c" -o "$WORK/tbd-check.o"
    "$LLVM/bin/ld64.lld" -arch "${t%%-*}" -platform_version macos 14.0 14.0 -syslibroot "$WORK/empty-root" \
        -fatal_warnings -o "$WORK/tbd-check" \
        "$WORK/tbd-check.o" "$out/libSystem.tbd"
done
log "SDK $(cat "$out/SDK_VERSION"): $(find "$out/include" -name '*.h' | wc -l) headers"
