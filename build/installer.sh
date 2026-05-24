#!/bin/bash
set -Eeuxo pipefail

# Packages that turn a fedora-bootc base into an Anaconda *installer environment*
# container, as required by image-builder's `bootc-installer` image type.
# The OS that actually gets installed is supplied separately via
# --bootc-installer-payload-ref, so this image stays minimal.

arch="$(uname -m)"
grub_cdboot=""

case "$arch" in
x86_64) grub_cdboot="grub2-efi-x64-cdboot" ;;
aarch64) grub_cdboot="grub2-efi-aa64-cdboot" ;;
esac

dnf5 -y distro-sync --allowerasing
dnf5 -y upgrade --refresh

dnf5 install -y \
    anaconda \
    anaconda-install-env-deps \
    anaconda-dracut \
    dracut-config-generic \
    dracut-network \
    net-tools \
    squashfs-tools \
    "${grub_cdboot:+$grub_cdboot}" \
    python3-mako \
    lorax-templates-generic \
    biosdevname \
    prefixdevname
# vim: set ft=bash et tw=4 sw=4 sts=4:
