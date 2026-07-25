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

# Root folder holding all three projects
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# name -> git URL, in required build order (aasdk before core before ui-slim)
REPOS=(
    "crankshaft_aasdk|https://github.com/BeegorMif/crankshaft_aasdk"
    "crankshaft-core|https://github.com/BeegorMif/crankshaft-core"
    "crankshaft-ui-slim|https://github.com/BeegorMif/crankshaft-ui-slim"
)

pull_repo() {
    local name="$1" url="$2"
    if [ -d "$name/.git" ]; then
        echo "==> Updating $name"
        git -C "$name" pull --ff-only
    else
        echo "==> Cloning $name"
        git clone "$url" "$name"
    fi
}

build_repo() {
    local name="$1"
    chmod +x "$name/build.sh"
    echo "==> Installing deps for $name"
    (cd "$name" && ./build.sh --install-deps)
    echo "==> Building $name"
    (cd "$name" && ./build.sh)
}

if [ "$DO_PULL" -eq 1 ]; then
    for entry in "${REPOS[@]}"; do
        name="${entry%%|*}"
        url="${entry##*|}"
        pull_repo "$name" "$url"
    done
else
    echo "==> Skipping pull (using local working copies as-is)"
fi

if [ "$DO_BUILD" -eq 1 ]; then
    for entry in "${REPOS[@]}"; do
        name="${entry%%|*}"
        build_repo "$name"
    done
else
    echo "==> Skipping build (--pull-only)"
fi

echo "==> Done"