#!/bin/bash
set -Eeuxo pipefail

{ export PS4='+( ${BASH_SOURCE}:${LINENO} ): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'; } 2>/dev/null

if ! [ $# -eq 1 ]; then
    echo "Usage: $0 <target-image-ref>" >&2
    exit 1
fi
target_image="$1"

if [ -z "${target_image:-}" ]; then
    echo "Usage: $0 <target-image-ref>" >&2
    exit 1
fi

# Packages that turn a fedora-bootc base into an Anaconda *installer environment*
# container, as required by image-builder's `bootc-installer` image type.
# The OS that actually gets installed is supplied separately via
# --bootc-installer-payload-ref, so this image stays minimal.

arch="$(uname -m)"
shim_pkg=""
grub_cdboot=""

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

dnf5 install -y \
    "${shim_pkg:+$shim_pkg}" \
    net-tools \
    plymouth \
    default-fonts-core-sans \
    default-fonts-other-sans \
    google-noto-sans-cjk-fonts \
    xorrisofs \
    squashfs-tools

# Fedora bootc stores the EFI binaries under /usr/lib/efi/<pkg>/<ver>/EFI/ and
# leaves /boot/efi empty (bootupd populates it at install time). The grub2.iso
# osbuild stage, however, reads shim/grub from /boot/efi/EFI/<vendor>/, so
# stage them into place here or ISO EFI-tree assembly fails with a missing
# shimx64.efi. Workaround per https://supakeen.com/weblog/installer-types-for-bootc/.
if [[ -n "${shim_pkg}" ]]; then
    dnf5 reinstall -y "${shim_pkg}"
fi

# Create the directory that /root is symlinked to
mkdir -p "$(realpath /root)"

podman pull "$target_image"

mkdir -p /etc/anaconda/conf.d/
cat >/etc/anaconda/conf.d/anaconda.conf <<EOF
[Payload]
flatpak_remote = flathub https://dl.flathub.org/repo/
EOF

mkdir -p /etc/anaconda/profile.d/
cat >/etc/anaconda/profile.d/homelabos.conf <<EOF
[Profile]
profile_id = homelabos

[Profile Detection]
os_id = fedora
variant_id = homelabos

[Network]
default_on_boot = FIRST_WIRED_WITH_LINK

[Bootloader]
efi_dir = fedora
menu_auto_hide = True

[Storage]
file_system_type = xfs
default_scheme = plain
default_partitioning =
    /     (min 1 GiB, max 70 GiB)
    /home (min 500 MiB, free 50 GiB)
    /var

[Localization]
use_geolocation = False

[User Interface]
hidden_webui_pages =
    network
custom_stylesheet = /usr/share/anaconda/pixmaps/server/fedora-server.css
EOF

mv /usr/lib/os-release /usr/lib/os-release.bak
CURRENT_RELEASE="$(cat /usr/lib/os-release.bak)"
cat >/etc/os-release <<EOT
${CURRENT_RELEASE}
VARIANT="HomelabOS"
VARIANT_ID=homelabos
EOT

# Swap kernel with vanilla and rebuild initramfs.
#
# This is done because we want the initramfs to use a signed
# kernel for secureboot.
kernel_pkgs=(
    kernel
    kernel-core
    kernel-devel
    kernel-devel-matched
    kernel-modules
    kernel-modules-core
    kernel-modules-extra
)
dnf5 -y versionlock delete "${kernel_pkgs[@]}"
dnf5 --setopt=protect_running_kernel=False -y remove "${kernel_pkgs[@]}"
(cd /usr/lib/modules && rm -rf -- ./*)
dnf5 -y --repo fedora,updates --setopt=tsflags=noscripts install kernel kernel-core
kernel=$(find /usr/lib/modules -maxdepth 1 -type d -printf '%P\n' | grep .)
depmod "$kernel"

dnf5 clean all -yq

# Install dracut-live and regenerate the initramfs
dnf5 install -y dracut-live
kernel=$(kernel-install list --json pretty | jq -r '.[] | select(.has_kernel == true) | .version')
DRACUT_NO_XATTR=1 dracut -v --force --zstd --reproducible --no-hostonly \
    --add "dmsquash-live dmsquash-live-autooverlay" \
    "/usr/lib/modules/${kernel}/initramfs.img" "${kernel}"

mkdir -p /boot/efi/EFI
for efidir in /usr/lib/efi/*/*/EFI; do
    [[ -d "${efidir}" ]] && cp -ra "${efidir}/." /boot/efi/EFI/
done

mkdir -p /var/mnt

# Remove all versionlocks, in order to avoid dependency issues
dnf5 -qy versionlock clear

# Install Anaconda
dnf5 install -qy --enable-repo=fedora-cisco-openh264 --allowerasing anaconda-live libblockdev-{btrfs,crypto,dm,fs,lvm,mdraid,nvme,part,smart,smartmontools}

mkdir -p /var/lib/rpm-state # Needed for Anaconda Web UI

# Utilities for displaying a dialog prompting users to review secure boot documentation
dnf5 install -qy --setopt=install_weak_deps=0 qrencode yad

# Default Kickstart
cat >>/usr/share/anaconda/interactive-defaults.ks <<EOF

# Create log directory
%pre
mkdir -p /tmp/anacoda_custom_logs
%end

# Check if there is a bitlocker partition and ask the user to disable it
%pre --erroronfail --log=/tmp/anacoda_custom_logs/detect_bitlocker.log
DOCS_QR=/tmp/detect_bitlocker_qr.png
IS_BITLOCKER=\$(lsblk -o FSTYPE --json | jq '.blockdevices | map(select(.fstype == "BitLocker")) | . != []')
{ WARNING_MSG="\$(</dev/stdin)"; } << 'WARNINGEOF'
<span size="x-large">Windows Bitlocker partition detected</span>

It might interrupt the installation process.
In such case, please, do <b>one</b> of the following:
    a) Disconnect its storage drive.
    b) Disable Bitlocker in Windows.
    c) Delete it in GNOME Disks.

Do you wish to continue?
WARNINGEOF

if [[ \$IS_BITLOCKER =~ true ]]; then
    qrencode -o \$DOCS_QR "https://www.wikihow.com/Turn-Off-BitLocker"
    _EXITLOCK=1
    _RETCODE=0
    while [[ \$_EXITLOCK -ne 0 ]]; do
        run0 --user=liveuser yad \
            --on-top \
            --timeout=10 \
            --image=\$DOCS_QR \
            --text="\$WARNING_MSG" \
            --button="Yes, I'm aware, continue":0 --button="Cancel installation":10
        _RETCODE=\$?
        case \$_RETCODE in
            0) _EXITLOCK=0; ;;
            10) _EXITLOCK=0; pkill liveinst; pkill firefox; exit 0 ;;
        esac
    done
fi
%end

# Remove the efi dir, must match efi_dir from the profile config
%pre-install --erroronfail
rm -rf /mnt/sysroot/boot/efi/EFI/fedora
%end

# Relabel the boot partition for the
%pre-install --erroronfail --log=/tmp/anacoda_custom_logs/repartitioning.log
set -x
xboot_dev=\$(findmnt -o SOURCE --nofsroot --noheadings -f --target /mnt/sysroot/boot)
if [[ -z \$xboot_dev ]]; then
  echo "ERROR: xboot_dev not found"
  exit 1
fi
e2label "\$xboot_dev" "xboot"
%end

# Open a dialog with the installation logs
%onerror
run0 --user=liveuser yad \
    --timeout=0 \
    --text-info \
    --no-buttons \
    --width=600 \
    --height=400 \
    --text="An error occurred during installation. Please report this issue to the developers." \
    < /tmp/anaconda.log
%end

ostreecontainer --url=${target_image} --transport=containers-storage --no-signature-verification
%include /usr/share/anaconda/post-scripts/install-configure-upgrade.ks

EOF

# Signed Images
cat <<EOF >>/usr/share/anaconda/post-scripts/install-configure-upgrade.ks
%post --erroronfail --log=/tmp/anacoda_custom_logs/bootc-switch.log
bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry ${target_image}
%end
EOF

# Don't check for verified image
rm -vf /etc/profile.d/verify_motd.sh

# Install Gparted
dnf5 -yq install gparted

# image-builder needs gcdx64.efi
dnf5 install -y "$grub_cdboot"

# image-builder expects the EFI directory to be in /boot/efi
mkdir -p /boot/efi
cp -av /usr/lib/efi/*/*/EFI /boot/efi/

# Set the timezone to UTC
rm -f /etc/localtime
systemd-firstboot --timezone UTC

# some configuration for our ISO
mkdir -p /usr/lib/image-builder/bootc

cat >/usr/lib/image-builder/bootc/iso.yaml <<EOT
label: "Fedora-bootc-Installer"
grub2:
  default: 0
  timeout: 10
  entries:
    - name: "Install Fedora (bootc)"
      linux: "/images/pxeboot/vmlinuz quiet rhgb root=live:CDLABEL=Fedora-bootc-Installer enforcing=0 rd.live.image"
      initrd: "/images/pxeboot/initrd.img"
    - name: "My Custom Image Live (Basic Graphics)"
      linux: "/images/pxeboot/vmlinuz quiet rhgb root=live:CDLABEL=Fedora-bootc-Installer enforcing=0 rd.live.image nomodeset"
      initrd: "/images/pxeboot/initrd.img"
EOT

mkdir -p /usr/lib/bootc-image-builder
cp /usr/lib/image-builder/bootc/iso.yaml /usr/lib/bootc-image-builder/iso.yaml

# / in a booted live ISO is an overlayfs with upperdir pointed somewhere under /run
# This means that /var/tmp is also technically under /run.
# /run is of course a tmpfs, but set with quite a small size.
# ostree needs quite a lot of space on /var/tmp for temporary files so /run is not enough.
# Mount a larger tmpfs to /var/tmp at boot time to avoid this issue.
rm -rf /var/tmp
mkdir /var/tmp
cat >/etc/systemd/system/var-tmp.mount <<'EOF'
[Unit]
Description=Larger tmpfs for /var/tmp on live system

[Mount]
What=tmpfs
Where=/var/tmp
Type=tmpfs
Options=size=50%%,nr_inodes=1m,x-systemd.graceful-option=usrquota

[Install]
WantedBy=local-fs.target
EOF
systemctl enable var-tmp.mount
# vim: set ft=bash et tw=4 sw=4 sts=4:
