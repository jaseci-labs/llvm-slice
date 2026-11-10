#!/bin/sh
# Node, built for one platform by its own build (configure --shared and make):
# as a shared library, which is how neojac holds Node, so that what the slice
# ships is compiled for one (position-independent code, and V8's thread-local
# storage in the model a library loaded while a program runs can use), and
# compiled as neojac compiles C++ so that it links into neojac's own build of
# that library: the LLVM release's Clang, with libc++ and libc++abi from the
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
#   <platform>  linux-x86_64, linux-aarch64 (natively, on Linux) or
#               macos-aarch64 (on an Apple silicon Mac)
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
        link_flags="-fuse-ld=lld"
        link_libs="-lpthread"
        dest_cpu="$arch"
        [ "$arch" = aarch64 ] && dest_cpu=arm64
        [ "$arch" = x86_64 ] && dest_cpu=x64
        ;;
    macos-aarch64)
        triple="arm64-apple-macos14.0"
        tdir="aarch64-macos"
        # The system root neojac compiles and links macOS programs against,
        # the runtimes slice's (libc/darwin: libSystem's and the frameworks'
        # stubs; libc/include/darwin: the SDK's headers), not the machine's
        # Xcode SDK, whose stubs a newer Xcode writes in a form the LLVM
        # release's linker may not read.
        darwin="$rt/libc/darwin"
        cflags="-isysroot $darwin -nostdinc -isystem $LLVM/lib/clang/22/include -isystem $rt/libc/include/darwin -iframework $darwin/System/Library/Frameworks"
        # libm, libdl, libpthread and libc are libSystem, as the SDK's stubs
        # of them are.
        syslibs="$WORK/darwin-libs"
        mkdir -p "$syslibs"
        for l in System m dl pthread c; do cp "$darwin/libSystem.tbd" "$syslibs/lib$l.tbd"; done
        # compiler-rt's builtins for the target, as neojac links them.
        link_flags="-fuse-ld=lld -nodefaultlibs -L$syslibs"
        link_libs="$rt/targets/$tdir/libclang_rt.builtins.a -lSystem"
        cxx_runtime="$rt/targets/$tdir/libc++.a $rt/targets/$tdir/libc++abi.a"
        dest_cpu=arm64
        ;;
    *) die "no Node slice for '$platform'" ;;
esac

# The compilers, as wrappers gyp's make calls with its own flags after these.
bin="$WORK/node-bin"
mkdir -p "$bin"
cat > "$bin/cc" << EOF
#!/bin/sh
# A link (no -c, -E, -S or -M among the arguments) takes the platform's
# link flags and libraries.
link=1
for a in "\$@"; do
    case "\$a" in -c | -E | -S | -M | -MM) link=0 ;; esac
done
if [ "\$link" = 1 ]; then
    exec "$LLVM/bin/clang" --target=$triple $cflags $link_flags "\$@" $link_libs
fi
exec "$LLVM/bin/clang" --target=$triple $cflags "\$@"
EOF
cat > "$bin/c++" << EOF
#!/bin/sh
# libc++'s headers, then its configuration for the target (__config_site), as
# neojac's C++ compiles; a link (no -c, -E, -S or -M among the arguments)
# takes the runtimes' libc++, never the system's, and the platform's link
# flags and libraries.
link=1
for a in "\$@"; do
    case "\$a" in -c | -E | -S | -M | -MM) link=0 ;; esac
done
if [ "\$link" = 1 ]; then
    exec "$LLVM/bin/clang++" --target=$triple -nostdinc++ -isystem "$rt/libcxx/include" -isystem "$rt/targets/$tdir/include" $cflags $link_flags -nostdlib++ "\$@" $cxx_runtime $link_libs
fi
exec "$LLVM/bin/clang++" --target=$triple -nostdinc++ -isystem "$rt/libcxx/include" -isystem "$rt/targets/$tdir/include" $cflags "\$@"
EOF
chmod +x "$bin/cc" "$bin/c++"
export CC="$bin/cc" CXX="$bin/c++" CC_host="$bin/cc" CXX_host="$bin/c++" LINK="$bin/c++"
export AR="$LLVM/bin/llvm-ar" RANLIB="$LLVM/bin/llvm-ranlib" STRIP="$LLVM/bin/llvm-strip"

src="$WORK/node"
unpack "node-v$NODE_VERSION.tar.xz" "$src"
cargo --version >&2 || die "no Rust toolchain: Node's Temporal needs cargo"
inc="$clibs/include"
lib="$clibs/lib"
# shellcheck disable=SC2086
(cd "$src" && python3 configure.py --use_clang --dest-cpu="$dest_cpu" --shared \
    --with-intl=full-icu --without-lief \
    --shared-openssl --shared-openssl-includes="$inc" --shared-openssl-libpath="$lib" \
    --shared-zlib --shared-zlib-includes="$inc" --shared-zlib-libpath="$lib" \
    --shared-zstd --shared-zstd-includes="$inc" --shared-zstd-libpath="$lib" \
    --shared-sqlite --shared-sqlite-includes="$inc" --shared-sqlite-libpath="$lib" \
    --shared-ffi --shared-ffi-includes="$inc" --shared-ffi-libpath="$lib")
grep -q '"v8_enable_temporal_support": 1' "$src/config.gypi" || die "configure left Temporal out"
make -s -C "$src" -j"$JOBS"
# The node program of a shared build loads Node's library, which is beside it.
LD_LIBRARY_PATH="$src/out/Release" DYLD_LIBRARY_PATH="$src/out/Release" "$src/out/Release/node" -e 'if (typeof Temporal !== "object" || process.versions.openssl === undefined) process.exit(1); console.log(process.version, process.versions.v8)'
python3 -I "$NODE_DIR/pack.py" "$src" "$platform" "$out"
log "$platform: $(du -sh "$out/node/$platform" | cut -f1)"
