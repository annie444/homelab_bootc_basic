#!/bin/bash
set -euxo pipefail

systemctl enable systemd-homed.service
systemctl enable podman.socket
systemctl enable cockpit.socket
