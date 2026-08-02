#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 [--skip-pull | --pull-only]"
    echo "  (no flags)   pull all repos, then build all repos"
    echo "  --skip-pull  build only, using whatever is on disk (local changes safe)"
    echo "  --pull-only  fetch/update repos, don't build"
    exit 1
}

DO_PULL=1
DO_BUILD=1
case "${1:-}" in
    --skip-pull) DO_PULL=0 ;;
    --pull-only) DO_BUILD=0 ;;
    "") ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
esac

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
    chmod +x "$name/build.sh"
    echo "==> Installing deps for $name"
    (cd "$name" && ./build.sh --install-deps)
    echo "==> Building $name"
    (cd "$name" && BUILD_TESTS=OFF ./build.sh)
}

build_node_server() {
    local name="$1"
    echo "==> npm install for $name"
    (cd "$name" && npm install)
}

build_dash_ui() {
    local name="$1"
    echo "==> npm install for $name"
    (cd "$name" && npm install)
    echo "==> npm run build for $name"
    (cd "$name" && npm run build)
}

if [ "$DO_PULL" -eq 1 ]; then
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
    sudo systemctl stop crankshaft-core.service
    sudo systemctl stop crankshaft-ui-slim.service
    for entry in "${REPOS[@]}"; do
        name="${entry%%|*}"
        build_repo "$name"
    done
    build_node_server "node_server"
    build_dash_ui "dash_ui"
    sudo systemctl restart crankshaft-core.service
    sudo systemctl restart crankshaft-ui-slim.service
    sudo systemctl restart dash-server.service
else
    echo "==> Skipping build (--pull-only)"
fi

echo "==> Done"