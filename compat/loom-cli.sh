#!/bin/sh
# POSIX fallback when bin/loomd is missing.
# Speaks the same verb surface as loomd oneshots:
#   loom-cli.sh dump | --dump
#   loom-cli.sh --cmd '{"op":"move",...}'
#   loom-cli.sh move|link|unlink|volume|mute|spawn-sink|destroy-module|sanitize
# Graph snapshots from `dump` are raw `pw-dump` JSON — QML parses them
# with js/PwDump.js. This script is NOT a daemon; build.sh must not
# install it as bin/loomd.

set -eu

sanitize_sink_name() {
  raw=${1:-Mix}
  out=
  i=1
  len=${#raw}
  while [ "$i" -le "$len" ] && [ "${#out}" -lt 32 ]; do
    ch=$(printf '%s' "$raw" | cut -c "$i")
    case "$ch" in
      [A-Za-z0-9_-]) out=$out$ch ;;
    esac
    i=$((i + 1))
  done
  [ -n "$out" ] || out=Mix
  case "$out" in
    Loom-*) printf '%s\n' "$out" ;;
    *) printf 'Loom-%s\n' "$out" ;;
  esac
}

json_field() {
  # Best-effort extract of a top-level "key":"value" or "key":true/false/number.
  key=$1
  blob=$2
  printf '%s' "$blob" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

json_bool() {
  key=$1
  blob=$2
  printf '%s' "$blob" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\\(true\\|false\\).*/\\1/p" | head -n 1
}

json_num() {
  key=$1
  blob=$2
  printf '%s' "$blob" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\\([0-9.][0-9.]*\\).*/\\1/p" | head -n 1
}

json_id_list() {
  blob=$1
  printf '%s' "$blob" | sed -n 's/.*"nodes"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' | tr ',' ' '
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "loom-cli.sh: $1 not on PATH" >&2
    exit 1
  fi
}

list_modules_text() {
  if [ -n "${LOOM_MODULES_TEXT:-}" ]; then
    printf '%s\n' "$LOOM_MODULES_TEXT"
    return 0
  fi
  need pactl
  pactl list short modules
}

# Print "id<TAB>Loom-Name" for each live Loom null-sink.
iter_loom_modules() {
  list_modules_text | while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    id=$(printf '%s' "$line" | awk '{print $1}')
    name=$(printf '%s' "$line" | awk '{print $2}')
    rest=$(printf '%s' "$line" | awk '{ $1=""; $2=""; sub(/^  */, ""); print }')
    case "$name" in
      *module-null-sink*) ;;
      *) continue ;;
    esac
    sink=$(printf '%s' "$rest" | sed -n 's/.*sink_name=\(Loom-[A-Za-z0-9_-]*\).*/\1/p')
    [ -n "$sink" ] || continue
    printf '%s\t%s\n' "$id" "$sink"
  done
}

verify_destroy_sink() {
  name=$1
  mid=$2
  case "$name" in
    Loom-*) ;;
    *) return 1 ;;
  esac
  [ -n "$mid" ] || return 1
  found=0
  while IFS="$(printf '\t')" read -r id sink || [ -n "$id" ]; do
    [ -n "$id" ] || continue
    if [ "$id" = "$mid" ] && [ "$sink" = "$name" ]; then
      found=1
      break
    fi
  done <<EOF
$(iter_loom_modules)
EOF
  [ "$found" -eq 1 ]
}

run_op() {
  op=$1
  shift || true
  case "$op" in
    dump|--dump)
      need pw-dump
      pw-dump
      ;;
    move)
      stream=${1:-}
      target=${2:-}
      [ -n "$stream" ] && [ -n "$target" ] || { echo "usage: move STREAM TARGET" >&2; exit 2; }
      if command -v wpctl >/dev/null 2>&1 && wpctl set-target "$stream" "$target"; then
        return 0
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
    spawnSink|spawn-sink)
      need pactl
      sink=$(sanitize_sink_name "${1:-Mix}")
      pactl load-module module-null-sink "sink_name=$sink" "sink_properties=device.description=$sink"
      ;;
    destroySink|destroy-module)
      mid=${1:-}
      name=${2:-}
      [ -n "$mid" ] && [ -n "$name" ] || { echo "usage: destroy-module ID Loom-name" >&2; exit 2; }
      verify_destroy_sink "$name" "$mid" || { echo "loom-cli.sh: refused destroy of $name/$mid" >&2; exit 1; }
      if [ "${LOOM_DRY:-}" = 1 ]; then
        return 0
      fi
      need pactl
      pactl unload-module "$mid"
      ;;
    cleanupOrphans)
      destroy=${1:-false}
      adopted=
      removed=
      while IFS="$(printf '\t')" read -r id sink || [ -n "$id" ]; do
        [ -n "$id" ] || continue
        if [ "$destroy" = "true" ]; then
          if [ "${LOOM_DRY:-}" != 1 ]; then
            need pactl
            pactl unload-module "$id"
          fi
          if [ -n "$removed" ]; then
            removed=$removed,
          fi
          removed=$removed'{"name":"'"$sink"'","moduleId":'"$id"'}'
        else
          if [ -n "$adopted" ]; then
            adopted=$adopted,
          fi
          adopted=$adopted'{"name":"'"$sink"'","moduleId":'"$id"'}'
        fi
      done <<EOF
$(iter_loom_modules)
EOF
      printf '%s\n' "${destroy}|${adopted}|${removed}"
      ;;
    list-loom-sinks)
      iter_loom_modules
      ;;
    sanitize)
      sanitize_sink_name "${1:-}"
      ;;
    *)
      echo "loom-cli.sh: unknown command $op" >&2
      exit 2
      ;;
  esac
}

emit_ok() {
  id=$1
  op=$2
  extra=${3:-}
  if [ -n "$extra" ]; then
    printf '{"t":"ok","id":"%s","op":"%s",%s}\n' "$id" "$op" "$extra"
  else
    printf '{"t":"ok","id":"%s","op":"%s"}\n' "$id" "$op"
  fi
}

emit_err() {
  printf '{"t":"err","id":"%s","op":"%s","err":"%s","msg":"%s"}\n' "$1" "$2" "$3" "$4"
}

run_cmd_json() {
  json=$1
  op=$(json_field op "$json")
  id=$(json_field id "$json")
  [ -n "$op" ] || { emit_err "$id" "" "parse" "missing op"; return 1; }
  case "$op" in
    dump)
      run_op dump
      ;;
    move)
      if out=$(run_op move "$(json_num stream "$json")" "$(json_num target "$json")"); then
        emit_ok "$id" "$op"
      else
        emit_err "$id" "$op" "exec" "move failed"
      fi
      ;;
    link)
      if run_op link "$(json_num from "$json")" "$(json_num to "$json")"; then
        emit_ok "$id" "$op"
      else
        emit_err "$id" "$op" "exec" "link failed"
      fi
      ;;
    unlink)
      if run_op unlink "$(json_num from "$json")" "$(json_num to "$json")"; then
        emit_ok "$id" "$op"
      else
        emit_err "$id" "$op" "exec" "unlink failed"
      fi
      ;;
    volume)
      if run_op volume "$(json_num node "$json")" "$(json_num vol "$json")"; then
        emit_ok "$id" "$op"
      else
        emit_err "$id" "$op" "exec" "volume failed"
      fi
      ;;
    mute|muteSubgraph)
      mute=$(json_bool mute "$json")
      [ "$mute" = "false" ] && flag=0 || flag=1
      ids=$(json_id_list "$json")
      if [ -z "$ids" ]; then
        ids=$(json_num node "$json")
      fi
      ok=1
      for nid in $ids; do
        [ -n "$nid" ] || continue
        if ! run_op mute "$nid" "$flag"; then
          ok=0
          break
        fi
      done
      if [ "$ok" -eq 1 ] && [ -n "$ids" ]; then
        emit_ok "$id" "$op"
      else
        emit_err "$id" "$op" "exec" "mute failed"
      fi
      ;;
    spawnSink)
      name=$(json_field name "$json")
      sink=$(sanitize_sink_name "$name")
      if mid=$(run_op spawnSink "$sink"); then
        mid=$(printf '%s' "$mid" | tr -d '[:space:]')
        emit_ok "$id" "$op" "\"name\":\"$sink\",\"moduleId\":${mid:-null}"
      else
        emit_err "$id" "$op" "exec" "pactl failed"
      fi
      ;;
    destroySink)
      dname=$(json_field name "$json")
      dmid=$(json_num moduleId "$json")
      if ! verify_destroy_sink "$dname" "$dmid"; then
        emit_err "$id" "$op" "denied" "not a verified Loom null-sink"
      elif run_op destroy-module "$dmid" "$dname"; then
        emit_ok "$id" "$op"
      else
        emit_err "$id" "$op" "exec" "unload failed"
      fi
      ;;
    cleanupOrphans)
      destroy=$(json_bool destroy "$json")
      [ "$destroy" = "true" ] || destroy=false
      if plan=$(run_op cleanupOrphans "$destroy"); then
        adopted=$(printf '%s' "$plan" | awk -F'|' '{print $2}')
        removed=$(printf '%s' "$plan" | awk -F'|' '{print $3}')
        emit_ok "$id" "$op" "\"destroy\":$destroy,\"adopted\":[${adopted}],\"removed\":[${removed}]"
      else
        emit_err "$id" "$op" "exec" "pactl failed"
      fi
      ;;
    *)
      emit_err "$id" "$op" "unsupported" "$op"
      ;;
  esac
}

cmd=${1:-}
[ -n "$cmd" ] || { echo "loom-cli.sh: missing command" >&2; exit 2; }
shift || true

case "$cmd" in
  --dump) run_op dump ;;
  --cmd)
    json=${1:-}
    [ -n "$json" ] || { echo "usage: --cmd JSON" >&2; exit 2; }
    run_cmd_json "$json"
    ;;
  --cli)
    echo "loom-cli.sh: not a daemon; QML should use in-process pw-dump" >&2
    exit 2
    ;;
  --help|-h)
    sed -n '2,14p' "$0"
    ;;
  *)
    run_op "$cmd" "$@"
    ;;
esac
