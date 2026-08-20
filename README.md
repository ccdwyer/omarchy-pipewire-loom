# PipeWire Loom

A theme-native PipeWire graph inside Omarchy. Drag a browser onto your headset, mute a subgraph, watch live routes light up. Helvum, if Omarchy had designed it. Virtual `Loom-*` sinks exist behind `virtualSinks: true` and are off by default (stock-Omarchy proof not run).

This is an Omarchy shell **bar-widget**. The graph is a nested panel, not a second Quickshell process. The v1.0 backend is stock `pw-dump` / `wpctl` / `pw-link` / `pactl`. Optional `loomd` is the same CLI poller speaking NDJSON — not a native PipeWire subscriber.

## Install

```sh
omarchy plugin add <git-url> --enable
```

Then, on the machine, build the helper (optional — the widget works without it):

```sh
~/.config/omarchy/plugins/io.github.chris.pipewire-loom/build.sh
```

If you added without `--enable`, enable it so the chip lands in `barWidget.defaultSection` (`right`):

```sh
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.chris.pipewire-loom
```

The widget can then be moved with `omarchy bar move`.

Saving any file under the plugin directory hot-reloads it.

## Usage

Click the bar chip (default sink + live stream count; red badge if a capture node is running). The graph opens as a large overlay.

| Input | Action |
|---|---|
| Drag a playback stream onto a sink | **Move** — `pw-metadata -n default <stream-id> target.object <sink-serial-or-name>`. Intended to survive a track restart; that live check needs PipeWire and was not run on this machine. |
| Drag a port onto a port or node | **Explicit `pw-link`**. Drawn dashed; the session manager may re-evaluate it. Drop on a node auto-maps channels. Stereo→5.1 and other mismatched counts are refused, ports highlighted. |
| `h j k l` / arrows | Walk nodes |
| `Tab` | Simple view (streams + devices) ↔ full graph |
| `Enter` | Start / complete an explicit link from the selection |
| `Esc` | Cancel a drag, or close |
| `m` | Mute / unmute the subgraph (`wpctl set-mute` on stream nodes) |
| `n` | Spawn `Loom-<name>` null sink — **off by default** until `virtualSinks: true` (stock-Omarchy proof not run) |
| `x` / Backspace | Unlink the selection; destroy a selected Loom sink |
| `+` / `-` | Volume on the selection |
| `?` | Key overlay |
| Right-click the chip | Toggle simple / full view without opening the panel |

The plugin does **not** write `hyprland.conf`. Bind a key yourself:

```
bind = SUPER SHIFT, A, exec, omarchy-shell shell call io.github.chris.pipewire-loom toggle '{}'
```

This plugin is a bar-widget only — do not `shell summon` it. Click the chip, or:

```
omarchy-shell shell call io.github.chris.pipewire-loom toggle '{}'
```

## Settings

Inline on the `shell.json` bar entry. There is no plugin config file.

```json
{
  "id": "io.github.chris.pipewire-loom",
  "simpleView": true,
  "pollMs": 1000,
  "virtualSinks": false
}
```

User-dragged node positions persist separately to `~/.local/state/pipewire-loom/state.json`, keyed by `application.name|media.class|index` — not by `node.name`, which Chrome/Electron recycle.

## Backends

v1.0 ships **one** backend: the CLI path (`pw-dump` for state, `wpctl` / `pw-link` / `pactl` for mutations). Native libpipewire subscribe is parked.

1. **In-process CLI (guaranteed).** QML polls `pw-dump` and mutates via the stock tools. This is the product.
2. **`bin/loomd --cli` (optional).** Same CLI poller, speaking the committed NDJSON schema on stdin/stdout. Missing or crashing helper drops back to (1) with a compat badge.
3. **`compat/loom-cli.sh`** — POSIX one-shot verbs (`--dump` / `--cmd`) for the same tools. Not a daemon.

Day-1 gate (backend alone, no UI):

```sh
compat/loom-cli.sh move <stream-id> <sink-object.serial-or-node.name>
# On a PipeWire machine: restart the track; the route should stick.
```

## Honest limitations

- **Wires light up when the source stream is `running`.** This is not per-route peak metering. Metering was a gated stretch and is not in 1.0.
- **Raw `pw-link` patches are policy-fragile.** Only the move verb (target metadata) is the sticky path. Dashed wires are honest about that.
- **Channel-map guard refuses ambiguous maps** (stereo→5.1, mismatched counts other than mono fan-out). It will not silently link one channel.
- **Virtual sinks are off by default** (`virtualSinks: false`). The spawn path is `pactl` null-sink with a `Loom-` prefix and will not unload anything else. The day-3 stock-Omarchy proof was not run on this machine; set `virtualSinks: true` in the `shell.json` entry only after that proof is green. Teardown uses the `moduleId` returned on `spawnSink` success and persisted via `rememberModule`. Startup adopts live `Loom-*` modules; `cleanupOrphans` unloads only those.
- **Latency labels** appear per-route only when a route's quantum differs from the graph default. Same-number-on-every-wire is noise and is omitted.
- **Simple view is presentation-only.** MIDI, monitor ports, and virtual-duplex nodes are hidden; they still exist in PipeWire.
- **No native PipeWire subscribe in 1.0.** `src/loomd/src/native.rs` is parked and not compiled. `build.sh` builds the CLI poller only.
- **Keybinds are yours to add.**
- **No second Quickshell process, no omarchy.* id.**

## Tests (off-device)

```sh
node tests/run.js
sh tests/cli-fallback.test.sh
# if cargo is present:
cargo test --manifest-path src/loomd/Cargo.toml
```
