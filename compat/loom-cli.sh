#!/bin/sh
# POSIX fallback when bin/loomd is missing.
# Speaks the same verb surface the Rust helper does, one shot at a time.
# Graph snapshots are raw `pw-dump` JSON — QML parses them with js/PwDump.js.
#
# usage:
#   loom-cli.sh dump
#   loom-cli.sh move <stream-id> <sink-id>
#   loom-cli.sh link <out-port-id> <in-port-id>
#   loom-cli.sh unlink <out-port-id> <in-port-id>
#   loom-cli.sh volume <node-id> <0..1>
#   loom-cli.sh mute <node-id> <0|1>
#   loom-cli.sh spawn-sink <name>
#   loom-cli.sh destroy-module <module-id>
#   loom-cli.sh list-loom-sinks

set -eu

cmd=${1:-}
[ -n "$cmd" ] || { echo "loom-cli.sh: missing command" >&2; exit 2; }
shift || true

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "loom-cli.sh: $1 not on PATH" >&2
    exit 1
  fi
}

case "$cmd" in
  dump)
    need pw-dump
    pw-dump
    ;;
  move)
    stream=${1:-}
    target=${2:-}
    [ -n "$stream" ] && [ -n "$target" ] || { echo "usage: move STREAM TARGET" >&2; exit 2; }
    if command -v wpctl >/dev/null 2>&1 && wpctl set-target "$stream" "$target"; then
      exit 0
    fi
    need pw-metadata
    pw-metadata "$stream" target.object "$target"
    ;;
  link)
    need pw-link
    pw-link -I "${1:?}" "${2:?}"
    ;;
  unlink)
    need pw-link
    pw-link -d -I "${1:?}" "${2:?}"
    ;;
  volume)
    need wpctl
    wpctl set-volume "${1:?}" "${2:?}"
    ;;
  mute)
    need wpctl
    wpctl set-mute "${1:?}" "${2:?}"
    ;;
  spawn-sink)
    need pactl
    name=$1
    [ -n "$name" ] || name=Mix
    case "$name" in
      Loom-*) sink=$name ;;
      *) sink="Loom-$name" ;;
    esac
    pactl load-module module-null-sink "sink_name=$sink" "sink_properties=device.description=$sink"
    ;;
  destroy-module)
    need pactl
    mid=${1:-}
    [ -n "$mid" ] || { echo "usage: destroy-module ID" >&2; exit 2; }
    pactl unload-module "$mid"
    ;;
  list-loom-sinks)
    need pactl
    pactl list short sinks | awk '$2 ~ /^Loom-/ { print }'
    ;;
  --help|-h)
    sed -n '2,16p' "$0"
    ;;
  *)
    echo "loom-cli.sh: unknown command $cmd" >&2
    exit 2
    ;;
esac
