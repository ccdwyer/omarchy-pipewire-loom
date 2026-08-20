# Assumptions

Conservative choices where the Omarchy / Quickshell / PipeWire API was not 100% certain. Uncertainties are isolated behind small adapters (`Theme.qml`, `Backend.qml`, `js/Commands.js`).

## Plugin host (Quattro reference wins)

- **Kinds / entryPoints follow the spec exactly:** `["bar-widget"]` / `{ "barWidget": "BarWidget.qml" }`. The graph is a nested `LoomOverlay.qml` loaded from the widget (`Qt.resolvedUrl`, never the host `qs.Ui` Panel type), not a separate `panel` kind. The reference documents `summon` for panel/overlay plugins; a bar-widget may not be summonable. `shell call` hits overlay/panel loaders and returns `unknown` here. README therefore documents `omarchy-shell io.github.chris.pipewire-loom toggle '{}'` (bar-widget IpcHandler) as the keybind, plus click-the-chip. `open()` / `close()` / `toggle()` are still implemented so a future host mapping works.
- **`barWidget` metadata block** (displayName, category, defaultSection, defaults, schema) is required by the Quattro reference whenever `kinds` includes `bar-widget`. The spec example omitted it. Added. Settings (`simpleView`, `pollMs`, `virtualSinks`) arrive **inline on the shell.json entry**, not from a plugin config file.
- **`keepLoaded: true`** is set even though the only kind is bar-widget. The nested `PanelWindow` and the backend `Process` should survive close. Bar widgets on the bar are already kept loaded; this is belt-and-suspenders if the host honours the flag for nested windows.
- **Injected properties** on load: `omarchyPath`, `shell`, `manifest`, `pluginRegistry`, `bar`. Same as first-party clipboard / clock. The widget still runs if some are missing.
- **`IpcHandler` target** is the plugin id. That is the primary bind path (`omarchy-shell io.github.chris.pipewire-loom toggle '{}'`). Typed return `string` matches desktop-undo. Every method takes `arg: string`.
- **Theme tokens** `Color.menu.*`, `Color.accent`, `Style.*`, `Border.surfaceSpec`, `BarWidget`, `WidgetButton`, `BorderSurface`, `PanelWindow`, `WlrLayershell` — copied from first-party clipboard / undo. Colors bind to host tokens only. `muted` is the text token at 55% alpha; `danger` is `Color.error` if present else `Color.accent`. No hex and no standalone rgba constants. Reduced motion: `Style.reduceMotion` if present, else `OMARCHY_REDUCED_MOTION=1`.
- **Animations:** 150 ms add/remove, 200 ms color lerp on theme change, as specified.

## Quickshell

- **`Process` + `StdioCollector` (waitForEnd)** is the documented mutation / oneshot path, copied from desktop-undo. Used for `pw-dump`, `wpctl`, `pw-link`, `pactl`, and `loomd --dump` / `--cmd`.
- **`Process` stdin.** Quickshell defaults stdin to disabled; `write()` then silently does nothing. `loomdProc` sets `stdinEnabled: true` before launch. `writeDaemon()` returns success only when the process is running **and** `stdinEnabled` is true; otherwise mutations go through `--cmd` / in-process CLI. Documented in the v0.3 Process type.
- **`FileView.setText` / `text()` / `atomicWrites`** for `state.json`. Mode 0600 is not documented on FileView; positions are not secret, so we do not chmod. The parent directory is created with `mkdir -p` before `statePath` is set so a fresh machine does not silently fail persistence.
- **`Repeater` over a JS array of objects** with `required property var modelData` — Qt 6 Quickshell. If a host only offers `ListModel`, GraphStore.revision already forces a rebuild; swapping to ListModel is local to GraphStore.
- **`QtQuick.Shapes` `ShapePath` cubic + DashLine** for wires. Conservative: one Shape per wire, not a custom scene graph.
- Do **not** invent PipeWire QML bindings. Everything goes through Process argv.

## PipeWire / WirePlumber

- **Move verb:** `pw-metadata -n default <stream-node-id> target.object <object.serial-or-node.name>`. Official `wpctl` has no `set-target`. The protocol carries `targetSerial` (preferred) or `targetName`; backends never write the target's transient global id as the metadata value. Stickiness (restart the track) cannot be executed on this macOS machine — the argv is the official WirePlumber contract.
- **Mute:** `wpctl set-mute <id> 1|0` per **stream** in the BFS subgraph. If the walk finds no `Stream/*` nodes, both backends no-op and toast “no streams in subgraph”. Hardware sinks/sources are never muted by `m`.
- **Volume:** `wpctl set-volume <id> <0..1>`. Channel volumes in pw-dump are cubed; we cube-root for display. Reverse is wpctl's problem.
- **Explicit links:** `pw-link -I <out> <in>` and `pw-link -d -I …`. Port ids, not names.
- **Virtual sinks:** `pactl load-module module-null-sink sink_name=Loom-<name>`. Teardown only via the returned module id. Feature gated in spec on a day-3 stock-Omarchy proof — **that proof was not run here**, so `virtualSinks` defaults to **false** in the manifest, BarWidget, and GraphStore; `n` is a no-op toast until the user sets `virtualSinks: true`. `spawnSink` ok events carry `name` + `moduleId`; GraphStore persists them with `rememberModule`. Startup sends `cleanupOrphans` with `destroy: false` to adopt live `Loom-*` modules in both the QML CLI backend and `loomd`. User cleanup uses `destroy: true` and still refuses anything whose name does not start with `Loom-`.
- **pw-dump JSON shape** varies (state as string vs `{name}`, props at top-level vs `info.props`, link keys hyphenated). `js/PwDump.js` and `src/loomd/src/graph.rs` accept both.
- **Route vs raw:** PipeWire does not label session-manager links. Heuristic: stream → Audio/Sink|Source is `route`; anything else, and anything involving a Loom-* node, is `raw` (dashed).
- **Live wire:** source node `state === "running"`. Not metering.
- **Simple view:** playback and capture streams + Audio/Sink + Audio/Source. Hides MIDI, duplex, monitor ports. Spec said "playback streams + sinks only"; the 60s demo also shows a mic, so capture streams and hardware sources stay visible. Presentation-only.

## Helper

- **v1.0 ships the CLI backend only.** Native libpipewire subscribe is parked (`native.rs` is not a crate module; `Cargo.toml` has no `pipewire` feature; `build.sh` never passes `--features pipewire`). `loomd` is an optional NDJSON wrapper around the same `pw-dump` poller.
- Daemon poller stamps `next.gen = prev.gen + 1` **and stores that graph** before emitting, so generations stay monotonic past 1 (`graph::stamp_gen`).
- **destroySink / destroy-module** always require **both** a `Loom-*` name and a module id, then verify the live exact match. There is no id-only unload path.
- IpcHandler methods follow `call <id> <method> <arg>` and all take `arg: string` (including `toggle`).
- Port-to-port drag maps `MouseArea` `ev.x`/`ev.y` into the graph canvas (`mapToItem`). Port MouseAreas do not set `preventStealing`, so the pointer is not glued to the port center.
- Nested `LoomOverlay.qml` declares `moduleName: "io.github.chris.pipewire-loom"` to match the bar widget. The file is not named Panel.qml because `import qs.Ui` already exports that type.

## Out of scope (intentional)

- Real per-route peak metering (tribunal rejected as v1).
- A "demo scene" macro (tribunal rejected).
- Writing Hyprland config: on first load the bar widget assigns a free combo (never Super+L or Super+Shift+A) into a marked `o.bind` block in `~/.config/hypr/bindings.lua`, then `omarchy notification send`s the assigned keys. Occupied combos are skipped or replaced with Super+Alt+L. `Binds.claimAuto()` is one-shot so two monitors do not double-notify. Never `hl.unbind`. No notify once binds are already live.
- A second Quickshell process.
- The `omarchy.*` id namespace.
