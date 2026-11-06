#!/bin/sh
# What a compiler needs to build and link macOS programs without Xcode, from the
# macOS SDK of the machine this runs on (the workflow's runner):
#
#   <out>/include          the SDK's usr/include, but for its libstdc++/libc++
#                          headers (c++/), which LLVM's own libc++ replaces
#   <out>/libSystem.tbd    the SDK's stub of libSystem, restricted to the
#                          architectures the pinned LLVM's TextAPI reads
#   <out>/frameworks/<name>.framework/{Headers/,<name>.tbd}
#                          the frameworks below: each one's headers, and its
#                          stub restricted as libSystem's is
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

# The frameworks besides libSystem that the programs neojac builds link:
# CPython's _scproxy, which urllib.request imports on macOS, reads the system's
# proxy settings through SystemConfiguration, whose headers include
# CoreFoundation's and Security's. Each is laid out flat (no Versions/ or
# symbolic links), as Clang's -iframework and LLD's -syslibroot find it.
FRAMEWORKS="CoreFoundation Security SystemConfiguration"
rm -rf "$out/frameworks"
for f in $FRAMEWORKS; do
    src="$sdk/System/Library/Frameworks/$f.framework"
    dst="$out/frameworks/$f.framework"
    mkdir -p "$dst/Headers"
    (cd "$src/Headers/" && COPYFILE_DISABLE=1 tar -cf - .) | (cd "$dst/Headers" && tar -xf -)
    python3 "$RUNTIMES_DIR/tbd_targets.py" "$LLVM_SRC/llvm/include/llvm/TextAPI/Architecture.def" \
        "$src/$f.tbd" "$dst/$f.tbd"
done

# The stubs must be ones LLD reads, and the frameworks' headers whole: compile a
# program that includes each framework's umbrella header, with only these
# headers and Clang's own, and link it, calling into each framework, for both
# arches, against these stubs alone (a system root holding only the frameworks;
# what libSystem re-exports resolves inside its stub), as a link on a machine
# without the SDK does.
rm -rf "$WORK/tbd-root"
mkdir -p "$WORK/tbd-root/System/Library"
cp -R "$out/frameworks" "$WORK/tbd-root/System/Library/Frameworks"
cat > "$WORK/tbd-check.c" <<'EOF'
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <SystemConfiguration/SystemConfiguration.h>

int main(void) {
    unsigned char b[8];
    CFDictionaryRef proxies = SCDynamicStoreCopyProxies(NULL);
    if (proxies != NULL) {
        CFRelease(proxies);
    }
    return SecRandomCopyBytes(kSecRandomDefault, sizeof b, b);
}
EOF
resource="$("$LLVM/bin/clang" -print-resource-dir)/include"
framework_args=""
for f in $FRAMEWORKS; do framework_args="$framework_args -framework $f"; done
for t in arm64-apple-macosx14.0 x86_64-apple-macosx14.0; do
    "$LLVM/bin/clang" -target "$t" -nostdinc -isystem "$resource" -isystem "$out/include" \
        -iframework "$out/frameworks" -c "$WORK/tbd-check.c" -o "$WORK/tbd-check.o"
    "$LLVM/bin/ld64.lld" -arch "${t%%-*}" -platform_version macos 14.0 14.0 -syslibroot "$WORK/tbd-root" \
        -fatal_warnings -o "$WORK/tbd-check" \
        "$WORK/tbd-check.o" "$out/libSystem.tbd" $framework_args
done

for arch in aarch64 x86_64; do
    triple="$(echo "$arch" | sed 's/^aarch64$/arm64/')-apple-macosx"
    SDKROOT="$sdk" sh "$RUNTIMES_DIR/llvm-runtimes.sh" "$triple" "$out/$arch-builtins" builtins
    SDKROOT="$sdk" sh "$RUNTIMES_DIR/llvm-runtimes.sh" "$triple" "$out/$arch" cxx
    cp "$out/$arch-builtins/lib/libclang_rt.builtins.a" "$out/$arch/lib/"
    rm -rf "$out/$arch-builtins"
done

log "SDK $(cat "$out/SDK_VERSION"): $(find "$out/include" "$out/frameworks" -name '*.h' | wc -l) headers"
