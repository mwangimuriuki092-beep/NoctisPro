#!/usr/bin/env bash
set -euo pipefail

# Usage: sudo bash deploy/install-systemd.sh /path/to/repo

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash deploy/install-systemd.sh /path/to/repo" >&2
  exit 1
fi

REPO_DIR=${1:-}
if [[ -z "${REPO_DIR}" ]]; then
  echo "Usage: sudo bash deploy/install-systemd.sh /path/to/repo" >&2
  exit 1
fi

APP_DIR=/opt/noctis
mkdir -p "${APP_DIR}"

rsync -a --delete "${REPO_DIR}/" "${APP_DIR}/"

install -m 0644 "${APP_DIR}/deploy/noctis.service" /etc/systemd/system/noctis.service

systemctl daemon-reload
systemctl enable noctis.service
systemctl restart noctis.service

echo "Systemd service installed. Check status with: systemctl status noctis" 

