#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 [--skip-pull | --pull-only] [--skip-deps]"
    echo "  (no flags)   pull all repos, then build all repos"
    echo "  --skip-pull  build only, using whatever is on disk (local changes safe)"
    echo "  --deps  build only, skip installing dependencies (useful if deps already installed)"
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
        # aasdk is a library dependency, not packaged as a .deb — install it
        # directly so libaasdk headers/.so are on the system for the others to link against.
        show_status "Building + installing $name..."
        echo "==> Building + installing $name (library)"
        (cd "$name" && BUILD_TESTS=OFF INSTALL_AFTER_BUILD=ON ./build.sh)
    else
        show_status "Building + packaging $name..."
        echo "==> Building + packaging $name"
        (cd "$name" && BUILD_TESTS=OFF BUILD_PACKAGE=ON ./build.sh)
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

install_dash_server_unit() {
    local unit_src="${ROOT_DIR}/systemd/dash-server.service"
    local unit_dst="/etc/systemd/system/dash-server.service"
    if [ ! -f "$unit_src" ]; then
        echo "==> WARNING: $unit_src not found, skipping unit install"
        return
    fi
    if ! cmp -s "$unit_src" "$unit_dst" 2>/dev/null; then
        show_status "Installing dash-server service..."
        echo "==> Installing dash-server.service"
        sudo install -m 0644 "$unit_src" "$unit_dst"
        sudo systemctl enable dash-server.service
    fi
}

install_pulseaudio_server_unit() {
    local unit_src="${ROOT_DIR}/systemd/crankshaft-pulseaudio.service"
    local unit_dst="/etc/systemd/system/crankshaft-pulseaudio.service"
    if [ ! -f "$unit_src" ]; then
        echo "==> WARNING: $unit_src not found, skipping unit install"
        return
    fi
    if ! cmp -s "$unit_src" "$unit_dst" 2>/dev/null; then
        show_status "Installing pulseaudio service..."
        echo "==> Installing crankshaft-pulseaudio.service"
        sudo install -m 0644 "$unit_src" "$unit_dst"
        sudo systemctl enable crankshaft-pulseaudio.service
    fi
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

if [ "$DO_BUILD" -eq 1 ]; then
    show_status "Stopping services for update..."
    sudo systemctl stop crankshaft-core.service crankshaft-ui-slim.service || true
    for entry in "${REPOS[@]}"; do
        name="${entry%%|*}"
        build_repo "$name"
    done
    build_node_server "node_server"
    build_dash_ui "dash_ui"
    install_dash_server_unit
    install_pulseaudio_server_unit
    show_status "Restarting services..."
    sudo systemctl daemon-reload
    sudo systemctl restart crankshaft-core.service
    sudo systemctl restart crankshaft-ui-slim.service
    show_status "Update complete, restarting dash server..."
    sudo systemctl restart dash-server.service
else
    echo "==> Skipping build (--pull-only)"
fi

echo "==> Done"