#!/bin/bash
set -Eeuxo pipefail

# shellcheck disable=SC2016
dnf5 install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release terra-gpg-keys
# vim: set ft=bash et tw=4 sw=4 sts=4:
