#!/bin/bash
set -Eeuxo pipefail

sed --in-place \
    's/^#auth[[:space:]]*required[[:space:]]*pam_wheel.so[[:space:]]use_uid$/auth  required pam_wheel.so use_uid/g' \
    /etc/pam.d/su
# vim: set ft=bash et tw=4 sw=4 sts=4:
