# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A [bootc](https://bootc-dev.github.io/) (bootable container) project that builds hardened, immutable Fedora 44 OS images for a homelab. The OS is delivered as an OCI container derived from `quay.io/fedora/fedora-bootc`, then converted into bootable disk images (qcow2/raw/iso) via [Image Builder](https://github.com/osbuild/image-builder-cli). Every recipe is orchestrated through the `Justfile`.

There is no application code — the "source" is Containerfiles, shell scripts, and config files that are baked into an OS image.

## Build pipeline (two stages)

1. **Containerfile → OCI image** (`just build <target>`): `podman build` runs the per-host `Containerfile.<target>`, which installs packages and copies config from `root/` into the image.
2. **OCI image → bootable disk** (`just build-qcow2 <target>`, etc.): `_build-ib` runs the Image Builder container against the OCI image using `config/user.toml` as the blueprint, emitting to `output/`. This stage needs **rootful podman** and copies/pulls the image into root storage first (`_rootful_load_image`).

`rebuild-*` recipes re-run stage 1 then stage 2; `build-*` recipes assume the OCI image already exists.

**ISOs are different from qcow2/raw.** qcow2/raw deploy the OS filesystem directly and never depsolve. An ISO needs an Anaconda *installer environment*, so it uses image-builder's `bootc-installer` type with **two** container refs: `--bootc-ref` = the installer environment (`Containerfile.installer`, built per-payload via `just build-installer <target>` as `<target>-installer`) and `--bootc-installer-payload-ref` = the OS to install (the homelab image). This lives in the `_build-installer-ib` recipe, separate from `_build-ib`. Building an ISO requires *both* the `<target>-installer` and payload OCI images to exist — `just rebuild-iso <target>` builds everything in one shot.

## Common commands

```bash
just                         # list all recipes
just build homelab01         # build the OCI container image for a host
just build-qcow2 homelab01   # build OCI image's qcow2 disk (alias: build-vm)
just rebuild-qcow2 homelab01 # rebuild OCI image + disk
just run-vm-qcow2 homelab01  # boot the qcow2 in a QEMU web VM (alias: run-vm)
just run-container homelab01 # drop into a shell in the built OCI image

just build-installer homelab01  # build the Anaconda installer-environment image for a payload
just rebuild-iso homelab01   # rebuild installer + payload images, then the ISO
just run-vm-iso homelab01     # build (if needed) and boot the installer ISO

just check                   # run all lints (just + scripts + containers)
just fmt                     # format Justfile + shell scripts
just encrypt                 # re-encrypt secrets/ into root/ (see Secrets)
just clean                   # remove build artifacts
```

**Targets** are `homelab01`–`homelab04` (and `tools`). Each maps to `Containerfile.<target>`. `homelab01` is the only one with NVIDIA drivers/container toolkit; `homelab02`–`04` are otherwise identical. The first arg to most recipes is the target image name; it directly selects the Containerfile.

### Linting (what `just check` enforces)

- **`check-scripts`**: every `*.sh` must be executable, start with `#!/bin/bash` followed by `set -Eeuxo pipefail` (or `set -Eeuo pipefail`), and pass `shellcheck`. A script can opt out by making its first line `# skip check` **and** removing the executable bit.
- **`check-containers`**: every `Containerfile*`/`Dockerfile*` must pass `hadolint` (config in `.hadolint.yml`; final image must also pass `bootc container lint`, run as the last Containerfile step).
- **`check-just`**: `just --fmt --check`.

Run a single lint directly: `just shellcheck <file>`, `just hadolint <file>`, `just shfmt <file>`.

## The tools container (cross-platform dev tooling)

Dev/build tools (shellcheck, shfmt, hadolint, sops, age, oras, skopeo, systemd-repart…) run inside `Containerfile.tools` so the repo works identically on macOS and Linux without native installs. Every utility recipe (`shellcheck`, `hadolint`, `sops`, etc.) first checks for the tool natively and falls back to `_tool` (runs it in the container with the repo mounted at `/work`).

```bash
just build-tools   # build the tools image first (required if tools aren't installed natively)
```

On **macOS**, podman runs in a VM; `_podman_cmd`/`_sudo_podman_cmd` route through `PODMAN_CONNECTION` (set to `root` to auto-select the rootful machine connection). Stage 2 (Image Builder) requires rootful podman and is effectively Linux-only.

## Secrets architecture (SOPS + age + TPM)

Secrets are encrypted at rest in git and rendered to plaintext only at boot:

- `secrets/` holds **plaintext** files, laid out by their target install path (e.g. `secrets/usr/libexec/aliases.sh`). This dir is gitignored.
- `just encrypt` walks `secrets/`, runs `sops encrypt` per file, and writes two artifacts into `root/` (committed): `<path>.enc` (ciphertext) and `<path>.perms` (target `uid`/`gid`/`mode` sidecar). Ownership matching the invoking user is normalized to `0`.
- At boot, `enroll-sops-age-key.service` prompts once for the age secret key and seals it into a **TPM2-bound systemd credential** (`/etc/credstore.encrypted/sops-age-key.cred`). `render-sops-secrets.service` then loads that credential and runs `render-sops-secrets.sh`, which decrypts every `*.enc` under `/etc` (and under `/usr`, written out to `/var`) applying the `.perms`.
- `.sops.yaml` defines age recipients; `.envrc` points `SOPS_AGE_KEY_FILE` at `main-key.txt`. The `*-key.txt` files are gitignored age identities — **never commit them**.

Note the `/usr` → `/var` redirect in `render-sops-secrets.sh`: bootc's `/usr` is read-only at runtime, so secrets destined for `/usr` paths are encrypted under `root/usr/...` but decrypted to the corresponding `/var/...` location.

## Image internals

- **`root/`** mirrors the image filesystem; adding config means dropping a file here and adding a matching `COPY` line in the Containerfile(s).
- **`build/`** holds RUN-stage scripts: `install-packages.sh` (reads `base-pkgs.txt`), `dnf/*.sh` (extra repos: rpm-fusion, terra, nvidia), `services.sh` (systemctl enable/disable list), `pam.sh`, `postfix.sh`, `firewalld.sh`, `cleanup.sh` (strips `/var` state and caches to shrink the image).
- Heavy **security hardening** is baked in: kernel cmdline hardening (`kargs.d/`), sysctl/modprobe hardening, auditd rules, SSH hardening, fail2ban, ClamAV (+ fangfrisch signature mirroring), rkhunter timer, FIPS-oriented config, `composefs`+verity via `prepare-root.conf`. When editing these, preserve the hardening intent.
- `config/user.toml` is the Image Builder blueprint (kernel args, the `annie` user, Anaconda installer modules). It is **not** baked into the OCI image — it only applies at the disk-build stage.

## Conventions

- Version/labels are derived in the `Justfile` from git tags (`container_version`) and `git rev-parse` (`container_revision`); OCI labels are generated, not hand-written.
- Shell scripts end with a `# vim:` modeline and use 4-space indent (`shfmt --indent=4`).
- The four host Containerfiles are kept in sync by hand — a change to one (other than the NVIDIA block) almost always belongs in all four.
