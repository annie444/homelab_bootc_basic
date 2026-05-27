#!/bin/bash
set -Eeuxo pipefail

{ export PS4='+( ${BASH_SOURCE}:${LINENO} ): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'; } 2>/dev/null

declare -a enabled_services=(
    "systemd-resolved.service"
    "NetworkManager.service"
    "podman.socket"
    "podman-auto-update.timer"
    "cockpit.socket"
    "clamav-freshclam.service"
    "clamd@scan.service"
    "sshd.service"
    "postfix.service"
    "rkhunter.timer"
    "bootc-fetch-apply-updates.timer"
    "rngd.service"
    "chronyd.service"
    "cachefilesd.service"
    "fail2ban.service"
    "postfix.service"
    "enroll-sops-age-key.service"
    "render-sops-secrets.service"
)

declare -a disabled_services=(
    "debug-shell.service"
)

for service in "${disabled_services[@]}"; do
    systemctl disable "$service"
done

for service in "${enabled_services[@]}"; do
    systemctl enable "$service"
done
# vim: set ft=bash et tw=4 sw=4 sts=4:
