#!/usr/bin/env bash

dnf5 install -y crypto-policies-scripts
update-crypto-policies --no-reload --set FIPS
