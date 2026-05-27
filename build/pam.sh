#!/bin/bash
set -Eeuxo pipefail

{ export PS4='+( ${BASH_SOURCE}:${LINENO} ): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'; } 2>/dev/null

sed --in-place \
    's/^#auth[[:space:]]*required[[:space:]]*pam_wheel.so[[:space:]]use_uid$/auth  required pam_wheel.so use_uid/g' \
    /etc/pam.d/su
# vim: set ft=bash et tw=4 sw=4 sts=4:
