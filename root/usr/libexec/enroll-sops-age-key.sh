#!/bin/bash
set -Eeuo pipefail

CRED_NAME="sops-age-key"
CRED_DIR="/etc/credstore.encrypted"
CRED_PATH="${CRED_DIR}/${CRED_NAME}.cred"

log() {
    systemd-cat -t enroll-sops-age-key -p info echo "$*"
}

fail() {
    systemd-cat -t enroll-sops-age-key -p err echo "$*"
    exit 1
}

# Only run if credential doesn’t exist
if [[ -f "${CRED_PATH}" ]]; then
    log "Encrypted age key already exists; skipping enrollment."
    exit 0
fi

install -d -m 0700 "${CRED_DIR}"

# Prompt user for the age secret key using systemd prompt infrastructure
read_secret() {
    systemd-ask-password \
        --system \
        --no-tty \
        --timeout=0 \
        --echo=no \
        -n \
        "$1"
}

first="$(read_secret "Enter SOPS age identity" ||
    fail "Failed reading age secret.")"
second="$(read_secret "Confirm SOPS age identity" ||
    fail "Failed reading age secret.")"
if [[ "$first" != "$second" ]]; then
    fail "Submitted values did not match"
fi
AGE_SECRET="$first"

# Trim whitespace
AGE_SECRET="$(printf '%s' "${AGE_SECRET}" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

if [[ -z "${AGE_SECRET}" ]]; then
    fail "No age identity entered."
fi

# Simple pattern validation — the AGE secret should start with AGE-SECRET-KEY-1...
if [[ ! "${AGE_SECRET}" =~ ^AGE-SECRET-KEY-1[0-9A-Z]+$ ]]; then
    fail "Input does not look like a valid age secret key."
fi

# Optional: verify that age can derive a public key
tmpfile="$(mktemp /run/sops-age-identity.XXXXXX)"
chmod 600 "${tmpfile}"
printf '%s\n' "${AGE_SECRET}" >"${tmpfile}"

if ! age-keygen -y "${tmpfile}" >/dev/null 2>&1; then
    rm -f "${tmpfile}"
    fail "Provided key did not validate as a usable age secret identity."
fi
rm -f "${tmpfile}"

# Encrypt into a systemd credential bound to the host+TPM
printf '%s\n' "${AGE_SECRET}" | systemd-creds encrypt \
    --name="${CRED_NAME}" \
    --with-key=host+tpm2 \
    - \
    "${CRED_PATH}"

chmod 0400 "${CRED_PATH}"
log "Encrypted and stored credential at ${CRED_PATH}."
# vim: set ft=bash et tw=4 sw=4 sts=4:
