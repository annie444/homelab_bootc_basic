#!/bin/bash
set -Eeuxo pipefail

if [[ -z "${FEDORA_VERSION:-}" ]]; then
    echo "FEDORA_VERSION environment variable is not set"
    exit 1
fi

dnf5 install -y dnf5-plugins
dnf5 config-manager setopt fedora-cisco-openh264.enabled=1

dnf5 install --nogpgcheck -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"
# vim: set ft=bash et tw=4 sw=4 sts=4:
