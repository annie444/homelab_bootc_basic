#!/bin/bash
set -Eeuxo pipefail

{ export PS4='+( ${BASH_SOURCE}:${LINENO} ): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'; } 2>/dev/null

if [[ -z "${FEDORA_VERSION:-}" ]]; then
    echo "FEDORA_VERSION environment variable is not set"
    exit 1
fi

arch="$(arch)"

dnf5 config-manager addrepo \
    --from-repofile="https://developer.download.nvidia.com/compute/cuda/repos/fedora${FEDORA_VERSION}/${arch}/cuda-fedora${FEDORA_VERSION}.repo"

dnf5 install -y nvidia-driver-cuda kmod-nvidia-open-dkms

dnf5 config-manager addrepo \
    --from-repofile=https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo

dnf5 install -y nvidia-container-toolkit nvidia-container-toolkit-base \
    libnvidia-container-tools libnvidia-container1

if [[ -d /usr/src/ ]]; then
    if ! [[ -d /usr/lib/tmpfiles.d/ ]]; then
        mkdir -p /usr/lib/tmpfiles.d/
    fi

    nvidia_dkms_file="/usr/lib/tmpfiles.d/90-dkms-nvidia.conf"

    mapfile -t dkms_nvidia_modules < <(/bin/ls -1 /usr/src/ | grep -E '^nvidia-[0-9]+.[0-9]+.[0-9]+$' | sed -E 's/nvidia-([0-9]+.[0-9]+.[0-9]+)/\1/g')

    {
        echo "d /var/lib/dkms/nvidia 0755 root root - -"
        for mod_version in "${dkms_nvidia_modules[@]}"; do
            echo "d /var/lib/dkms/nvidia/${mod_version} 0755 root root - -"
            echo "d /var/lib/dkms/nvidia/${mod_version}/build 0755 root root - -"
            echo "L /var/lib/dkms/nvidia/${mod_version}/source - - - - /usr/src/nvidia-${mod_version}"
        done
    } >"${nvidia_dkms_file}"

    cat "${nvidia_dkms_file}"
fi
# vim: set ft=bash et tw=4 sw=4 sts=4:
