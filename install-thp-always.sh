#!/bin/bash -x

cd "$(dirname "$0")"

cp -r thp-always.service.d thp-always.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now thp-always.service
systemctl status thp-always.service
