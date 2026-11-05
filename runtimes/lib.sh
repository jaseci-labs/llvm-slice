# Shared by the runtimes build scripts (sourced, not run).
#
#   SRC_CACHE  where pinned downloads are kept (default: $WORK/src)
#   WORK       scratch space (default: ./work)
#   LLVM       an extracted LLVM release (bin/clang, bin/lld, bin/llvm-ar, ...);
#              llvm_toolchain sets it for the host when it is unset.

set -eu

RUNTIMES_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-$PWD/work}"
SRC_CACHE="${SRC_CACHE:-$WORK/src}"
LLVM_VERSION=22.1.8
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2> /dev/null || echo 4)}"
mkdir -p "$WORK" "$SRC_CACHE"

log() { printf '%s: %s\n' "$(basename "$0")" "$*" >&2; }
die() { log "error: $*"; exit 1; }

# From standard input, so no path is printed (sha256sum escapes a path with a
# backslash, as Git Bash's on Windows are, with a leading backslash).
sha256_of() {
    if command -v sha256sum > /dev/null; then sha256sum < "$1" | cut -d' ' -f1
    else shasum -a 256 < "$1" | cut -d' ' -f1; fi
}

# fetch <file>: the path of a pinned download (sources.txt), downloaded once and
# checked against its pinned sha256 every time.
fetch() {
    line="$(grep -E "^$1 " "$RUNTIMES_DIR/sources.txt")" || die "$1 is not pinned in sources.txt"
    want="$(echo "$line" | cut -d' ' -f2)"
    url="$(echo "$line" | cut -d' ' -f3)"
    path="$SRC_CACHE/$1"
    if [ ! -f "$path" ]; then
        log "downloading $url"
        curl -fsSL --retry 5 -o "$path.part" "$url"
        mv "$path.part" "$path"
    fi
    got="$(sha256_of "$path")"
    [ "$got" = "$want" ] || die "$1: sha256 $got, pinned $want"
    echo "$path"
}

# unpack <file> <dir> [<pattern>...]: a pinned tarball's contents (its top
# directory stripped), or only the members matching the patterns, in a fresh
# <dir>.
unpack() {
    archive="$(fetch "$1")"
    dir="$2"
    shift 2
    rm -rf "$dir"
    mkdir -p "$dir"
    if [ $# -gt 0 ] && tar --version 2> /dev/null | grep -q GNU; then
        tar -xf "$archive" -C "$dir" --strip-components=1 --wildcards "$@"
    else
        tar -xf "$archive" -C "$dir" --strip-components=1 "$@"
    fi
}

# The host's LLVM release, extracted once under $WORK/llvm.
llvm_toolchain() {
    if [ -n "${LLVM:-}" ]; then return; fi
    case "$(uname -s)-$(uname -m)" in
        Linux-x86_64) name="LLVM-$LLVM_VERSION-Linux-X64" ;;
        Linux-aarch64) name="LLVM-$LLVM_VERSION-Linux-ARM64" ;;
        Darwin-arm64) name="LLVM-$LLVM_VERSION-macOS-ARM64" ;;
        *) die "no LLVM release for $(uname -s)-$(uname -m)" ;;
    esac
    LLVM="$WORK/llvm"
    if [ ! -x "$LLVM/bin/clang" ]; then
        # The compiler, linker and binary tools, and Clang's resource directory.
        unpack "$name.tar.xz" "$LLVM" "*/bin/*" "*/lib/clang/*"
    fi
    "$LLVM/bin/clang" --version | head -1 >&2
}

# The LLVM sources, extracted once under $WORK/llvm-project.
llvm_sources() {
    LLVM_SRC="$WORK/llvm-project"
    if [ ! -f "$LLVM_SRC/runtimes/CMakeLists.txt" ]; then
        unpack "llvm-project-$LLVM_VERSION.src.tar.xz" "$LLVM_SRC"
    fi
}
