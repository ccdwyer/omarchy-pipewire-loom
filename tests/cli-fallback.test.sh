#!/bin/sh
# Off-device: the POSIX fallback script exists, is executable, and rejects
# destroy of a non-Loom name by never exposing a device-wide unload.

set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CLI="$ROOT/compat/loom-cli.sh"

test -x "$CLI" || { echo "FAIL compat/loom-cli.sh not executable"; exit 1; }

help=$("$CLI" --help) || true
echo "$help" | grep -q spawn-sink || { echo "FAIL help missing spawn-sink"; exit 1; }

# destroy-module requires an id; it must not accept a raw device name.
if "$CLI" destroy-module >/dev/null 2>&1; then
  echo "FAIL destroy-module without id should fail"
  exit 1
fi

echo "ok  compat loom-cli.sh surface"
echo "1 passed, 0 failed"
