#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 [--ui-only | --core-only | --server-only] [--desktop]"
    echo "  (no flags)     start core, then node_server, then ui-slim, using eglfs"
    echo "                 (the Pi target default — full-screen DRM/KMS)"
    echo "  --core-only    start core only"
    echo "  --server-only  start node_server only"
    echo "  --ui-only      start ui-slim only (assumes core/server already running)"
    echo "  --desktop      run ui-slim windowed (QT_QPA_PLATFORM=xcb) instead of"
    echo "                 eglfs — use this on a desktop dev box with GNOME/X11"
    echo "                 already running, or eglfs will fight the desktop"
    echo "                 compositor for DRM master. Pi target should never"
    echo "                 pass this flag."
    exit 1
}

RUN_CORE=1
RUN_SERVER=1
RUN_UI=1
DESKTOP_MODE=0
for arg in "$@"; do
    case "$arg" in
        --core-only) RUN_SERVER=0; RUN_UI=0 ;;
        --server-only) RUN_CORE=0; RUN_UI=0 ;;
        --ui-only) RUN_CORE=0; RUN_SERVER=0 ;;
        --desktop) DESKTOP_MODE=1 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $arg"; usage ;;
    esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# CORE_BIN/UI_BIN/SERVER_JS paths — set once here, matches the systemd units
CORE_BIN="$ROOT_DIR/crankshaft-core/build-release/core/crankshaft-core"
UI_BIN="$ROOT_DIR/crankshaft-ui-slim/build-release/ui-slim/crankshaft-ui-slim"
SERVER_JS="$ROOT_DIR/node_server/server.cjs"

PIDS=()
cleanup() {
    echo "==> Shutting down"
    for pid in "${PIDS[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
}
trap cleanup INT TERM EXIT

if [ "$RUN_CORE" -eq 1 ]; then
    echo "==> Starting crankshaft-core"
    "$CORE_BIN" &
    CORE_PID=$!
    PIDS+=("$CORE_PID")
    # give core a moment to come up before anything tries to talk to it
    sleep 1
fi

if [ "$RUN_SERVER" -eq 1 ]; then
    echo "==> Starting node_server"
    node "$SERVER_JS" &
    SERVER_PID=$!
    PIDS+=("$SERVER_PID")
    # give the server a moment to come up before the UI tries to load it
    sleep 1
fi

if [ "$RUN_UI" -eq 1 ]; then
    echo "==> Starting crankshaft-ui-slim"
    if [ "$DESKTOP_MODE" -eq 1 ]; then
        echo "    (desktop mode: windowed via xcb, not eglfs)"
        QT_QPA_PLATFORM=xcb "$UI_BIN" &
    else
        QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-eglfs}" \
        QT_QPA_EGLFS_ALWAYS_SET_MODE="${QT_QPA_EGLFS_ALWAYS_SET_MODE:-1}" \
        "$UI_BIN" &
    fi
    UI_PID=$!
    PIDS+=("$UI_PID")
fi

echo "==> Running (Ctrl+C to stop)"
wait