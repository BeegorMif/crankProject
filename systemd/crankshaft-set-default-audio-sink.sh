#!/usr/bin/env bash
# Waits for PulseAudio to be ready, then sets the default sink to the first
# USB audio device found, if any exists. Falls back to leaving Pulse's own
# default untouched if no USB audio device is present, so this degrades
# gracefully on other hardware.
set -euo pipefail

export XDG_RUNTIME_DIR=/run/crankshaft
export PULSE_RUNTIME_PATH=/run/crankshaft/pulse

# Wait briefly for the daemon to finish starting and enumerate sinks.
for _ in $(seq 1 20); do
  if pactl info >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

usb_sink=$(pactl list sinks | awk '
  /^Sink #/ { name="" }
  /Name:/ { name=$2 }
  /device.bus = "usb"/ { print name; exit }
')

if [ -n "${usb_sink:-}" ]; then
  pactl set-default-sink "$usb_sink"
  echo "crankshaft-set-default-audio-sink: set default sink to $usb_sink"
else
  echo "crankshaft-set-default-audio-sink: no USB audio sink found, leaving default as-is"
fi