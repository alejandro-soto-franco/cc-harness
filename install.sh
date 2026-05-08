#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# cc-harness installer — fetches the latest GitHub release tarball,
# verifies its sha256, and installs into a chosen prefix.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/alejandro-soto-franco/cc-harness/main/install.sh | bash
#   curl ... | bash -s -- --prefix ~/.local
#   curl ... | bash -s -- --user
#   CC_HARNESS_VERSION=v0.1.0 curl ... | bash
#   curl ... | bash -s -- --uninstall
set -euo pipefail

REPO="${CC_HARNESS_REPO:-alejandro-soto-franco/cc-harness}"
NAME="cc-harness"
VERSION="${CC_HARNESS_VERSION:-}"
PREFIX=""
USER_INSTALL=0
UNINSTALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)    PREFIX="$2"; shift 2 ;;
        --user)      USER_INSTALL=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        --help|-h)
            sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) printf "install.sh: unknown flag: %s\n" "$1" >&2; exit 2 ;;
    esac
done

# Pick a prefix the user can actually write to.
if [[ -z "$PREFIX" ]]; then
    if (( USER_INSTALL )); then
        PREFIX="$HOME/.local"
    elif [[ -w /usr/local ]]; then
        PREFIX="/usr/local"
    else
        PREFIX="$HOME/.local"
        echo "install.sh: /usr/local not writable; falling back to $PREFIX" >&2
    fi
fi

if (( UNINSTALL )); then
    if [[ -x "$PREFIX/bin/$NAME" ]]; then
        exec "$PREFIX/bin/$NAME" uninstall --prefix "$PREFIX"
    fi
    rm -f "$PREFIX/bin/$NAME" \
          "$PREFIX/share/man/man1/$NAME.1" \
          "$PREFIX/share/bash-completion/completions/$NAME" \
          "$PREFIX/share/zsh/site-functions/_$NAME" \
          "$PREFIX/share/fish/vendor_completions.d/$NAME.fish"
    echo "install.sh: removed $NAME from $PREFIX"
    exit 0
fi

# Resolve the latest version if not pinned.
if [[ -z "$VERSION" ]]; then
    VERSION="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | awk -F'"' '/"tag_name":/ {print $4; exit}')"
    [[ -n "$VERSION" ]] || { echo "install.sh: could not resolve latest version" >&2; exit 1; }
fi

VER_NO_V="${VERSION#v}"
TARBALL="$NAME-$VER_NO_V.tar.gz"
URL="https://github.com/$REPO/releases/download/$VERSION/$TARBALL"
SUMS_URL="$URL.sha256"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "install.sh: downloading $TARBALL ..."
curl -fsSL --retry 3 -o "$TMP/$TARBALL"      "$URL"
curl -fsSL --retry 3 -o "$TMP/$TARBALL.sha256" "$SUMS_URL"

echo "install.sh: verifying sha256 ..."
( cd "$TMP" && sha256sum -c "$TARBALL.sha256" )

echo "install.sh: extracting ..."
tar -xzf "$TMP/$TARBALL" -C "$TMP"

echo "install.sh: installing into $PREFIX ..."
make -C "$TMP/$NAME-$VER_NO_V" install PREFIX="$PREFIX" \
    BASH_COMPLETION_DIR="$PREFIX/share/bash-completion/completions" \
    ZSH_COMPLETION_DIR="$PREFIX/share/zsh/site-functions" \
    FISH_COMPLETION_DIR="$PREFIX/share/fish/vendor_completions.d"

echo
echo "  installed: $PREFIX/bin/$NAME"
echo "  man page:  $PREFIX/share/man/man1/$NAME.1"
echo "  run:       $NAME doctor"
