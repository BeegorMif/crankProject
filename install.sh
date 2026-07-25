#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: sudo $0 [--enable] [--now]"
    echo "  (no flags)  copy unit files to systemd only — nothing starts, nothing"
    echo "              autostarts on boot. Safe to run on a desktop dev box."
    echo "  --enable    also 'systemctl enable' both units (autostart on boot)."
    echo "              Only pass this on the deployed Pi target."
    echo "  --now       also start the services immediately this run"
    echo "              (implies nothing about boot-time autostart on its own)"
    exit 1
}

ENABLE=0
START_NOW=0
for arg in "$@"; do
    case "$arg" in
        --enable) ENABLE=1 ;;
        --now) START_NOW=1 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $arg"; usage ;;
    esac
done

if [ "$EUID" -ne 0 ]; then
    echo "Run with sudo (needs to write to /etc/systemd/system)."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNITS=(crankshaft-core.service crankshaft-ui-slim.service)

for unit in "${UNITS[@]}"; do
    echo "==> Installing $unit"
    cp "$SCRIPT_DIR/systemd/$unit" "/etc/systemd/system/$unit"
done

systemctl daemon-reload

if [ "$ENABLE" -eq 1 ]; then
    for unit in "${UNITS[@]}"; do
        echo "==> Enabling $unit (will autostart on boot)"
        systemctl enable "$unit"
    done
else
    echo "==> Units installed but NOT enabled — will not autostart on boot."
    echo "    Re-run with --enable on the Pi target when you're ready for that."
fi

if [ "$START_NOW" -eq 1 ]; then
    for unit in "${UNITS[@]}"; do
        echo "==> Starting $unit now"
        systemctl start "$unit"
    done
fi

echo "==> Done. Check status with: systemctl status crankshaft-core crankshaft-ui-slim"