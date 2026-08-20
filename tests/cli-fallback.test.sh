#!/bin/sh
# Off-device: the POSIX fallback script exists, is executable, sanitizes
# names like JS/Rust, and implements --dump/--cmd/--cli without pretending
# to be a loomd daemon.

set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CLI="$ROOT/compat/loom-cli.sh"

test -x "$CLI" || { echo "FAIL compat/loom-cli.sh not executable"; exit 1; }

help=$("$CLI" --help) || true
echo "$help" | grep -q dump || { echo "FAIL help missing dump"; exit 1; }

# destroy-module requires an id; it must not accept a raw device name.
if "$CLI" destroy-module >/dev/null 2>&1; then
  echo "FAIL destroy-module without id should fail"
  exit 1
fi

got=$("$CLI" sanitize "a b/c")
[ "$got" = "Loom-abc" ] || { echo "FAIL sanitize got $got"; exit 1; }

got=$("$CLI" sanitize "Loom-Mix")
[ "$got" = "Loom-Mix" ] || { echo "FAIL sanitize prefix got $got"; exit 1; }

# --cli is not a daemon.
if "$CLI" --cli >/dev/null 2>&1; then
  echo "FAIL --cli should exit nonzero (not a daemon)"
  exit 1
fi

# --cmd with unknown op returns NDJSON err, not a crash.
out=$("$CLI" --cmd '{"op":"nope","id":"x"}' || true)
echo "$out" | grep -q '"t":"err"' || { echo "FAIL --cmd should emit err NDJSON: $out"; exit 1; }

# cleanupOrphans adopt/destroy against a fixture listing (no pactl).
export LOOM_MODULES_TEXT="$(printf '12\tmodule-null-sink\tsink_name=Loom-Mix\n13\tmodule-alsa-card\tdevice_id=0\n')"
export LOOM_DRY=1
out=$("$CLI" --cmd '{"op":"cleanupOrphans","id":"1","destroy":false}')
echo "$out" | grep -q 'Loom-Mix' || { echo "FAIL adopt should list Loom-Mix: $out"; exit 1; }
echo "$out" | grep -q '"adopted"' || { echo "FAIL adopt missing adopted: $out"; exit 1; }
out=$("$CLI" --cmd '{"op":"cleanupOrphans","id":"2","destroy":true}')
echo "$out" | grep -q '"removed"' || { echo "FAIL destroy missing removed: $out"; exit 1; }
echo "$out" | grep -q 'Loom-Mix' || { echo "FAIL destroy should list Loom-Mix: $out"; exit 1; }

# destroySink refuses a non-Loom name even with a live module id.
out=$("$CLI" --cmd '{"op":"destroySink","id":"3","name":"alsa_output","moduleId":12}' || true)
echo "$out" | grep -q '"err":"denied"' || { echo "FAIL destroySink must deny non-Loom: $out"; exit 1; }
unset LOOM_MODULES_TEXT LOOM_DRY

# build.sh must not install this script as bin/loomd.
if grep -q 'exec .*compat/loom-cli.sh' "$ROOT/build.sh"; then
  echo "FAIL build.sh still wraps loom-cli.sh as bin/loomd"
  exit 1
fi

echo "ok  compat loom-cli.sh surface"
echo "1 passed, 0 failed"
