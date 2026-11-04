#!/usr/bin/env bash
# Resolve the binary's linked libraries plus the shortcut's gapplication command.
set -euo pipefail
BINARY="$1"
command -v dpkg-shlibdeps >/dev/null || {
    echo 'error: dpkg-shlibdeps is required to package Vervellum' >&2
    exit 1
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$workdir/debian"
printf 'Source: vervellum\n\nPackage: vervellum\nArchitecture: any\nDescription: Research panel\n' > "$workdir/debian/control"
# Missing metadata is a packaging failure, not permission to guess dependencies.
(cd "$workdir" && dpkg-shlibdeps -O "$BINARY") > "$workdir/deps"
DEPENDS="$(sed -n 's/^shlibs:Depends=//p' "$workdir/deps" | head -1)"
[ -n "$DEPENDS" ] || {
    echo 'error: dpkg-shlibdeps returned no dependencies' >&2
    exit 1
}
# gapplication is executed by the shortcut, so linked-library discovery cannot see it.
printf '%s, libglib2.0-bin\n' "$DEPENDS"
