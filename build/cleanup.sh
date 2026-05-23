#!/bin/bash

rm -rf /var/log/maillog
rm -rf /var/log/messages
rm -rf /var/log/secure
rm -rf /var/log/spooler
rm -rf /var/spool/anacron
rm -rf /var/spool/at
rm -rf /var/lib/dnf/repos/*
rm -rf /var/lib/plocate/CACHEDIR.TAG
rm -rf /var/lib/rkhunter/db/i18n/*
rm -rf /var/lib/systemd/catalog/database
rm -rf /var/account/pacct
rm -rf /var/cache/abrt-di/.migration-group-add
rm -rf /var/cache/ldconfig/aux-cache
rm -rf /var/cache/libdnf5/*
rm -rf /var/cache/swcatalog/cache/*
rm -rf /tmp/*
