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
    "${grub_cdboot:+$grub_cdboot}" \
    "${shim_pkg:+$shim_pkg}" \
    anaconda \
    anaconda-install-img-deps \
    anaconda-dracut \
    dracut-config-generic \
    dracut-network \
    net-tools \
    plymouth \
    default-fonts-core-sans \
    default-fonts-other-sans \
    google-noto-sans-cjk-fonts

# these are necessary build tools, if you have a separate build container
# in `--bootc-build-ref` then these can go there
dnf install -qy \
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

mkdir -p /boot/efi/EFI
for efidir in /usr/lib/efi/*/*/EFI; do
    [[ -d "${efidir}" ]] && cp -ra "${efidir}/." /boot/efi/EFI/
done

dnf5 clean all

mkdir -p /var/mnt

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

# some configuration for anaconda

cat >/usr/share/anaconda/interactive-defaults.ks <<EOT
bootc --source-imgref registry:${target_image} --target-imgref ${target_image}
EOT

# these things are normally performed by `lorax` to make `anaconda` work; this is the
# bare minimum to get things to work

echo "install:x:0:0:root:/root:/usr/libexec/anaconda/run-anaconda" >>/etc/passwd
echo "install::14438:0:99999:7:::" >>/etc/shadow
passwd -d root

mv /usr/share/anaconda/list-harddrives-stub /usr/bin/list-harddrives
mv /etc/yum.repos.d /etc/anaconda.repos.d
systemctl set-default anaconda.target
rm -v /usr/lib/systemd/system-generators/systemd-gpt-auto-generator

if [ -e /usr/lib/systemd/system/autovt@.service ]; then
    rm -f /usr/lib/systemd/system/autovt@.service
fi
ln -s /usr/lib/systemd/system/anaconda-shell@.service /usr/lib/systemd/system/autovt@.service

mkdir /usr/lib/systemd/logind.conf.d
cat >/usr/lib/systemd/logind.conf.d/anaconda-shell.conf <<EOT
[Login]
ReserveVT=2
EOT

mkdir "$(realpath /root)"
kernel=$(kernel-install list --json pretty | jq -r '.[] | select(.has_kernel == true) | .version')
DRACUT_NO_XATTR=1 dracut --force -v --zstd --reproducible --no-hostonly \
    --add "anaconda" \
    "/usr/lib/modules/${kernel}/initramfs.img" "${kernel}"

mkdir /etc/systemd/user/pipewire.service.d/
cat >/etc/systemd/user/pipewire.service.d/allowroot.conf <<EOT
[Unit]
ConditionUser=
EOT

mkdir /etc/systemd/user/pipewire.socket.d/
cat >/etc/systemd/user/pipewire.socket.d/allowroot.conf <<EOT
[Unit]
ConditionUser=
EOT

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
