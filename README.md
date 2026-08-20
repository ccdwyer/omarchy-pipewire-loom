# PipeWire Loom

A theme-native PipeWire graph inside Omarchy. Drag a browser onto your headset, spawn a virtual sink, mute a subgraph, watch live routes light up. Helvum, if Omarchy had designed it.

This is an Omarchy shell **bar-widget**. The graph is a nested panel, not a second Quickshell process. The guaranteed backend is stock `pw-dump` / `wpctl` / `pw-link` / `pactl`. `loomd` is a performance upgrade.

## Install

```sh
omarchy plugin add <git-url> --enable
```

Then, on the machine, build the helper (optional — the widget works without it):

```sh
~/.config/omarchy/plugins/io.github.chris.pipewire-loom/build.sh
```

Put the chip on the bar if `--enable` did not:

```sh
omarchy bar put io.github.chris.pipewire-loom --section right
```

Reload plugins if the shell was already running:

```sh
omarchy-shell shell rescanPlugins
```

Saving any file under the plugin directory hot-reloads it.

## Usage

Click the bar chip (default sink + live stream count; red badge if a capture node is running). The graph opens as a large overlay.

| Input | Action |
|---|---|
| Drag a playback stream onto a sink | **Move** — WirePlumber `target.object` / `wpctl set-target`. Intended to survive a track restart; that stickiness test has not been run on this machine. |
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

`omarchy-shell shell summon io.github.chris.pipewire-loom '{}'` may also work if the host maps summon onto the widget's `open()`. The documented path is `shell call … toggle '{}'`.

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

1. **`bin/loomd`** — Rust helper. Built with `build.sh`. Dynamically linked against system `libpipewire-0.3` when that crate feature compiles; otherwise a `pw-dump` poller that still speaks the committed NDJSON schema (`schema.md`).
2. **CLI (guaranteed).** If `loomd` is missing, fails to say hello in 2s, or crashes 3×, QML polls `pw-dump` itself and mutates via `wpctl` / `pw-link` / `pactl`. A "compat mode" badge appears. The panel is never blank.
3. **`compat/loom-cli.sh`** — POSIX one-shot verbs for the same tools, used if you want to drive a move from a terminal without the UI.

Day-1 gate (backend alone, no UI):

```sh
compat/loom-cli.sh move <stream-id> <sink-id>
# restart the track; WirePlumber should keep the route
```

## Honest limitations

- **Wires light up when the source stream is `running`.** This is not per-route peak metering. Metering was a gated stretch and is not in 1.0.
- **Raw `pw-link` patches are policy-fragile.** Only the move verb (target metadata) is the sticky path. Dashed wires are honest about that.
- **Channel-map guard refuses ambiguous maps** (stereo→5.1, mismatched counts other than mono fan-out). It will not silently link one channel.
- **Virtual sinks are off by default** (`virtualSinks: false`). The spawn path is `pactl` null-sink with a `Loom-` prefix and will not unload anything else. The day-3 stock-Omarchy proof was not run on this machine; set `virtualSinks: true` in the `shell.json` entry only after that proof is green. Teardown uses the `moduleId` returned on `spawnSink` success and persisted via `rememberModule`. Startup adopts live `Loom-*` modules; `cleanupOrphans` unloads only those.
- **Latency labels** appear per-route only when a route's quantum differs from the graph default. Same-number-on-every-wire is noise and is omitted.
- **Simple view is presentation-only.** MIDI, monitor ports, and virtual-duplex nodes are hidden; they still exist in PipeWire.
- **`loomd` native subscribe** is optional. The product is the CLI path. A macOS checkout cannot link libpipewire; `build.sh` then produces a CLI-only binary, or installs nothing and QML stays on in-process `pw-dump`. `compat/loom-cli.sh` implements `--dump` / `--cmd` oneshots and is **not** installed as `bin/loomd`.
- **Keybinds are yours to add.**
- **No second Quickshell process, no omarchy.* id.**

## Tests (off-device)

```sh
node tests/run.js
sh tests/cli-fallback.test.sh
# if cargo is present:
cargo test --manifest-path src/loomd/Cargo.toml
```
