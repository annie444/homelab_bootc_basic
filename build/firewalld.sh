#!/bin/bash
set -Eeuxo pipefail

{ export PS4='+( ${BASH_SOURCE}:${LINENO} ): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'; } 2>/dev/null

declare -a services=(
    "cockpit"
    "dhcpv6-client"
    "llmnr-client"
    "mdns"
    "mosh"
    "ssh"
    "upnp-client"
)

declare -a add_services_cmds

for service in "${services[@]}"; do
    add_services_cmds+=("--add-service=${service}")
done

firewall-offline-cmd --zone=public "${add_services_cmds[@]}"
# vim: set ft=bash et tw=4 sw=4 sts=4:
