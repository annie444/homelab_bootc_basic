#!/bin/bash
set -Eeuxo pipefail

/usr/bin/rkhunter \
    --configfile /etc/rkhunter.conf \
    --update

/usr/bin/rkhunter \
    --configfile /etc/rkhunter.conf \
    --check \
    --skip-keypress \
    --report-warnings-only \
    --no-mail-on-warning
# vim: set ft=bash et tw=4 sw=4 sts=4:
