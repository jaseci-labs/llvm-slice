#!/bin/sh
# Node, built for one platform by its own build (configure and make), compiled
# as neojac compiles C++ so that what the slice ships links into a neojac
# program: the LLVM release's Clang, with libc++ and libc++abi from the
# runtimes slice (their headers and their static libraries, which neojac's
# C++ links), and on Linux the glibc headers neojac compiles against, for
# glibc 2.28. Node links the clibs slice's OpenSSL, zlib, Zstandard, SQLite
# and libffi (configure's --shared-* options), as neojac's Node does; its
# Temporal (V8's Temporal API, through the temporal_rs crate) is built by the
# pinned Rust toolchain. Then node/pack.py takes the slice's tree from the
# build.
#
#   node/build.sh <platform> <clibs> <runtimes> <out>
#
#   <platform>  linux-x86_64, linux-aarch64 (natively, on Linux), macos-aarch64
#               or macos-x86_64 (on an Apple silicon Mac: every tool the build
#               compiles, compiled for x86-64 as its host compiler is, runs
#               under Rosetta, so configure sees no cross build and keeps the
#               startup snapshot and code cache, which a cross build leaves
#               out)
#   <clibs>     the clibs slice's tree for <platform> (clibs/<platform>/ of
#               clibs-v<set>-<revision>)
#   <runtimes>  the runtimes slice's tree (runtimes-v<llvm>-<revision>)
#   <out>       where node/pack.py writes node/<platform>/ and node/npm/
#
# The build runs Node's own tests' smoke check (node -e) before packing.
NODE_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIMES_DIR="$NODE_DIR/../runtimes"
SOURCES="$NODE_DIR/sources.txt $RUNTIMES_DIR/sources.txt"
. "$RUNTIMES_DIR/lib.sh"
platform="$1"
clibs="$(cd "$2" && pwd)"
rt="$(cd "$3" && pwd)"
out="$(mkdir -p "$4" && cd "$4" && pwd)"
NODE_VERSION=26.13.0

llvm_toolchain
case "$platform" in
    linux-x86_64 | linux-aarch64)
        arch="${platform#linux-}"
        [ "$(uname -m)" = "$arch" ] || die "$platform builds natively; this is $(uname -m)"
        triple="$arch-linux-gnu"
        tdir="$arch-linux-gnu"
        kernel="x86_64-linux-kernel"
        libc_arch="x86-linux-gnu"
        if [ "$arch" = aarch64 ]; then
            kernel="aarch64-linux-kernel"
            libc_arch="aarch64-linux-gnu"
        fi
        # The C library's headers neojac compiles with (the runtimes slice's,
        # for glibc 2.28), not the runner's newer glibc's, whose headers
        # redirect calls to symbols glibc 2.28 lacks (__isoc23_strtol).
        cflags="-nostdinc -isystem $LLVM/lib/clang/22/include -isystem $rt/libc/include/$libc_arch -isystem $rt/libc/include/generic-glibc -isystem $rt/libc/include/$kernel -D__GLIBC_MINOR__=28"
        cxx_runtime="$rt/targets/$tdir/libc++.a $rt/targets/$tdir/libc++abi.a $rt/targets/$tdir/libunwind.a"
        dest_cpu="$arch"
        [ "$arch" = aarch64 ] && dest_cpu=arm64
        [ "$arch" = x86_64 ] && dest_cpu=x64
        ;;
    macos-aarch64 | macos-x86_64)
        arch="${platform#macos-}"
        march="$arch"
        [ "$arch" = aarch64 ] && march=arm64
        sdk="$(xcrun --sdk macosx --show-sdk-path)"
        triple="$march-apple-macos14.0"
        tdir="$arch-macos"
        cflags="-isysroot $sdk"
        cxx_runtime="$rt/targets/$tdir/libc++.a $rt/targets/$tdir/libc++abi.a"
        dest_cpu=arm64
        [ "$arch" = x86_64 ] && dest_cpu=x64
        ;;
    *) die "no Node slice for '$platform'" ;;
esac

# The compilers, as wrappers gyp's make calls with its own flags after these.
bin="$WORK/node-bin"
mkdir -p "$bin"
cat > "$bin/cc" << EOF
#!/bin/sh
exec "$LLVM/bin/clang" --target=$triple $cflags "\$@"
EOF
cat > "$bin/c++" << EOF
#!/bin/sh
# libc++'s headers, then its configuration for the target (__config_site), as
# neojac's C++ compiles; a link (no -c, -E, -S or -M among the arguments)
# takes the runtimes' libc++, never the system's.
link=1
for a in "\$@"; do
    case "\$a" in -c | -E | -S | -M | -MM) link=0 ;; esac
done
if [ "\$link" = 1 ]; then
    exec "$LLVM/bin/clang++" --target=$triple -nostdinc++ -isystem "$rt/libcxx/include" -isystem "$rt/targets/$tdir/include" $cflags -fuse-ld=lld -nostdlib++ "\$@" $cxx_runtime -lpthread
fi
exec "$LLVM/bin/clang++" --target=$triple -nostdinc++ -isystem "$rt/libcxx/include" -isystem "$rt/targets/$tdir/include" $cflags "\$@"
EOF
chmod +x "$bin/cc" "$bin/c++"
export CC="$bin/cc" CXX="$bin/c++" CC_host="$bin/cc" CXX_host="$bin/c++" LINK="$bin/c++"
export AR="$LLVM/bin/llvm-ar" RANLIB="$LLVM/bin/llvm-ranlib"

src="$WORK/node"
unpack "node-v$NODE_VERSION.tar.xz" "$src"
cargo --version >&2 || die "no Rust toolchain: Node's Temporal needs cargo"
inc="$clibs/include"
lib="$clibs/lib"
# shellcheck disable=SC2086
(cd "$src" && python3 configure.py --use_clang --dest-cpu="$dest_cpu" \
    --with-intl=full-icu --without-lief \
    --shared-openssl --shared-openssl-includes="$inc" --shared-openssl-libpath="$lib" \
    --shared-zlib --shared-zlib-includes="$inc" --shared-zlib-libpath="$lib" \
    --shared-zstd --shared-zstd-includes="$inc" --shared-zstd-libpath="$lib" \
    --shared-sqlite --shared-sqlite-includes="$inc" --shared-sqlite-libpath="$lib" \
    --shared-ffi --shared-ffi-includes="$inc" --shared-ffi-libpath="$lib")
grep -q '"v8_enable_temporal_support": 1' "$src/config.gypi" || die "configure left Temporal out"
make -s -C "$src" -j"$JOBS"
"$src/out/Release/node" -e 'if (typeof Temporal !== "object" || process.versions.openssl === undefined) process.exit(1); console.log(process.version, process.versions.v8)'
python3 -I "$NODE_DIR/pack.py" "$src" "$platform" "$out"
log "$platform: $(du -sh "$out/node/$platform" | cut -f1)"
