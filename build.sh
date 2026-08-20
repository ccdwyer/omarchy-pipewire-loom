#!/bin/sh
# Build loomd. The plugin QML degrades to in-process pw-dump + compat/loom-cli.sh
# when bin/loomd is missing, so a failed build is not fatal at runtime.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SRC="$ROOT/src/loomd"
OUT="$ROOT/bin"

mkdir -p "$OUT"
chmod +x "$ROOT/compat/loom-cli.sh" 2>/dev/null || true

if ! command -v cargo >/dev/null 2>&1; then
  echo "build.sh: cargo not found; not installing a fake bin/loomd" >&2
  echo "build.sh: QML will use in-process pw-dump + wpctl (compat mode)"
  echo "build.sh: oneshot verbs: $ROOT/compat/loom-cli.sh --dump | --cmd JSON"
  exit 0
fi

# v1.0 ships the CLI poller only. Native libpipewire is parked.
built=
if cargo build --release --manifest-path "$SRC/Cargo.toml"; then
  built="$SRC/target/release/loomd"
  echo "build.sh: CLI loomd build ok"
fi

if [ -z "$built" ] || [ ! -x "$built" ]; then
  echo "build.sh: cargo build failed; not installing a fake bin/loomd" >&2
  echo "build.sh: QML will use in-process pw-dump + wpctl (compat mode)"
  echo "build.sh: oneshot verbs: $ROOT/compat/loom-cli.sh --dump | --cmd JSON"
  exit 0
fi

cp "$built" "$OUT/loomd"
chmod +x "$OUT/loomd"
echo "build.sh: wrote $OUT/loomd"
