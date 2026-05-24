#!/bin/bash
set -Eeuxo pipefail

if ! [ -d /var/lib/fangfrisch ]; then
    mkdir -p /var/lib/fangfrisch
    chmod 0770 /var/lib/fangfrisch
    chown clamscan:virusgroup /var/lib/fangfrisch
fi

if ! [ -f /var/lib/clamav/urlhaus.ndb ]; then
    sudo -u clamscan -- /usr/local/bin/fangfrisch --conf /etc/fangfrisch.conf initdb
fi

/usr/local/bin/fangfrisch --conf /etc/fangfrisch.conf refresh
# vim: set ft=bash et tw=4 sw=4 sts=4:
