#!/bin/bash
set -Eeuxo pipefail

{ export PS4='+( ${BASH_SOURCE}:${LINENO} ): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'; } 2>/dev/null

arch="$(uname -m)"
shim_pkg=""

case "$arch" in
x86_64) shim_pkg="shim-x64" ;;
aarch64) shim_pkg="shim-aa64" ;;
esac

dnf5 -y distro-sync --allowerasing
dnf5 -y upgrade --refresh

mapfile -t packages < <(/bin/cat /src/build/*-pkgs.txt)

dnf5 install -y \
    "${shim_pkg:+$shim_pkg}" \
    "${packages[@]}"
# vim: set ft=bash et tw=4 sw=4 sts=4:
