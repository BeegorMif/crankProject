#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 [--skip-pull | --pull-only] [--deps]"
    echo "  (no flags)   pull all repos, then build all repos (dependency installs skipped)"
    echo "  --skip-pull  build only, using whatever is on disk (local changes safe)"
    echo "  --deps       also install/update build dependencies before building"
    echo "  --pull-only  fetch/update repos, don't build"
    exit 1
}

show_status() {
    printf '\033c' > /dev/tty1 2>/dev/null || true
    {
        echo "=== Crankshaft Update ==="
        echo ""
        echo "$1"
    } > /dev/tty1 2>/dev/null || true
}

DO_PULL=1
DO_BUILD=1
DO_DEPS=0

for arg in "$@"; do
    case "$arg" in
        --skip-pull) DO_PULL=0 ;;
        --pull-only) DO_BUILD=0 ;;
        --deps) DO_DEPS=1 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $arg"; usage ;;
    esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# name|url|branch  (blank branch = repo default)
REPOS=(
    "crankshaft_aasdk|https://github.com/BeegorMif/crankshaft_aasdk|"
    "crankshaft-core|https://github.com/BeegorMif/crankshaft-core|"
    "crankshaft-ui-slim|https://github.com/BeegorMif/crankshaft-ui-slim|"
)

DASH_REPOS=(
    "node_server|https://github.com/BeegorMif/node_server|crankshaft_ui_server"
    "dash_ui|https://github.com/BeegorMif/dash_ui|crankshaft_vue_ui"
)

pull_repo() {
    local name="$1" url="$2" branch="$3"
    show_status "Pulling $name..."
    if [ -d "$name/.git" ]; then
        echo "==> Updating $name"
        if [ -n "$branch" ]; then
            git -C "$name" fetch origin "$branch"
            git -C "$name" checkout "$branch"
            git -C "$name" pull --ff-only origin "$branch"
        else
            git -C "$name" pull --ff-only
        fi
    else
        echo "==> Cloning $name"
        if [ -n "$branch" ]; then
            git clone -b "$branch" "$url" "$name"
        else
            git clone "$url" "$name"
        fi
    fi
}

build_repo() {
    local name="$1"
    show_status "Building $name..."
    chmod +x "$name/build.sh"
    if [ "$DO_DEPS" -eq 1 ]; then
        show_status "Installing deps for $name..."
        echo "==> Installing deps for $name"
        (cd "$name" && ./build.sh --install-deps)
    else
        echo "==> Skipping dep install for $name"
    fi
    if [ "$name" = "crankshaft_aasdk" ]; then
        show_status "Building + installing $name..."
        echo "==> Building + installing $name (library)"

        # Build and install our local AASDK into /usr/local.
        (cd "$name" && \
            CMAKE_INSTALL_PREFIX=/usr/local \
            INSTALL_AFTER_BUILD=ON \
            ./build.sh)

        # Make the local AASDK take precedence over any distro package.
        sudo ldconfig

        echo "==> Installed AASDK:"
        ldconfig -p | grep libaasdk || true
    else
        show_status "Building + packaging $name..."
        echo "==> Building + packaging $name"
        (cd "$name" && BUILD_PACKAGE=ON ./build.sh)
        install_deb_packages "$name"
    fi
}

install_deb_packages() {
    local name="$1"
    local pkg_dir="${ROOT_DIR}/${name}/build-release/packages"
    shopt -s nullglob
    local debs=("$pkg_dir"/*.deb)
    shopt -u nullglob
    if [ "${#debs[@]}" -eq 0 ]; then
        echo "==> WARNING: no .deb found in $pkg_dir, skipping install"
        return
    fi
    show_status "Installing package for $name..."
    echo "==> Installing ${debs[*]}"
    sudo apt-get install -y --reinstall "${debs[@]}"
    echo "==> Removing installed .deb packages"
    rm -f "${debs[@]}"
}

build_node_server() {
    local name="$1"
    show_status "Setting up $name..."
    if [ "$DO_DEPS" -eq 1 ]; then
        echo "==> npm install for $name"
        (cd "$name" && npm install)
    else
        echo "==> Skipping npm install for $name"
    fi
}

build_dash_ui() {
    local name="$1"
    show_status "Building $name..."
    if [ "$DO_DEPS" -eq 1 ]; then
        echo "==> npm install for $name"
        (cd "$name" && npm install)
    else
        echo "==> Skipping npm install for $name"
    fi
    echo "==> npm run build for $name"
    (cd "$name" && npm run build)
}

# Installs $src -> $dst (with mode $3) only if it's missing or changed.
# Returns 0 (and prints/installs) if it installed something, 1 otherwise —
# use that to gate any one-off post-install step (enable a unit, reload udev...).
install_managed_file() {
    local src="$1" dst="$2" mode="$3" label="$4"
    if [ ! -f "$src" ]; then
        echo "==> WARNING: $src not found, skipping $label install"
        return 1
    fi
    if cmp -s "$src" "$dst" 2>/dev/null; then
        return 1
    fi
    show_status "Installing $label..."
    echo "==> Installing $label"
    sudo install -m "$mode" "$src" "$dst"
}

if [ "$DO_PULL" -eq 1 ]; then
    show_status "Pulling repositories..."
    for entry in "${REPOS[@]}"; do
        IFS='|' read -r name url branch <<< "$entry"
        pull_repo "$name" "$url" "$branch"
    done
    for entry in "${DASH_REPOS[@]}"; do
        IFS='|' read -r name url branch <<< "$entry"
        pull_repo "$name" "$url" "$branch"
    done
else
    echo "==> Skipping pull (using local working copies as-is)"
fi

fix_crankshaft_user() {
    # ============================================================
    # Configure crankshaft X11 setup
    # ============================================================

    show_status "Configuring crankshaft user..."
    show_status "Stopping services for user setup..."
    sudo systemctl stop crankshaft-core.service crankshaft-ui-slim.service dashboard-xorg.service || true

    CRANKSHAFT_HOME="/home/crankshaft"

    # Make sure the crankshaft user exists
    if ! id crankshaft >/dev/null 2>&1; then
        sudo useradd --system \
            --home-dir "$CRANKSHAFT_HOME" \
            --create-home \
            --shell /bin/bash \
            crankshaft
    else
        echo "crankshaft user already exists"
    fi

    # Make sure the home directory exists
    sudo mkdir -p "$CRANKSHAFT_HOME"

    # Set the correct home directory and shell
    sudo usermod \
        --home "$CRANKSHAFT_HOME" \
        --shell /bin/bash \
        crankshaft

    # Ensure ownership
    sudo chown -R crankshaft:crankshaft "$CRANKSHAFT_HOME"

    # Xorg needs somewhere to write its log
    sudo -u crankshaft mkdir -p "$CRANKSHAFT_HOME/.local/share/xorg"

    # Prepare Xauthority
    sudo touch "$CRANKSHAFT_HOME/.Xauthority"
    sudo chown crankshaft:crankshaft "$CRANKSHAFT_HOME/.Xauthority"

    echo "crankshaft account:"
    getent passwd crankshaft

    echo "crankshaft home:"
    ls -ld "$CRANKSHAFT_HOME"

}

install_crankshaft_core_binary() {
    local binary_src="${ROOT_DIR}/crankshaft-core/build-release/core/crankshaft-core"
    local binary_dst="/usr/local/bin/crankshaft-core"

    if [ ! -f "$binary_src" ]; then
        echo "==> ERROR: Built crankshaft-core not found: $binary_src"
        exit 1
    fi

    show_status "Installing crankshaft-core binary..."
    echo "==> Installing $binary_src -> $binary_dst"

    sudo install -m 0755 "$binary_src" "$binary_dst"

    # Verify that the installed binary is using the local AASDK.
    if readelf -d "$binary_dst" |
        grep -qE 'libaasdk\.so\.4|libaap_protobuf\.so\.4'; then
        echo "==> ERROR: Installed crankshaft-core is linked against old AASDK"
        readelf -d "$binary_dst" |
            grep -E 'NEEDED.*(aasdk|aap_protobuf|protobuf)'
        exit 1
    fi

    echo "==> Installed crankshaft-core dependencies:"
    readelf -d "$binary_dst" |
        grep -E 'NEEDED.*(aasdk|aap_protobuf|protobuf)'
}

if [ "$DO_BUILD" -eq 1 ]; then
    show_status "Stopping services for update..."
    sudo systemctl stop crankshaft-xorg crankshaft-core.service crankshaft-ui-slim.service || true
    for entry in "${REPOS[@]}"; do
        name="${entry%%|*}"
        build_repo "$name"

        if [ "$name" = "crankshaft-core" ]; then
            install_crankshaft_core_binary
        fi
    done
    build_node_server "node_server"
    build_dash_ui "dash_ui"
    if install_managed_file "$ROOT_DIR/systemd/dash-server.service" \
        "/etc/systemd/system/dash-server.service" 0644 "dash-server.service"; then
        sudo systemctl enable dash-server.service
    fi

    if install_managed_file "$ROOT_DIR/systemd/crankshaft-pulseaudio.service" \
        "/etc/systemd/system/crankshaft-pulseaudio.service" 0644 "crankshaft-pulseaudio.service"; then
        sudo systemctl enable crankshaft-pulseaudio.service
    fi

    install_managed_file "$ROOT_DIR/systemd/crankshaft-set-default-audio-sink.sh" \
        "/usr/local/bin/crankshaft-set-default-audio-sink.sh" 0755 "audio sink helper script"

    if install_managed_file "$ROOT_DIR/systemd/dashboard-xorg.service" \
        "/etc/systemd/system/dashboard-xorg.service" 0644 "dashboard-xorg.service"; then
        sudo systemctl enable dashboard-xorg.service
    fi

    install_managed_file "$ROOT_DIR/systemd/crankshaft-xinit" \
        "/usr/local/bin/crankshaft-xinit" 0755 "crankshaft-xinit"

    if install_managed_file "$ROOT_DIR/systemd/99-waveshare-touchscreen.rules" \
        "/etc/udev/rules.d/99-waveshare-touchscreen.rules" 0644 "99-waveshare-touchscreen.rules"; then
        sudo udevadm control --reload-rules
        sudo udevadm trigger
    fi
    fix_crankshaft_user
    show_status "Restarting services..."
    sudo systemctl daemon-reload
    sudo systemctl restart dashboard-xorg.service
    sudo systemctl restart dash-server.service
    sudo systemctl restart crankshaft-core.service
    sudo systemctl restart crankshaft-ui-slim.service
else
    echo "==> Skipping build (--pull-only)"
fi

echo "==> Done"