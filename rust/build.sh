#!/bin/sh
# rustc and its tools, and the standard library, built against the LLVM
# library rust/neollvm.sh makes (neojac's libneollvm at run time), on
# linux-x86_64, for every host and target from there.
#
#   rust/build.sh host <host> <out>   rustc (with rustdoc), cargo, clippy and
#       rustfmt for <host>, under <out>/rust/host/<host>/: one of
#       x86_64-unknown-linux-gnu, aarch64-unknown-linux-gnu,
#       aarch64-apple-darwin, x86_64-pc-windows-gnullvm
#   rust/build.sh std <out>           the standard library of every target,
#       under <out>/rust/target/<target>/ (what a sysroot's
#       lib/rustlib/<target>/ holds)
#
# Every target's C compiler and linker is Zig's cc, at the target's floor:
# glibc 2.17, musl, macOS (with the runtimes slice's framework stubs), the
# Universal CRT with mingw-w64 and libunwind (rustc's gnullvm targets), WASI.
# The compiler runtime is compiler-rt's builtins as the runtimes slice ships
# them; the standard library's C (compiler-rt's profiling runtime) is LLVM
# 22.1.8's, as LLVM itself is: rustc's source tree carries Rust's own LLVM,
# which this build replaces with the upstream release's compiler-rt and
# libunwind. Nothing is taken from the machine that builds: no system library
# (pkg-config is disabled), no C toolchain but Zig.
#
# rustc's source is patched once (rustc-llvm-wrapper-in-llvm.patch): it links
# the LLVM library alone, which carries rustc's LLVM wrapper itself.
RUNTIMES_DIR="$(cd "$(dirname "$0")/../runtimes" && pwd)"
. "$RUNTIMES_DIR/lib.sh"
RUST_DIR="$(cd "$RUNTIMES_DIR/../rust" && pwd)"
SOURCES="$RUNTIMES_DIR/sources.txt $RUST_DIR/sources.txt"
RUST_VERSION=1.99.0
BUILD=x86_64-unknown-linux-gnu
HOSTS="x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu aarch64-apple-darwin x86_64-pc-windows-gnullvm"
TARGETS="x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu x86_64-unknown-linux-musl aarch64-unknown-linux-musl
    x86_64-apple-darwin aarch64-apple-darwin x86_64-pc-windows-gnullvm wasm32-wasip1"

mode="$1"
case "$mode" in
    host) host="$2"; out="$3" ;;
    std) out="$2" ;;
    *) die "usage: rust/build.sh host <host> <out> | std <out>" ;;
esac
case " $HOSTS " in *" ${host:-$BUILD} "*) ;; *) die "no host ${host:-}; one of $HOSTS" ;; esac
mkdir -p "$out"
out="$(cd "$out" && pwd)"

# zig_target <rust target>: the target Zig's cc compiles and links for.
zig_target() {
    case "$1" in
        x86_64-unknown-linux-gnu) echo x86_64-linux-gnu.2.17 ;;
        aarch64-unknown-linux-gnu) echo aarch64-linux-gnu.2.17 ;;
        x86_64-unknown-linux-musl) echo x86_64-linux-musl ;;
        aarch64-unknown-linux-musl) echo aarch64-linux-musl ;;
        x86_64-apple-darwin) echo x86_64-macos ;;
        aarch64-apple-darwin) echo aarch64-macos ;;
        x86_64-pc-windows-gnullvm) echo x86_64-windows-gnu ;;
        wasm32-wasip1) echo wasm32-wasi ;;
    esac
}

# runtimes_target <rust target>: the runtimes slice's directory for it.
runtimes_target() {
    case "$1" in
        *-apple-darwin) echo "${1%%-*}-macos" ;;
        *-windows-gnullvm) echo x86_64-windows-gnu ;;
        wasm32-wasip1) echo wasm32-wasi ;;
        *) echo "$1" | sed 's/-unknown//' ;;
    esac
}

# rustc's source tree, once: the release, Rust's LLVM replaced by the upstream
# release's compiler-rt and libunwind (and the CMake modules they read), the
# patch applied.
src="$WORK/rust-src"
if [ ! -f "$src/.prepared" ]; then
    unpack "rustc-$RUST_VERSION-src.tar.xz" "$src"
    rm -rf "$src/src/llvm-project"
    mkdir -p "$src/src/llvm-project"
    # Assigned first: a failed fetch stops the script.
    llvm_src="$(fetch llvm-project-22.1.8.src.tar.xz)"
    tar -xf "$llvm_src" -C "$src/src/llvm-project" --strip-components=1 \
        llvm-project-22.1.8.src/compiler-rt llvm-project-22.1.8.src/libunwind llvm-project-22.1.8.src/cmake \
        llvm-project-22.1.8.src/runtimes llvm-project-22.1.8.src/llvm/cmake
    (cd "$src" && patch -p1 < "$RUST_DIR/rustc-llvm-wrapper-in-llvm.patch")
    touch "$src/.prepared"
fi

# The LLVM library, and every host's library to link against.
neollvm="$WORK/neollvm-out"
if [ ! -f "$neollvm/exports.txt" ]; then
    sh "$RUST_DIR/neollvm.sh" "$src" "$neollvm"
fi

# The runtimes slice: every target's compiler-rt builtins and musl, and the
# macOS frameworks' stubs; and wasi-libc's sysroot.
runtimes="$WORK/runtimes"
if [ ! -f "$runtimes/SOURCES.txt" ]; then
    rm -rf "$runtimes"
    mkdir -p "$runtimes"
    zip="$(fetch llvm-22.1.8-runtimes-dev.zip)"
    (cd "$runtimes" && unzip -q "$zip")
fi
wasi="$WORK/wasi-sysroot"
if [ ! -f "$wasi/lib/wasm32-wasip1/crt1-command.o" ]; then
    unpack wasi-sysroot-34.0.tar.gz "$wasi"
fi
frameworks="$runtimes/libc/darwin/System/Library/Frameworks"

# Every target's tools, by one path each, as rustc's bootstrap and the cc
# crate run them. The cc crate tells a Clang its target with --target=, and
# rustc tells a macOS linker with -arch: Zig's cc has its target from -target
# already, so the wrappers leave both out.
tools="$WORK/tools"
rm -rf "$tools"
mkdir -p "$tools"
printf '#!/bin/sh\nexec zig ar "$@"\n' > "$tools/ar"
printf '#!/bin/sh\nexec zig ranlib "$@"\n' > "$tools/ranlib"
for t in $TARGETS; do
    extra=""
    case "$t" in
        *-apple-darwin) extra="-F$frameworks -iframework$frameworks" ;;
    esac
    for lang in cc c++; do
        cat > "$tools/$t-$lang" <<EOF
#!/bin/sh
skip=""
for a do
    shift
    if [ -n "\$skip" ]; then skip=""; continue; fi
    case "\$a" in
        --target=*) continue ;;
        -arch) skip=1; continue ;;
    esac
    set -- "\$@" "\$a"
done
exec zig $lang -target $(zig_target "$t") -g0 $extra "\$@"
EOF
    done
done
chmod +x "$tools"/*

# llvm-config for each host's LLVM library: what rustc's build asks of it.
components="ipo bitreader bitwriter linker asmparser lto coverage instrumentation
    aarch64 amdgpu arm avr bpf hexagon lanai loongarch mips msp430 nvptx powerpc riscv sparc spirv
    systemz ve webassembly x86 xcore"
for h in $HOSTS; do
    cat > "$tools/llvm-config-$h" <<EOF
#!/bin/sh
# The LLVM library rustc for $h links: LLVM 22.1.8 with rustc's LLVM wrapper,
# exporting only C symbols (rust/neollvm.sh).
for a do
    case "\$a" in
        --version) echo 22.1.8 ;;
        --components) echo $(echo $components) ;;
        --libdir | --bindir) echo "$neollvm/$h" ;;
        --libs) echo -lneollvm ;;
        --ldflags) echo "-L$neollvm/$h" ;;
        --cxxflags | --system-libs) echo ;;
        --shared-mode) echo shared ;;
        --help) echo "usage: llvm-config <option>..." >&2 ;;
        --link-static | --link-shared) ;;
        -*) echo "llvm-config: unsupported option \$a" >&2; exit 1 ;;
    esac
done
EOF
    chmod +x "$tools/llvm-config-$h"
done

# The build's configuration.
if [ "$mode" = host ]; then
    hosts="$host"
    targets="$host"
else
    hosts="$BUILD"
    targets="$TARGETS"
fi
quote() { printf '"%s"' "$1"; }
list() { printf '['; sep=""; for x in $1; do printf '%s"%s"' "$sep" "$x"; sep=", "; done; printf ']'; }
config="$src/bootstrap.toml"
{
    echo 'change-id = "ignore"'
    echo
    echo '[llvm]'
    echo 'download-ci-llvm = false'
    echo
    echo '[build]'
    echo "build = $(quote $BUILD)"
    echo "host = $(list "$hosts")"
    echo "target = $(list "$targets")"
    echo 'docs = false'
    echo 'extended = true'
    echo 'tools = ["cargo", "clippy", "rustdoc", "rustfmt"]'
    echo 'sanitizers = false'
    echo 'profiler = false'
    echo 'vendor = true'
    echo 'locked-deps = true'
    echo 'submodules = false'
    echo 'cargo-native-static = true'
    echo "jobs = $JOBS"
    echo
    echo '[rust]'
    echo 'channel = "stable"'
    echo 'lld = false'
    echo 'llvm-tools = false'
    echo 'llvm-bitcode-linker = false'
    echo 'codegen-backends = ["llvm"]'
    echo 'debuginfo-level-std = 1'
    echo
    echo '[dist]'
    echo 'compression-formats = ["xz"]'
    echo 'compression-profile = "fast"'
    echo 'include-mingw-linker = false'
    for t in $BUILD $hosts $targets; do echo "$t"; done | sort -u | while read -r t; do
        echo
        echo "[target.$t]"
        echo "cc = $(quote "$tools/$t-cc")"
        echo "cxx = $(quote "$tools/$t-c++")"
        echo "ar = $(quote "$tools/ar")"
        echo "ranlib = $(quote "$tools/ranlib")"
        echo "linker = $(quote "$tools/$t-cc")"
        echo "optimized-compiler-builtins = $(quote "$runtimes/targets/$(runtimes_target "$t")/libclang_rt.builtins.a")"
        case " $HOSTS " in *" $t "*) echo "llvm-config = $(quote "$tools/llvm-config-$t")" ;; esac
        case "$t" in
            wasm32-*) echo "wasi-root = $(quote "$wasi")" ;;
            *) echo 'profiler = true' ;;
        esac
        case "$t" in
            *-linux-musl) echo "musl-libdir = $(quote "$runtimes/targets/$(runtimes_target "$t")")" ;;
            x86_64-unknown-linux-gnu) echo 'default-linker-linux-override = "off"' ;;
        esac
    done
} > "$config"
log "bootstrap.toml:"
cat "$config" >&2

# The compiler the build makes runs against the LLVM library; nothing from the
# machine's own libraries reaches it.
export LLVM_PROVIDES_RUSTC_WRAPPER=1
export LD_LIBRARY_PATH="$neollvm/$BUILD"
export PKG_CONFIG=/bin/false
cd "$src"
rm -rf build/dist
if [ "$mode" = host ]; then
    python3 x.py dist --host "$host" --target "$host" rustc cargo clippy rustfmt
else
    python3 x.py dist rust-std
fi

# What the tarballs install, without the installer's own files: each
# component's tree under its directory.
dist="$WORK/dist"
rm -rf "$dist"
mkdir -p "$dist"
for tarball in build/dist/*.tar.xz; do
    tar -xJf "$tarball" -C "$dist"
done
install_components() { # install_components <dir> <into>
    for c in "$1"/*/; do
        [ -f "$c/manifest.in" ] || continue
        (cd "$c" && find . -type f ! -name manifest.in | while read -r f; do
            mkdir -p "$2/$(dirname "$f")"
            cp -p "$f" "$2/$f"
        done)
    done
}
if [ "$mode" = host ]; then
    dest="$out/rust/host/$host"
    rm -rf "$dest"
    for d in "$dist"/*/; do install_components "$d" "$dest"; done
    test -x "$dest/bin/rustc" || test -f "$dest/bin/rustc.exe"
    log "rust/host/$host: $(du -sh "$dest" | cut -f1)"
else
    for t in $TARGETS; do
        dest="$out/rust/target/$t"
        rm -rf "$dest"
        mkdir -p "$dest"
        tmp="$WORK/std-$t"
        rm -rf "$tmp"
        install_components "$dist/rust-std-$RUST_VERSION-$t" "$tmp"
        cp -Rp "$tmp/lib/rustlib/$t/." "$dest/"
        ls "$dest/lib" | grep -q '^libstd-' || die "no standard library for $t"
        log "rust/target/$t: $(du -sh "$dest" | cut -f1)"
    done
fi
