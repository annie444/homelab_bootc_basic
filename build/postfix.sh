#!/bin/bash
set -Eeuxo pipefail

# shellcheck disable=SC2016
declare -A postfix_config=(
    [smtpd_relay_restrictions]="permit_mynetworks permit_sasl_authenticated defer_unauth_destination"
    [myhostname]="ov-hjhjhjhj.kjkjkjj.ch"
    [alias_maps]="hash:/etc/aliases"
    [alias_database]="hash:/etc/aliases"
    [myorigin]="/etc/mailname"
    [mydestination]='$myhostname, mydomaine.com, ov-b2bbd0.infomaniak.ch, localhost.infomaniak.ch, localhost'
    [relayhost]="[127.0.0.1]:1025"
    [mynetworks]="127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128"
    [mailbox_size_limit]="0"
    [recipient_delimiter]="+"
    [inet_interfaces]="loopback-only"
    [inet_protocols]="all"
    [smtp_sasl_auth_enable]="yes"
    [smtp_sasl_password_maps]="hash:/etc/postfix/sasl_passwd"
    [smtp_sasl_security_options]="noanonymous"
)

for conf_key in "${!postfix_config[@]}"; do
    postconf -e "$conf_key"="${postfix_config[$conf_key]}"
done
# vim: set ft=bash et tw=4 sw=4 sts=4:
