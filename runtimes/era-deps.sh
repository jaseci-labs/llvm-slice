#!/bin/sh
# Install what glibc-crt.sh needs in the end-of-life distribution it runs in
# (centos:7, fedora:34 or fedora:35), from the archives those releases moved to.
#
#   runtimes/era-deps.sh
set -eu
. /etc/os-release
case "$ID:$VERSION_ID" in
    centos:7)
        # vault.centos.org keeps CentOS 7.9.2009; aarch64 is under altarch/.
        base=http://vault.centos.org/7.9.2009
        if [ "$(uname -m)" = aarch64 ]; then base=http://vault.centos.org/altarch/7.9.2009; fi
        for f in /etc/yum.repos.d/*.repo; do
            sed -i -e 's/^mirrorlist=/#mirrorlist=/' \
                -e "s|^#baseurl=http://mirror.centos.org/centos/[$]releasever|baseurl=$base|" \
                -e "s|^#baseurl=http://mirror.centos.org/altarch/[$]releasever|baseurl=$base|" "$f"
        done
        yum -q -y install gcc make gawk bison perl python3 tar xz patch file binutils
        ;;
    fedora:34 | fedora:35)
        for f in /etc/yum.repos.d/*.repo; do
            sed -i -e 's/^metalink=/#metalink=/' \
                -e 's|^#baseurl=http://download.example/pub/fedora/linux|baseurl=https://archives.fedoraproject.org/pub/archive/fedora/linux|' "$f"
        done
        dnf -q -y install gcc make gawk bison perl python3 tar xz patch file binutils diffutils
        ;;
    *) echo "era-deps.sh: no recipe for $ID $VERSION_ID" >&2; exit 1 ;;
esac
gcc --version | head -1
