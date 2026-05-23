#!/usr/bin/env bash

if ! [ -d /var/lib/fangfrisch ]; then
  mkdir -m 0770 -p /var/lib/fangfrisch
  chown clamscan:virusgroup /var/lib/fangfrisch
fi

if ! [ -f /var/lib/clamav/urlhaus.ndb ]; then
  sudo -u clamscan -- /usr/local/bin/fangfrisch --conf /etc/fangfrisch.conf initdb
fi

/usr/local/bin/fangfrisch --conf /etc/fangfrisch.conf refresh
