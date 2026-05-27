#!/bin/bash
set -Eeuxo pipefail

{ export PS4='+( ${BASH_SOURCE}:${LINENO} ): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'; } 2>/dev/null

rm -rf /tmp/*
rm -rf /run/fail2ban
rm -rf /run/cockpit
rm -rf /run/dnf
rm -rf /run/selinux-policy
rm -rf /run/setroubleshoot
rm -rf /run/certmonger
rm -rf /run/unbound
rm -rf /var/account
rm -rf /var/cache
rm -rf /var/lib/PackageKit
rm -rf /var/lib/abrt
rm -rf /var/lib/clamav
rm -rf /var/lib/dnsmasq
rm -rf /var/lib/fprint
rm -rf /var/lib/geoclue
rm -rf /var/lib/iscsi
rm -rf /var/lib/lastlog
rm -rf /var/lib/lockdown
rm -rf /var/lib/plymouth
rm -rf /var/lib/rpm-state
rm -rf /var/lib/rsyslog
rm -rf /var/lib/setroubleshoot
rm -rf /var/lib/smartmontools
rm -rf /var/lib/dnf
rm -rf /var/lib/plocate
rm -rf /var/lib/rkhunter
rm -rf /var/lib/postfix
rm -rf /var/lib/systemd
rm -rf /var/lib/fail2ban
rm -rf /var/lib/certmonger
rm -rf /var/lib/ipa-client
rm -rf /var/lib/samba/winbindd_privileged
rm -rf /var/roothome/.cache
rm -rf /var/log/*
rm -rf /var/spool/*
rm -rf /usr/etc
# vim: set ft=bash et tw=4 sw=4 sts=4:
