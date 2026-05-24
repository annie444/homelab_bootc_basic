#!/bin/bash
set -Eeuo pipefail

umask 077

SCRIPT_NAME="$(basename "$0")"
should_fail=0

log() {
    printf '[%s] INFO %s\n' "$SCRIPT_NAME" "$*"
}

err() {
    printf '[%s] ERROR %s\n' "$SCRIPT_NAME" "$*" >&2
    should_fail=1
}

file_err() {
    local file="$1"
    shift
    err "$*"
    if [ -f "$file" ]; then
        rm -f -- "$file"
    elif [ -d "$file" ]; then
        rmdir -- "$file"
    fi
}

decrypt_dir() {
    local dir_name="$1"
    local dest_dir="${2:-$dir_name}"
    local first_bit file_basename relative_path out_dir unencrypted_file \
        target_uid target_gid target_mode file_perms
    while IFS= read -r -d '' file_name; do
        file_basename="${file_name%.enc}"
        relative_path="${file_basename#"$dir_name"/}"
        if [ "$relative_path" = "$file_basename" ]; then
            err "path $file_basename not under $dir_name"
            continue
        fi
        unencrypted_file="$dest_dir/$relative_path"
        file_perms="${file_basename}.perms"
        log "decrypting $file_name to $unencrypted_file with perms from $file_perms"
        target_uid="" target_gid="" target_mode=""
        if [ ! -f "$file_perms" ]; then
            err "missing perms sidecar: $file_perms"
            continue
        fi
        while IFS='=' read -r key value; do
            case "$key" in
            target_uid) target_uid="$value" ;;
            target_gid) target_gid="$value" ;;
            target_mode) target_mode="$value" ;;
            esac
        done <"$file_perms"
        log "setting permissions for $unencrypted_file: uid=$target_uid gid=$target_gid mode=$target_mode"
        if ! [[ "$target_mode" =~ ^[0-7]{3,4}$ ]] ||
            ! [[ "$target_uid" =~ ^[0-9]+$ ]] ||
            ! [[ "$target_gid" =~ ^[0-9]+$ ]]; then
            err "invalid .perms for $file_name"
            continue
        fi
        out_dir="$(dirname "$unencrypted_file")"
        if ! [ -d "$out_dir" ]; then
            if ! mkdir -p -- "$out_dir"; then
                err "cannot create directory: $out_dir"
                continue
            fi
            if ! chown "${target_uid}:${target_gid}" -- "$out_dir"; then
                file_err "$out_dir" "chown failed: $out_dir"
                continue
            fi
            first_bit="${target_mode:0:1}"
            if ! chmod "${first_bit}755" -- "$out_dir"; then
                file_err "$out_dir" "chmod failed: $out_dir"
                continue
            fi
        fi
        if ! sops decrypt --output "$unencrypted_file" "$file_name"; then
            file_err "$unencrypted_file" "decrypt failed: $file_name"
            continue
        fi
        if ! chown "${target_uid}:${target_gid}" -- "$unencrypted_file"; then
            file_err "$unencrypted_file" "chown failed: $unencrypted_file"
            continue
        fi
        if ! chmod "$target_mode" -- "$unencrypted_file"; then
            file_err "$unencrypted_file" "chmod failed: $unencrypted_file"
            continue
        fi
    done < <(find "$dir_name" -type f -name "*.enc" -print0)
}

decrypt_dir "/etc"
decrypt_dir "/usr" "/var"

exit "$should_fail"
# vim: set ft=bash et tw=4 sw=4 sts=4:
