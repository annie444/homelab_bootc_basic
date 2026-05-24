#!/bin/bash
set -Eeuxo pipefail

# Packages that turn a fedora-bootc base into an Anaconda *installer environment*
# container, as required by image-builder's `bootc-installer` image type.
# The OS that actually gets installed is supplied separately via
# --bootc-installer-payload-ref, so this image stays minimal.

arch="$(uname -m)"
grub_cdboot=""
shim_pkg=""

# The grub2.iso osbuild stage builds the EFI boot tree by copying the vendor
# shim (e.g. /boot/efi/EFI/fedora/shimx64.efi) and the CD-boot grub from this
# installer environment, so both must be installed here.
case "$arch" in
x86_64)
    grub_cdboot="grub2-efi-x64-cdboot"
    shim_pkg="shim-x64"
    ;;
aarch64)
    grub_cdboot="grub2-efi-aa64-cdboot"
    shim_pkg="shim-aa64"
    ;;
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
    "${shim_pkg:+$shim_pkg}" \
    python3-mako \
    lorax-templates-generic \
    biosdevname \
    prefixdevname
# vim: set ft=bash et tw=4 sw=4 sts=4:
