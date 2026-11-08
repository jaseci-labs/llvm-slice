#!/bin/sh
# rustc and its tools, and the standard library, built against the LLVM
# library rust/neollvm.sh makes (neojac's libneollvm at run time), each
# platform's with the platform's own C toolchain, as Rust's releases are.
#
#   rust/build.sh <platform> <out>
#
# writes rustc (with rustdoc), cargo, clippy and rustfmt for the platform's
# Rust host under <out>/rust/host/<host>/, and the standard library of the
# targets its toolchain builds under <out>/rust/target/<target>/ (what a
# sysroot's lib/rustlib/<target>/ holds):
#
#   linux-x86_64    run in manylinux2014 (CentOS 7: GCC, glibc 2.17):
#                   x86_64-unknown-linux-gnu; the standard library of it,
#                   x86_64-unknown-linux-musl and wasm32-wasip1
#   linux-aarch64   the same on aarch64: aarch64-unknown-linux-gnu; the
#                   standard library of it and aarch64-unknown-linux-musl
#   macos-aarch64   on macOS, with Xcode's Clang and SDK, for macOS 14.0:
#                   aarch64-apple-darwin; the standard library of it and
#                   x86_64-apple-darwin
#   windows-x86_64  on Linux, with llvm-mingw (Clang, LLD, mingw-w64, the
#                   Universal CRT, libunwind): x86_64-pc-windows-gnullvm and
#                   its standard library
#
# The musl and WASI standard libraries' C (no program links there) compiles
# with Zig's cc. Every target's compiler runtime is compiler-rt's builtins as
# the runtimes slice ships them, musl is the runtimes slice's, and wasi-libc
# wasi-sdk's sysroot. The standard library's C (compiler-rt's profiling
# runtime) is LLVM 22.1.8's, as LLVM itself is: rustc's source tree carries
# Rust's own LLVM, which this build replaces with the upstream release's
# compiler-rt and libunwind. No system library reaches a build (pkg-config is
# disabled).
#
# rustc's source is patched once: it links the LLVM library alone, which
# carries rustc's LLVM wrapper itself (rustc-llvm-wrapper-in-llvm.patch), and a
# cross-compiled rustc leaves out of its sysroot the proc macros built for the
# host it is for (bootstrap-cross-proc-macros.patch).
RUNTIMES_DIR="$(cd "$(dirname "$0")/../runtimes" && pwd)"
. "$RUNTIMES_DIR/lib.sh"
RUST_DIR="$(cd "$RUNTIMES_DIR/../rust" && pwd)"
SOURCES="$RUNTIMES_DIR/sources.txt $RUST_DIR/sources.txt"
RUST_VERSION=1.99.0

platform="$1"
out="$(mkdir -p "$2" && cd "$2" && pwd)"
case "$platform" in
    linux-x86_64)
        build=x86_64-unknown-linux-gnu
        host=$build
        targets="x86_64-unknown-linux-gnu x86_64-unknown-linux-musl wasm32-wasip1"
        ;;
    linux-aarch64)
        build=aarch64-unknown-linux-gnu
        host=$build
        targets="aarch64-unknown-linux-gnu aarch64-unknown-linux-musl"
        ;;
    macos-aarch64)
        build=aarch64-apple-darwin
        host=$build
        targets="aarch64-apple-darwin x86_64-apple-darwin"
        # neojac's macOS floor, which its runtime and libneollvm are built for.
        export MACOSX_DEPLOYMENT_TARGET=14.0
        ;;
    windows-x86_64)
        build=x86_64-unknown-linux-gnu
        host=x86_64-pc-windows-gnullvm
        targets=$host
        ;;
    *) die "usage: rust/build.sh linux-x86_64|linux-aarch64|macos-aarch64|windows-x86_64 <out>" ;;
esac

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
    for p in "$RUST_DIR"/*.patch; do
        (cd "$src" && patch -p1 < "$p")
    done
    touch "$src/.prepared"
fi

# What the build takes from the runtimes slice: every target's compiler-rt
# builtins, and musl (not the rest, whose mingw-w64 names differ only in case,
# which a case-insensitive file system would collapse); and wasi-libc's
# sysroot.
runtimes="$WORK/runtimes"
if [ ! -f "$runtimes/SOURCES.txt" ]; then
    rm -rf "$runtimes"
    mkdir -p "$runtimes"
    zip="$(fetch llvm-22.1.8-runtimes-dev.zip)"
    (cd "$runtimes" && unzip -q "$zip" SOURCES.txt 'targets/*/libclang_rt.builtins.a' 'targets/*-linux-musl/*')
fi
wasi="$WORK/wasi-sysroot"
case " $targets " in
    *" wasm32-wasip1 "*)
        [ -f "$wasi/lib/wasm32-wasip1/crt1-command.o" ] || unpack wasi-sysroot-34.0.tar.gz "$wasi"
        ;;
esac

# The LLVM library of the machine that builds (which runs the compiler the
# build makes), and of the host (to link against), when that is another.
neollvm="$WORK/neollvm"
case "$platform" in
    windows-x86_64) sh "$RUST_DIR/neollvm.sh" linux-x86_64 "$src" "$neollvm/$build" ;;
    *) sh "$RUST_DIR/neollvm.sh" "$platform" "$src" "$neollvm/$build" ;;
esac
if [ "$platform" = windows-x86_64 ]; then
    mingw="$WORK/llvm-mingw"
    [ -x "$mingw/bin/x86_64-w64-mingw32-clang" ] || unpack llvm-mingw-20261104-ucrt-ubuntu-22.04-x86_64.tar.xz "$mingw"
    # libneollvm.dll's import library: the functions the library exports.
    mkdir -p "$neollvm/$host"
    { echo "LIBRARY libneollvm.dll"; echo "EXPORTS"; sed 's/.*/    &/' "$neollvm/$build/exports.txt"; } \
        > "$neollvm/$host/neollvm.def"
    "$mingw/bin/llvm-dlltool" -m i386:x86-64 -d "$neollvm/$host/neollvm.def" -D libneollvm.dll \
        -l "$neollvm/$host/libneollvm.dll.a"
fi

# Each target's tools, by one path each, as rustc's bootstrap and the cc
# crate run them.
tools="$WORK/tools"
rm -rf "$tools"
mkdir -p "$tools"
# zig_cc <rust target> <zig target>: Zig's cc and c++ for a target whose C
# only compiles here. The cc crate tells a Clang its target with --target=;
# Zig's cc has it from -target already.
zig_cc() {
    for lang in cc c++; do
        cat > "$tools/$1-$lang" <<EOF
#!/bin/sh
for a do
    shift
    case "\$a" in --target=*) continue ;; esac
    set -- "\$@" "\$a"
done
exec zig $lang -target $2 -g0 "\$@"
EOF
    done
    printf '#!/bin/sh\nexec zig ar "$@"\n' > "$tools/$1-ar"
    printf '#!/bin/sh\nexec zig ranlib "$@"\n' > "$tools/$1-ranlib"
}
# native <rust target>: the machine's own C compiler, archiver and linker.
native() {
    for t in cc:cc c++:c++ ar:ar ranlib:ranlib; do
        printf '#!/bin/sh\nexec %s "$@"\n' "$(command -v "${t#*:}")" > "$tools/$1-${t%%:*}"
    done
}
for t in $build $targets; do
    case "$t" in
        *-linux-gnu | *-apple-darwin) native "$t" ;;
        *-linux-musl) zig_cc "$t" "${t%%-*}-linux-musl" ;;
        wasm32-wasip1) zig_cc "$t" wasm32-wasi ;;
        x86_64-pc-windows-gnullvm)
            for x in cc:clang c++:clang++; do
                printf '#!/bin/sh\nexec %s "$@"\n' "$mingw/bin/x86_64-w64-mingw32-${x#*:}" > "$tools/$t-${x%%:*}"
            done
            printf '#!/bin/sh\nexec %s "$@"\n' "$mingw/bin/llvm-ar" > "$tools/$t-ar"
            printf '#!/bin/sh\nexec %s "$@"\n' "$mingw/bin/llvm-ranlib" > "$tools/$t-ranlib"
            ;;
    esac
done
chmod +x "$tools"/*

# llvm_manifest <rust host>: the manifest of the LLVM slice neojac builds
# libneollvm from on that host, whose LLVM targets the host's rustc is built
# for (Windows' official LLVM carries fewer than the others).
llvm_manifest() {
    case "$1" in
        x86_64-unknown-linux-gnu) fetch llvm-22.1.8-x86_64-linux-libcxx-lld-r2-manifest.json ;;
        aarch64-unknown-linux-gnu) fetch llvm-22.1.8-aarch64-linux-libcxx-lld-r2-manifest.json ;;
        aarch64-apple-darwin) fetch llvm-22.1.8-aarch64-apple-darwin-manifest.json ;;
        x86_64-pc-windows-gnullvm) fetch llvm-22.1.8-x86_64-pc-windows-msvc-manifest.json ;;
    esac
}

# llvm-config for the LLVM libraries: what rustc's build asks of them.
for h in $build $host; do
    manifest="$(llvm_manifest "$h")"
    components="ipo bitreader bitwriter linker asmparser lto coverage instrumentation $(python3 -c \
        'import json, sys; print(" ".join(t.lower() for t in json.load(open(sys.argv[1]))["targets_to_build"]))' "$manifest")"
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
quote() { printf '"%s"' "$1"; }
list() { printf '['; sep=""; for x in $1; do printf '%s"%s"' "$sep" "$x"; sep=", "; done; printf ']'; }
{
    echo 'change-id = "ignore"'
    echo
    echo '[llvm]'
    echo 'download-ci-llvm = false'
    echo
    echo '[build]'
    echo "build = $(quote $build)"
    echo "host = $(list "$host")"
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
    # On Windows, the runtime DLLs the tools load (libunwind.dll) ship beside
    # rustc.exe; nowhere else is there one to ship.
    if [ "$platform" = windows-x86_64 ]; then
        echo 'include-mingw-linker = true'
    else
        echo 'include-mingw-linker = false'
    fi
    for t in $build $host $targets; do echo "$t"; done | sort -u | while read -r t; do
        echo
        echo "[target.$t]"
        echo "cc = $(quote "$tools/$t-cc")"
        echo "cxx = $(quote "$tools/$t-c++")"
        echo "ar = $(quote "$tools/$t-ar")"
        echo "ranlib = $(quote "$tools/$t-ranlib")"
        echo "linker = $(quote "$tools/$t-cc")"
        echo "optimized-compiler-builtins = $(quote "$runtimes/targets/$(runtimes_target "$t")/libclang_rt.builtins.a")"
        case " $build $host " in *" $t "*) echo "llvm-config = $(quote "$tools/llvm-config-$t")" ;; esac
        case "$t" in
            wasm32-*) echo "wasi-root = $(quote "$wasi")" ;;
            *) echo 'profiler = true' ;;
        esac
        case "$t" in
            *-linux-musl) echo "musl-libdir = $(quote "$runtimes/targets/$(runtimes_target "$t")")" ;;
            x86_64-unknown-linux-gnu) echo 'default-linker-linux-override = "off"' ;;
        esac
    done
} > "$src/bootstrap.toml"
log "bootstrap.toml:"
cat "$src/bootstrap.toml" >&2

# The compiler the build makes runs against the LLVM library; nothing from the
# machine's own libraries reaches it.
export LLVM_PROVIDES_RUSTC_WRAPPER=1
case "$platform" in
    macos-*) export DYLD_LIBRARY_PATH="$neollvm/$build" ;;
    *) export LD_LIBRARY_PATH="$neollvm/$build" ;;
esac
export PKG_CONFIG=/bin/false
if [ "$platform" = windows-x86_64 ]; then
    # Where llvm-mingw keeps the runtime DLLs its programs load (libunwind.dll),
    # which the bootstrap ships beside rustc.exe, finding them on PATH.
    export PATH="$mingw/x86_64-w64-mingw32/bin:$PATH"
fi
cd "$src"
rm -rf build/dist
python3 x.py dist --host "$host" --target "$(echo $targets | tr ' ' ',')" rustc cargo clippy rustfmt rust-std

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
dest="$out/rust/host/$host"
rm -rf "$dest"
for d in "$dist"/*/; do
    case "$(basename "$d")" in rust-std-*) continue ;; esac
    install_components "$d" "$dest"
done
test -f "$dest/bin/rustc" || test -f "$dest/bin/rustc.exe" || die "no rustc for $host"
# What the host's tools import from libneollvm, which the library a consumer
# ships for the host must export: from the libraries themselves.
case "$platform" in
    linux-*)
        nm -D --undefined-only "$dest"/lib/*.so | awk '{ print $2 }' ;;
    macos-*)
        nm -u "$dest"/lib/*.dylib | sed 's/^_//' ;;
    windows-*)
        "$mingw/bin/llvm-objdump" -p "$dest"/bin/*.dll \
            | awk '/DLL Name:/ { dll = $3 } dll == "libneollvm.dll" && NF >= 3 { print $NF }' ;;
esac | grep '^LLVM' | sort -u > "$dest/neollvm-imports.txt"
test -s "$dest/neollvm-imports.txt" || die "no imports from libneollvm recorded for $host"
log "rust/host/$host imports $(wc -l < "$dest/neollvm-imports.txt") functions from libneollvm"
if [ "$platform" = windows-x86_64 ]; then
    test -f "$dest/bin/libunwind.dll" || die "no libunwind.dll beside rustc.exe"
fi
log "rust/host/$host: $(du -sh "$dest" | cut -f1)"
for t in $targets; do
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
