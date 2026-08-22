#!/usr/bin/env bash
# Installs and activates the Crankshaft Plymouth boot splash theme.
# Sourced/called from pull.sh — see snippet below.

set -euo pipefail

THEME_NAME="crankshaft"
THEME_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plymouth/${THEME_NAME}"
THEME_DEST_DIR="/usr/share/plymouth/themes/${THEME_NAME}"

install_plymouth_theme() {
    echo "Installing Plymouth theme: ${THEME_NAME}"

    if ! command -v plymouth-set-default-theme >/dev/null 2>&1; then
        echo "plymouth not found, installing..."
        sudo apt-get update
        sudo apt-get install -y plymouth plymouth-themes
    fi

    if [ ! -d "${THEME_SRC_DIR}" ]; then
        echo "ERROR: theme source dir not found at ${THEME_SRC_DIR}" >&2
        return 1
    fi
    if [ ! -f "${THEME_SRC_DIR}/logo.png" ]; then
        echo "WARNING: ${THEME_SRC_DIR}/logo.png missing — splash will show no logo." >&2
    fi

    sudo mkdir -p "${THEME_DEST_DIR}"
    sudo cp "${THEME_SRC_DIR}/${THEME_NAME}.plymouth" "${THEME_DEST_DIR}/"
    sudo cp "${THEME_SRC_DIR}/${THEME_NAME}.script" "${THEME_DEST_DIR}/"
    [ -f "${THEME_SRC_DIR}/logo.png" ] && sudo cp "${THEME_SRC_DIR}/logo.png" "${THEME_DEST_DIR}/"

    sudo plymouth-set-default-theme -R "${THEME_NAME}"

    # Optiplex 7010 uses GRUB, not the Pi's config.txt/cmdline.txt —
    # make sure the kernel cmdline actually enables the splash.
    if [ -f /etc/default/grub ] && ! grep -q 'splash' /etc/default/grub; then
        echo "Enabling 'quiet splash' in /etc/default/grub"
        sudo sed -i \
            's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 quiet splash"/' \
            /etc/default/grub
        sudo update-grub
    fi

    sudo update-initramfs -u

    echo "Plymouth theme '${THEME_NAME}' installed and set as default."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_plymouth_theme
fi