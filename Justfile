export image_registry := env("IMAGE_REGISTRY", "ghcr.io")
export image_ns := env("IMAGE_NS", "annie444")
export default_tag := env("DEFAULT_TAG", "latest")
export ib_image := env("IB_IMAGE", "ghcr.io/osbuild/image-builder-cli:latest")
export podman_connection := env("PODMAN_CONNECTION", "")
export fedora_version := env("FEDORA_VERSION", "43")
export output_dir := justfile_directory() + "/output"
export tools_image := env("TOOLS_IMAGE", "localhost/homelab-tools:latest")
export target_arch_raw := env("TARGET_ARCH", arch())
git_tag_version := `git tag -l | sed -E 's/^[^0-9]*//g' | sort --version-sort | tail -n 1`
export container_version := if git_tag_version != "" { git_tag_version } else { "0.1.0-0" }
export container_authors := "Annie Ehler <annie.ehler.4@gmail.com>"
export container_source := "https://github.com/annie444/homelab_bootc"
export container_revision := `git rev-parse --short HEAD`
export container_created := `date --rfc-3339="seconds"`
open_cmd := if os() == "windows" { "start" } else if os() == "darwin" { "open" } else { "xdg-open" }
export target_arch := if target_arch_raw == "amd64" { "amd64" } else if target_arch_raw == "arm64" { "aarch64" } else if target_arch_raw == "x86_64" { "amd64" } else { target_arch_raw }

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt -f Justfile || { exit 1; }

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/env bash
    set -eoux pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env
    rm -f output/

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
[private]
sudoif command *args:
    #!/usr/bin/env bash
    function sudoif(){
        if [[ "${EUID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            sudo "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif {{ command }} {{ args }}

_podman_cmd *args:
    #!/usr/bin/env bash
    set -eoux pipefail
    declare -a podman_args=()
    if [[ "$(uname)" == "Darwin" ]]; then
        if [[ -z "${podman_connection}" ]]; then
            true
        elif [[ "${podman_connection}" == "root" ]]; then
            podman_args+=("--connection=$(podman system connection list --format '{{{{.Name}} {{{{.URI}}' | grep "127.0.0.1" | grep root | awk '{ print $1 }')")
        else
            podman_args+=("--connection=${podman_connection}")
        fi
    fi
    podman "${podman_args[@]}" {{ args }}

_sudo_podman_cmd *args:
    #!/usr/bin/env bash
    set -eoux pipefail
    declare -a podman_args=()
    if [[ "$(uname)" == "Darwin" ]]; then
        if [[ -z "${podman_connection}" ]]; then
            true
        elif [[ "${podman_connection}" == "root" ]]; then
            podman_args+=("--connection=$(podman system connection list --format '{{{{.Name}} {{{{.URI}}' | grep "127.0.0.1" | grep root | awk '{ print $1 }')")
        else
            podman_args+=("--connection=${podman_connection}")
        fi
    fi
    just sudoif podman "${podman_args[@]}" {{ args }}

# Build the shared tooling container (shellcheck, shfmt, oras, systemd-repart, etc.)

# Required before using lint, format, or ext-* recipes when tools are not installed natively
[group('Utility')]
build-tools:
    just _podman_cmd build \
        --tag="${tools_image}" \
        --file=Containerfile.tools \
        .

# Run a command inside the tools container with the repo mounted at /work (unprivileged)
[private]
_tool *args:
    #!/usr/bin/env bash
    set -eoux pipefail
    just _podman_cmd run \
        --rm \
        --volume "$(pwd):/work:z" \
        --workdir /work \
        "${tools_image}" \
        {{ args }}

# Run a command inside the tools container with elevated privileges (for systemd-repart, loop devices)
[private]
_tool_privileged *args:
    #!/usr/bin/env bash
    set -eoux pipefail
    just _sudo_podman_cmd run \
        --rm \
        --privileged \
        --volume "$(pwd):/work:z" \
        --workdir /work \
        "${tools_image}" \
        {{ args }}

# This Justfile recipe builds a container image using Podman.
#
# Arguments:
#   $target_image - The tag you want to apply to the image (default: $image_name).
#   $tag - The tag for the image (default: $default_tag).
#
# The script constructs the version string using the tag and the current date.
# If the git working directory is clean, it also includes the short SHA of the current HEAD.
#
# just build $target_image $tag
#
# Example usage:
#   just build aurora lts
#
# This will build an image 'aurora:lts' with DX and GDX enabled.
#

# Build the image using the specified parameters
build $target_image $tag=default_tag $registry=image_registry $ns=image_ns:
    #!/usr/bin/env bash

    set -euxo pipefail

    container_host="${target_image}"

    container_url="${container_source}/pkgs/container/${container_host}"
    container_documentation="${container_source}/blob/main/README.md"

    if [[ "${target_image}" == "installer" ]]; then
        container_title="Fedora ${fedora_version} bootc secure base installer image"
        container_description="Interactive installer environment for HomeLabOS bare-metal installation"
    else
        container_title="Fedora ${fedora_version} bootc secure base for ${container_host}"
        container_description="Fedora ${fedora_version} bootc-derived OS with sd-boot/UKI tooling, systemd credentials, sysext/confext support, repart, sysupdate extension channels, portable services, homed, and nspawn support, built for ${container_host}."
    fi

    declare -a build_args
    build_args+=("--build-arg=FEDORA_VERSION=\"${fedora_version}\"")

    declare -a labels
    labels+=("org.opencontainers.image.title=\"${container_title}\"")
    labels+=("org.opencontainers.image.description=\"${container_description}\"")
    labels+=("org.opencontainers.image.created=\"${container_created}\"")
    labels+=("org.opencontainers.image.authors=\"${container_authors}\"")
    labels+=("org.opencontainers.image.url=\"${container_url}\"")
    labels+=("org.opencontainers.image.documentation=\"${container_documentation}\"")
    labels+=("org.opencontainers.image.source=\"${container_source}\"")
    labels+=("org.opencontainers.image.version=\"${container_version}\"")
    labels+=("org.opencontainers.image.revision=\"${container_revision}\"")
    labels+=("org.opencontainers.image.base.name=\"quay.io/fedora/fedora-bootc:${fedora_version}\"")
    labels+=("org.label-schema.schema-version=\"1.0\"")
    labels+=("org.label-schema.build-date=\"${container_created}\"")
    labels+=("org.label-schema.url=\"${container_url}\"")
    labels+=("org.label-schema.vcs-url=\"${container_source}\"")
    labels+=("org.label-schema.version=\"${container_version}\"")
    labels+=("org.label-schema.vcs-ref=\"${container_revision}\"")
    labels+=("org.label-schema.name=\"${container_title}\"")
    labels+=("org.label-schema.description=\"${container_description}\"")
    labels+=("org.label-schema.usage=\"${container_documentation}\"")
    labels+=("containers.bootc=\"1\"")

    for label in "${labels[@]}"; do
        build_args+=("--label=${label}")
        build_args+=("--annotation=${label}")
    done

    declare -a tags
    tags+=("--tag=${registry}/${ns}/${target_image}:${tag}")
    tags+=("--tag=${registry}/${ns}/${target_image}:${container_version}")

    just _podman_cmd build \
        "${build_args[@]}" \
        --arch="${target_arch}" \
        --created-annotation \
        --format=oci \
        --identity-label \
        --inherit-annotations \
        --inherit-labels \
        --layers \
        --pull=newer \
        --file="Containerfile.${target_image}" \
        "${tags[@]}" \
        .

run-container $target_image $tag=default_tag $registry=image_registry $ns=image_ns: _mkoutputdir
    #!/usr/bin/env bash
    set -eoux pipefail
    declare -a vols

    vols=("-v" "${output_dir}:/output")
    if [[ -d /dev ]]; then
        vols+=("-v /dev:/dev")
    fi
    if [[ -d /var/lib/containers ]]; then
        vols+=("-v /var/lib/containers:/var/lib/containers")
    fi
    if [[ -d "$HOME/.local/share/containers" ]]; then
        vols+=("-v ${HOME}/.local/share/containers:/var/lib/containers:Z")
    fi
    just _podman_cmd run \
        --rm -it \
        --privileged \
        --pid=host \
        --ipc=host \
        --security-opt label=type:unconfined_t \
        "${vols[@]}" \
        "${registry}/${ns}/${target_image}:${tag}" \
        /bin/bash

# Command: _rootful_load_image
# Description: This script checks if the current user is root or running under sudo. If not, it attempts to resolve the image tag using podman inspect.
#              If the image is found, it loads it into rootful podman. If the image is not found, it pulls it from the repository.
#
# Parameters:
#   $target_image - The name of the target image to be loaded or pulled.
#   $tag - The tag of the target image to be loaded or pulled. Default is 'default_tag'.
#
# Example usage:
#   _rootful_load_image my_image latest
#
# Steps:
# 1. Check if the script is already running as root or under sudo.
# 2. Check if target image is in the non-root podman container storage)
# 3. If the image is found, load it into rootful podman using podman scp.
# 4. If the image is not found, pull it from the remote repository into reootful podman.

_rootful_load_image $target_image $tag=default_tag $registry=image_registry $ns=image_ns:
    #!/usr/bin/env bash
    set -eoux pipefail

    # Check if already running as root or under sudo
    if [[ -n "${SUDO_USER:-}" || "${UID}" -eq "0" ]]; then
        echo "Already root or running under sudo, no need to load image from user podman."
        exit 0
    fi

    # Try to resolve the image tag using podman inspect
    set +e
    resolved_tag=$(just -q _podman_cmd inspect -t image "${registry}/${ns}/${target_image}:${tag}" | jq -r '.[].RepoTags.[0]')
    return_code=$?
    set -e

    USER_IMG_ID=$(just -q _podman_cmd images --filter reference="${registry}/${ns}/${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")

    if [[ $return_code -eq 0 ]]; then
        # If the image is found, load it into rootful podman
        ID=$(just sudoif podman images --filter reference="${registry}/${ns}/${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")
        if [[ "$ID" != "$USER_IMG_ID" ]]; then
            # If the image ID is not found or different from user, copy the image from user podman to root podman
            COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
            export TMPDIR=${COPYTMP}
            just _sudo_podman_cmd image scp ${UID}@localhost::"${registry}/${ns}/${target_image}:${tag}" root@localhost::"${registry}/${ns}/${target_image}:${tag}"
            rm -rf "${COPYTMP}"
        fi
    else
        # If the image is not found, pull it from the repository
        just sudoif podman pull --arch="${target_arch}" "${registry}/${ns}/${target_image}:${tag}"
    fi

_mkoutputdir:
    #!/usr/bin/env bash
    set -eoux pipefail
    if ! [[ -d "${output_dir}" ]]; then
        mkdir -p "${output_dir}"
    fi

# Build a bootc bootable image using Image Builder (IB)
# Converts a container image to a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (default: config/user.toml)

# Example: just _rebuild-ib localhost/fedora latest qcow2 config/user.toml
_build-ib $target_image $tag $type $config $registry=image_registry $ns=image_ns: (_rootful_load_image target_image tag registry ns) && _mkoutputdir
    #!/usr/bin/env bash
    set -euxo pipefail

    declare -a args=()
    args+=("--arch=${target_arch_raw}") 
    args+=("--blueprint=/config.toml")
    args+=("--bootc-ref=${registry}/${ns}/${target_image}:${tag}")
    args+=("--bootc-default-fs=xfs")
    args+=("--use-librepo")
    args+=("--output-dir=/output")
    args+=("${type}")

    BUILDTMP=$(mktemp -p "${PWD}" -d -t _build-ib.XXXXXXXXXX)

    just _sudo_podman_cmd run \
      --rm \
      -it \
      --privileged \
      --pull=newer \
      --net=host \
      --security-opt label=type:unconfined_t \
      -v $(pwd)/${config}:/config.toml:ro \
      -v $BUILDTMP:/output \
      -v /var/lib/containers/storage:/var/lib/containers/storage \
      "${ib_image}" build \
      "${args[@]}"

    sudo mv -f $BUILDTMP/* output/
    sudo rmdir $BUILDTMP
    sudo chown -R $USER:$USER output/

# Podman builds the image from the Containerfile and creates a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (deafult: config/user.toml)

# Example: just _rebuild-ib localhost/fedora latest qcow2 config/user.toml
_rebuild-ib $target_image $tag $type $config $registry=image_registry $ns=image_ns: (build target_image tag registry ns) && (_build-ib target_image tag type config registry ns)

# Build a QCOW2 virtual machine image
[group('Build Virtal Machine Image')]
build-qcow2 $target_image $tag=default_tag $registry=image_registry $ns=image_ns: && (_build-ib target_image tag "qcow2" "config/user.toml" registry ns)

# Build a RAW virtual machine image
[group('Build Virtal Machine Image')]
build-raw $target_image $tag=default_tag $registry=image_registry $ns=image_ns: && (_build-ib target_image tag "raw" "config/user.toml" registry ns)

# Build an ISO virtual machine image
[group('Build Virtal Machine Image')]
build-iso $target_image $tag=default_tag $registry=image_registry $ns=image_ns: && (_build-ib target_image tag "iso" "config/user.toml" registry ns)

# Rebuild a QCOW2 virtual machine image
[group('Build Virtal Machine Image')]
rebuild-qcow2 $target_image $tag=default_tag $registry=image_registry $ns=image_ns: && (_rebuild-ib target_image tag "qcow2" "config/user.toml" registry ns)

# Rebuild a RAW virtual machine image
[group('Build Virtal Machine Image')]
rebuild-raw $target_image $tag=default_tag $registry=image_registry $ns=image_ns: && (_rebuild-ib target_image tag "raw" "config/user.toml" registry ns)

# Rebuild an ISO virtual machine image
[group('Build Virtal Machine Image')]
rebuild-iso $target_image $tag=default_tag $registry=image_registry $ns=image_ns: && (_rebuild-ib target_image tag "iso" "config/user.toml" registry ns)

# Run a virtual machine with the specified image type and configuration
_run-vm $target_image $tag $type $config $registry=image_registry $ns=image_ns:
    #!/usr/bin/env bash
    set -eoux pipefail

    # Determine the image file based on the type
    image_file="output/${type}/disk.${type}"
    if [[ $type == iso ]]; then
        image_file="output/bootiso/install.iso"
    fi

    # Build the image if it does not exist
    if [[ ! -f "${image_file}" ]]; then
        just "build-${type}" "$target_image" "$tag" "$registry" "$ns"
    fi

    # Determine an available port (cross-platform: lsof on macOS, ss on Linux)
    port=8006
    _port_in_use() {
        if command -v ss &>/dev/null; then
            ss -tunalp 2>/dev/null | grep -q ":${1}\b"
        elif command -v lsof &>/dev/null; then
            lsof -iTCP:"${1}" -sTCP:LISTEN &>/dev/null
        elif command -v netstat &>/dev/null; then
            netstat -an 2>/dev/null | grep -q "[.:]${1} "
        else
            return 1  # Can't check; assume available
        fi
    }
    while _port_in_use "${port}"; do
        port=$(( port + 1 ))
    done
    echo "Using Port: ${port}"
    echo "Connect to http://localhost:${port}"

    # Set up the arguments for running the VM
    run_args=()
    run_args+=(--rm --privileged)
    run_args+=(--pull=newer)
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=8G")
    run_args+=(--env "DISK_SIZE=64G")
    run_args+=(--env "TPM=Y")
    # KVM acceleration and GPU passthrough: only available on Linux with /dev/kvm
    if [[ -c /dev/kvm ]]; then
        run_args+=(--device=/dev/kvm)
        run_args+=(--env "GPU=Y")
    fi
    run_args+=(--volume "${PWD}/${image_file}":"/boot.${type}")
    run_args+=(docker.io/qemux/qemu)

    # Run the VM and open the browser to connect
    (sleep 30 && {{ open_cmd }} http://localhost:"$port") &
    just _podman_cmd run "${run_args[@]}"

# Run a virtual machine from a QCOW2 image
[group('Run Virtal Machine')]
run-vm-qcow2 $target_image $tag=default_tag $registry=image_registry $ns=image_ns: && (_run-vm target_image tag "qcow2" "config/user.toml" registry ns)

# Run a virtual machine from a RAW image
[group('Run Virtal Machine')]
run-vm-raw $target_image $tag=default_tag $registry=image_registry $ns=image_ns: && (_run-vm target_image tag "raw" "config/user.toml" registry ns)

# Run a virtual machine from an ISO
[group('Run Virtal Machine')]
run-vm-iso $target_image $tag=default_tag $registry=image_registry $ns=image_ns: && (_run-vm target_image tag "iso" "config/user.toml" registry ns)

# Run a virtual machine using systemd-vmspawn
[group('Run Virtal Machine')]
spawn-vm rebuild="0" type="qcow2" ram="6G":
    #!/usr/bin/env bash

    set -euo pipefail

    [ "{{ rebuild }}" -eq 1 ] && echo "Rebuilding the ISO" && just build-vm {{ rebuild }} {{ type }}

    systemd-vmspawn \
      -M "bootc-image" \
      --console=gui \
      --cpus=2 \
      --ram=$(echo {{ ram }}| /usr/bin/numfmt --from=iec) \
      --network-user-mode \
      --vsock=false --pass-ssh-key=false \
      -i ./output/**/*.{{ type }}

# Lint all Bash scripts with shellcheck (uses tools container if shellcheck not installed natively)
[group('Utility')]
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    if command -v shellcheck &>/dev/null; then
        find . -iname "*.sh" -type f -not -path "./.git/*" -exec shellcheck "{}" ";"
    else
        just _tool bash -c 'find /work -iname "*.sh" -type f -not -path "/work/.git/*" -exec shellcheck "{}" ";"'
    fi

# Format all Bash scripts with shfmt (uses tools container if shfmt not installed natively)
[group('Utility')]
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    if command -v shfmt &>/dev/null; then
        find . -iname "*.sh" -type f -not -path "./.git/*" -exec shfmt --write "{}" ";"
    else
        just _tool bash -c 'find /work -iname "*.sh" -type f -not -path "/work/.git/*" -exec shfmt --write "{}" ";"'
    fi
