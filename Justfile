export image_registry := env("IMAGE_REGISTRY", "ghcr.io")
export image_ns := env("IMAGE_NS", "annie444")
export default_tag := env("DEFAULT_TAG", "latest")
export ib_image := env("IB_IMAGE", "ghcr.io/osbuild/image-builder-cli:latest")
export podman_connection := env("PODMAN_CONNECTION", "")
export fedora_version := env("FEDORA_VERSION", "44")
export output_dir := justfile_directory() + "/output"
export tools_image := env("TOOLS_IMAGE", "localhost/homelab-tools:latest")
export installer_image := env("INSTALLER_IMAGE", "installer")
export target_arch_raw := env("TARGET_ARCH", arch())
git_tag_version := `git tag -l | sed -E 's/^[^0-9]*//g' | sort --version-sort | tail -n 1`
export container_version := if git_tag_version != "" { git_tag_version } else { "0.1.0-0" }
export container_authors := 'Analetta "Annie" Ehler <annie.ehler.4@gmail.com>'
export container_source := "https://github.com/annie444/homelab_bootc_basic"
export container_revision := `git rev-parse --short HEAD`
export container_created := `date --rfc-3339="seconds"`
open_cmd := if os() == "windows" { "start" } else if os() == "darwin" { "open" } else { "xdg-open" }
export target_arch := if target_arch_raw == "amd64" { "amd64" } else if target_arch_raw == "arm64" { "aarch64" } else if target_arch_raw == "x86_64" { "amd64" } else { target_arch_raw }

debug := '''
set -Eeuo pipefail
if [ -n "${DEBUG:-}" ] && [ "${DEBUG:-}" -eq 1 ]; then
    set -x
fi
'''

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

[group('Dev')]
encrypt:
    #!/usr/bin/env bash
    {{ debug }}
    SRC="./secrets"
    DST="./root"
    if ! [ -d "$SRC" ]; then
        echo "Source directory $SRC does not exist. Please create it and add files to encrypt."
        exit 1
    fi
    current_uid="$(id -ru)"
    current_gid="$(id -rg)"
    should_fail=0
    get_id() {
        local owner="$1"
        local current="$2"
        if ((owner == current)); then
            printf '0\n'
        else
            printf '%d\n' "$owner"
        fi
    }
    while IFS= read -r -d '' file; do
        if ! stat_out="$(stat -c '%u %g %04a' -- "$file" 2>/dev/null)"; then
            printf 'stat failed: %s\n' "$file" >&2
            should_fail=1
            continue
        fi
        read -r owner_uid group_gid target_mode <<< "$stat_out"
        target_uid="$(get_id "$owner_uid" "$current_uid")"
        target_gid="$(get_id "$group_gid" "$current_gid")"
        relative_path="${file#"$SRC"/}"
        relative_out_path="$DST/$relative_path"
        encrypted_filename="${relative_out_path}.enc"
        encrypted_permsname="${relative_out_path}.perms"
        dir="$(dirname "$encrypted_filename")"
        mkdir -p "$dir"
        if ! just sops encrypt "$file" > "$encrypted_filename"; then
            printf 'encryption failed: %s\n' "$file" >&2
            if [ -f "$encrypted_filename" ]; then
                rm -f "$encrypted_filename"
            fi
            if [ -f "$encrypted_permsname" ]; then
                rm -f "$encrypted_permsname"
            fi
            should_fail=1
            continue
        fi
        {
            echo "target_uid=$target_uid"
            echo "target_gid=$target_gid"
            echo "target_mode=$target_mode"
        } > "$encrypted_permsname"
    done < <(find "$SRC" -type f -print0)
    exit "$should_fail"

# Run lints
[group('Dev')]
[parallel]
check: check-just check-scripts check-containers

# Check Just Syntax
[group('Dev')]
check-just:
    #!/usr/bin/env bash
    {{ debug }}
    find . -type f -name "*.just" -print0 | while IFS= read -r -d '' file; do
    	just --fmt --check -f $file
    done
    just --fmt --check -f Justfile

# Check scripts for shebang and safety flags
[group('Dev')]
check-scripts:
    #!/usr/bin/env bash
    {{ debug }}
    expected_top_lines='#!/bin/bash
    set -Eeuxo pipefail'
    alt_expected_top_lines='#!/bin/bash
    set -Eeuo pipefail'
    should_fail=0
    find . -type f -name "*.sh" -print0 | while IFS= read -r -d '' file; do
        if [[ "$(head -n 1 "$file")" == "# skip check" ]]; then
            [ -x "$file" ] && {
                echo "Script $file is executable but marked to skip check. Please remove the executable permission or the skip check comment."
                should_fail=1
            }
            continue
        fi
        [ -x "$file" ] || {
            echo "Script $file is not executable."
            should_fail=1
        }
        top_lines="$(head -n 2 "$file")"
        if [[ "$top_lines" != "$expected_top_lines" && "$top_lines" != "$alt_expected_top_lines" ]]; then
            echo "Script $file does not have the expected shebang and safety flags."
            should_fail=1
        fi
        just shellcheck "$file" || should_fail=1
    done
    if ((should_fail == 1)); then
        echo "Expected:"
        echo "$expected_top_lines"
        echo "Found:"
        echo "$top_lines"
    fi
    exit "$should_fail"

# Check containerfiles
[group('Dev')]
check-containers:
    #!/usr/bin/env bash
    {{ debug }}
    should_fail=0
    find . -type f \( -name "Containerfile*" -o -name "Dockerfile*" \) -print0 | while IFS= read -r -d '' file; do
        just hadolint "$file" || should_fail=1
    done
    exit "$should_fail"

# Format files
[group('Dev')]
[parallel]
fmt: fmt-just fmt-scripts

# Fix Just Syntax
[group('Dev')]
fmt-just:
    #!/usr/bin/env bash
    {{ debug }}
    find . -type f -name "*.just" -print0 | while IFS= read -r -d '' file; do
    	just --fmt -f $file
    done
    just --fmt -f Justfile || { exit 1; }

# Fix scripts syntax
[group('Dev')]
fmt-scripts:
    #!/usr/bin/env bash
    {{ debug }}
    find . -type f -name "*.sh" -print0 | while IFS= read -r -d '' file; do
        just shfmt "$file"
    done

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/env bash
    {{ debug }}
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
    {{ debug }}
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
    {{ debug }}
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
    {{ debug }}
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
    {{ debug }}
    just _podman_cmd run \
        --rm \
        --volume "${SOPS_AGE_KEY_FILE}:/.sops-age-key.txt:ro" \
        --volume "$(pwd):/work:z" \
        --env "SOPS_AGE_KEY_FILE=/.sops-age-key.txt" \
        --workdir /work \
        "${tools_image}" \
        {{ args }}

# Run a command inside the tools container with elevated privileges (for systemd-repart, loop devices)
[private]
_tool_privileged *args:
    #!/usr/bin/env bash
    {{ debug }}
    just _sudo_podman_cmd run \
        --rm \
        --privileged \
        --volume "${SOPS_AGE_KEY_FILE}:/.sops-age-key.txt:ro" \
        --volume "$(pwd):/work:z" \
        --env "SOPS_AGE_KEY_FILE=/.sops-age-key.txt" \
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
build $target_image $install_target='' $tag=default_tag $registry=image_registry $ns=image_ns:
    #!/usr/bin/env bash
    {{ debug }}

    container_host="${target_image}"

    container_url="${container_source}/pkgs/container/${container_host}"
    container_documentation="${container_source}/blob/main/README.md"

    declare -a build_args
    build_args+=("--build-arg=FEDORA_VERSION=\"${fedora_version}\"")

    if [[ "${target_image}" == "installer" ]]; then
        container_title="Fedora ${fedora_version} bootc secure base installer image"
        container_description="Interactive installer environment for HomeLabOS bare-metal installation"
        if [ -z "${install_target:-}" ]; then
            echo "Error: install_target must be specified when building the installer image." >&2
            exit 1
        fi
        build_args+=("--build-arg=TARGET_IMAGE=\"${install_target}\"")
        containerfile="${target_image}"
        tmp="${install_target##*/}"
        result_image="${tmp%%:*}"
        target_image="${result_image}-${target_image}"
    else
        container_title="Fedora ${fedora_version} bootc secure base for ${container_host}"
        container_description="Fedora ${fedora_version} bootc-derived OS with sd-boot/UKI tooling, systemd credentials, repart, and nspawn support, built for ${container_host}."
        containerfile="${target_image}"
    fi

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
        --file="Containerfile.${containerfile}" \
        "${tags[@]}" \
        .

# Push the image using the specified parameters
push $target_image $tag=default_tag $registry=image_registry $ns=image_ns:
    #!/usr/bin/env bash
    {{ debug }}

    declare -a containers
    containers+=("${registry}/${ns}/${target_image}:${tag}")
    containers+=("${registry}/${ns}/${target_image}:${container_version}")

    for container in "${containers[@]}"; do
        just _podman_cmd push \
            --format oci \
            --retry 3 \
            --retry-delay 3 \
            "${container}"
    done
run-container $target_image $tag=default_tag $registry=image_registry $ns=image_ns: _mkoutputdir
    #!/usr/bin/env bash
    {{ debug }}
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
    {{ debug }}

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
    {{ debug }}
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
    {{ debug }}

    declare -a args=()
    args+=("${type}")
    args+=("--arch=${target_arch_raw}")
    args+=("--blueprint=/config.toml")
    args+=("--bootc-default-fs=xfs")
    args+=("--bootc-ref=${registry}/${ns}/${target_image}:${tag}")
    args+=("--with-buildlog")
    args+=("--with-manifest")
    args+=("--with-metrics")
    args+=("--with-sbom")
    args+=("--output-dir=/output")

    BUILDTMP=$(mktemp -p "${PWD}" -d -t _build-ib.XXXXXXXXXX)

    just _sudo_podman_cmd run \
      --rm \
      -it \
      --privileged \
      --pull=newer \
      --net=host \
      --security-opt label=type:unconfined_t \
      -v "$(pwd)/${config}:/config.toml:ro" \
      -v "$BUILDTMP:/output:rw,z" \
      -v "/var/lib/containers/storage:/var/lib/containers/storage" \
      "${ib_image}" build \
      "${args[@]}"

    sudo mv -f $BUILDTMP/* output/
    sudo rmdir $BUILDTMP
    sudo chown -R $USER:$USER output/

# Build a bootc-installer ISO using Image Builder (IB).
#
# Unlike qcow2/raw (which deploy the OS filesystem directly and need no
# depsolving), an ISO needs an Anaconda *installer environment*. That maps to
# image-builder's `bootc-installer` type, which takes two container refs:
#   --bootc-ref                  -> the installer environment (Containerfile.installer)
#   --bootc-installer-payload-ref-> the OS that gets installed (the homelab image)
# Both images must already exist in (root) podman storage; this recipe loads both.
# Note: --bootc-default-fs is intentionally omitted -- the payload's root
# filesystem is chosen at install time (blueprint/kickstart), not now.
#
# Parameters:
#   payload_image: The OS image to install (ex. homelab02)
#   tag:           The tag shared by the installer and payload images
#   config:        The Image Builder blueprint (default: config/iso.toml)

# Example: just _build-installer-ib homelab02 latest config/iso.toml
_build-installer-ib $payload_image $tag $config $registry=image_registry $ns=image_ns: (_rootful_load_image installer_image tag registry ns) (_rootful_load_image payload_image tag registry ns) _mkoutputdir
    #!/usr/bin/env bash
    {{ debug }}

    declare -a args=()
    args+=("bootc-generic-iso")
    args+=("--arch=${target_arch_raw}")
    args+=("--blueprint=/config.toml")
    args+=("--bootc-default-fs=xfs")
    args+=("--bootc-ref=${registry}/${ns}/${payload_image}-${installer_image}:${tag}")
    args+=("--bootc-installer-payload-ref=${registry}/${ns}/${payload_image}:${tag}")
    args+=("--with-buildlog")
    args+=("--with-manifest")
    args+=("--with-metrics")
    args+=("--with-sbom")
    args+=("--output-dir=/output")

    BUILDTMP=$(mktemp -p "${PWD}" -d -t _build-ib.XXXXXXXXXX)

    just _sudo_podman_cmd run \
      --rm \
      -it \
      --privileged \
      --pull=newer \
      --net=host \
      --security-opt label=type:unconfined_t \
      -v "$(pwd)/${config}:/config.toml:ro" \
      -v "$BUILDTMP:/output:rw,z" \
      -v "/var/lib/containers/storage:/var/lib/containers/storage" \
      "${ib_image}" build \
      "${args[@]}"

    sudo mv -f "$BUILDTMP"/* "${output_dir}/"
    sudo rmdir "$BUILDTMP"
    sudo chown -R $USER:$USER "${output_dir}/"
    image_file="$(find "${output_dir}" -type f -name '*.iso' -print -quit)"
    if ! [ -f "$image_file" ]; then
        echo "No ISO found under ${output_dir}/ after build." >&2
        exit 1
    fi
    if ! [ -d "${output_dir}/bootiso" ]; then
        mkdir -p "${output_dir}/bootiso"
    fi
    cp "$image_file" "${output_dir}/bootiso/install.iso"

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

# Build the Anaconda installer-environment OCI image (run before build-iso)
[group('Build Virtal Machine Image')]
build-installer $tag=default_tag $registry=image_registry $ns=image_ns: (build installer_image tag registry ns)

# Build an installer ISO (installer + payload OCI images must already exist; else use rebuild-iso)
[group('Build Virtal Machine Image')]
build-iso $target_image $tag=default_tag $registry=image_registry $ns=image_ns: && (_build-installer-ib target_image tag "config/iso.toml" registry ns)

# Rebuild a QCOW2 virtual machine image
[group('Build Virtal Machine Image')]
rebuild-qcow2 $target_image $tag=default_tag $registry=image_registry $ns=image_ns: && (_rebuild-ib target_image tag "qcow2" "config/user.toml" registry ns)

# Rebuild a RAW virtual machine image
[group('Build Virtal Machine Image')]
rebuild-raw $target_image $tag=default_tag $registry=image_registry $ns=image_ns: && (_rebuild-ib target_image tag "raw" "config/user.toml" registry ns)

# Rebuild the installer + payload OCI images, then assemble the ISO
[group('Build Virtal Machine Image')]
rebuild-iso $target_image $tag=default_tag $registry=image_registry $ns=image_ns: (build installer_image tag registry ns) (build target_image tag registry ns) && (_build-installer-ib target_image tag "config/iso.toml" registry ns)

# Run a virtual machine with the specified image type and configuration
_run-vm $target_image $tag $type $config $registry=image_registry $ns=image_ns:
    #!/usr/bin/env bash
    {{ debug }}

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
run-vm-iso $target_image $tag=default_tag $registry=image_registry $ns=image_ns: && (_run-vm target_image tag "iso" "config/iso.toml" registry ns)

# Run a virtual machine using systemd-vmspawn
[group('Run Virtal Machine')]
spawn-vm rebuild="0" type="qcow2" ram="6G":
    #!/usr/bin/env bash
    {{ debug }}

    [ "{{ rebuild }}" -eq 1 ] && echo "Rebuilding the ISO" && just build-vm {{ rebuild }} {{ type }}

    systemd-vmspawn \
      -M "bootc-image" \
      --console=gui \
      --cpus=2 \
      --ram=$(echo {{ ram }}| /usr/bin/numfmt --from=iec) \
      --network-user-mode \
      --vsock=false --pass-ssh-key=false \
      -i ./output/**/*.{{ type }}

# Run the shellcheck shell script linter
[group('Utility')]
shellcheck $file:
    #!/usr/bin/env bash
    {{ debug }}
    if command -v shellcheck &>/dev/null; then
        shellcheck --check-sourced --external-sources "$file"
    else
        just _tool bash -c "shellcheck --check-sourced --external-sources '$file'"
    fi

# Run the shfmt shell script formatter
[group('Utility')]
shfmt $file:
    #!/usr/bin/env bash
    {{ debug }}
    if command -v shfmt &>/dev/null; then
        shfmt --write --indent=4  "$file"
    else
        just _tool bash -c "shfmt --write --indent=4  '$file'"
    fi

# Run the hadolint Containerfile linter
[group('Utility')]
hadolint $file:
    #!/usr/bin/env bash
    {{ debug }}
    if command -v hadolint &>/dev/null; then
        hadolint "$file"
    else
        just _tool bash -c "hadolint '$file'"
    fi

# Run the sops encryption utility
[group('Utility')]
sops +args:
    #!/usr/bin/env bash
    {{ debug }}
    if command -v sops &>/dev/null; then
        sops {{ args }}
    else
        just _tool bash -c 'sops {{ args }}'
    fi
