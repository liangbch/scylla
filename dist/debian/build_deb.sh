#!/bin/bash -e

PRODUCT=$(cat SCYLLA-PRODUCT-FILE)

. /etc/os-release
print_usage() {
    echo "build_deb.sh -target <codename> --dist --rebuild-dep --reloc-pkg build/release/scylla-package.tar.gz"
    echo "  --dist  create a public distribution package"
    echo "  --reloc-pkg specify relocatable package path"
    exit 1
}

DIST="false"
RELOC_PKG=
while [ $# -gt 0 ]; do
    case "$1" in
        "--dist")
            DIST="true"
            shift 1
            ;;
        "--reloc-pkg")
            RELOC_PKG=$2
            shift 2
            ;;
        *)
            print_usage
            ;;
    esac
done

is_redhat_variant() {
    [ -f /etc/redhat-release ]
}
is_debian_variant() {
    [ -f /etc/debian_version ]
}
pkg_install() {
    if is_redhat_variant; then
        sudo yum install -y $1
    elif is_debian_variant; then
        sudo apt-get install -y $1
    else
        echo "Requires to install following command: $1"
        exit 1
    fi
}

if [ ! -e SCYLLA-RELOCATABLE-FILE ]; then
    echo "do not directly execute build_deb.sh, use reloc/build_deb.sh instead."
    exit 1
fi

if [ "$(arch)" != "x86_64" ]; then
    echo "Unsupported architecture: $(arch)"
    exit 1
fi

if [ -z "$RELOC_PKG" ]; then
    print_usage
    exit 1
fi
if [ ! -f "$RELOC_PKG" ]; then
    echo "$RELOC_PKG is not found."
    exit 1
fi

if is_debian_variant; then
    sudo apt-get -y update
fi
# this hack is needed since some environment installs 'git-core' package, it's
# subset of the git command and doesn't works for our git-archive-all script.
if is_redhat_variant && [ ! -f /usr/libexec/git-core/git-submodule ]; then
    sudo yum install -y git
fi
if [ ! -f /usr/bin/git ]; then
    pkg_install git
fi
if [ ! -f /usr/bin/python ]; then
    pkg_install python
fi
if [ ! -f /usr/bin/debuild ]; then
    pkg_install devscripts
fi
if [ ! -f /usr/bin/dh_testdir ]; then
    pkg_install debhelper
fi
if [ ! -f /usr/bin/fakeroot ]; then
    pkg_install fakeroot
fi
if [ ! -f /usr/bin/file ]; then
    pkg_install file
fi
if is_debian_variant && [ ! -f /usr/share/doc/python-pkg-resources/copyright ]; then
    sudo apt-get install -y python-pkg-resources
fi

if [ "$ID" = "ubuntu" ] && [ ! -f /usr/share/keyrings/debian-archive-keyring.gpg ]; then
    sudo apt-get install -y debian-archive-keyring
fi
if [ "$ID" = "debian" ] && [ ! -f /usr/share/keyrings/ubuntu-archive-keyring.gpg ]; then
    sudo apt-get install -y ubuntu-archive-keyring
fi

RELOC_PKG_FULLPATH=$(readlink -f $RELOC_PKG)
RELOC_PKG_BASENAME=$(basename $RELOC_PKG)
SCYLLA_VERSION=$(cat SCYLLA-VERSION-FILE | sed 's/\.rc/~rc/')
SCYLLA_RELEASE=$(cat SCYLLA-RELEASE-FILE)

ln -fv $RELOC_PKG_FULLPATH ../$PRODUCT-server_$SCYLLA_VERSION-$SCYLLA_RELEASE.orig.tar.gz

if $DIST; then
    export DEB_BUILD_OPTIONS="housekeeping"
fi
debuild -rfakeroot -us -uc
