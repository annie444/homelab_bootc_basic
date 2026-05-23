#!/bin/bash
set -euxo pipefail

systemctl enable systemd-homed.service
systemctl enable podman.socket
systemctl enable cockpit.socket
systemctl enable clamav-freshclam.service
systemctl enable clamd@scan.service
systemctl enable sshd.service
systemctl enable postfix.service
