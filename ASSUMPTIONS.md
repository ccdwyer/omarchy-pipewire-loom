# Assumptions

Conservative choices where the Omarchy / Quickshell / PipeWire API was not 100% certain. Uncertainties are isolated behind small adapters (`Theme.qml`, `Backend.qml`, `js/Commands.js`).

## Plugin host (Quattro reference wins)

- **Kinds / entryPoints follow the spec exactly:** `["bar-widget"]` / `{ "barWidget": "BarWidget.qml" }`. The graph is a nested `Panel.qml` loaded from the widget, not a separate `panel` kind. The reference documents `summon` for panel/overlay plugins; a bar-widget may not be summonable. README therefore documents `omarchy-shell shell call io.github.chris.pipewire-loom toggle` as the keybind, plus click-the-chip. `open()` / `close()` / `toggle()` are still implemented so a future host mapping works.
- **`barWidget` metadata block** (displayName, category, defaultSection, defaults, schema) is required by the Quattro reference whenever `kinds` includes `bar-widget`. The spec example omitted it. Added. Settings (`simpleView`, `pollMs`, `virtualSinks`) arrive **inline on the shell.json entry**, not from a plugin config file.
- **`keepLoaded: true`** is set even though the only kind is bar-widget. The nested `PanelWindow` and the backend `Process` should survive close. Bar widgets on the bar are already kept loaded; this is belt-and-suspenders if the host honours the flag for nested windows.
- **Injected properties** on load: `omarchyPath`, `shell`, `manifest`, `pluginRegistry`, `bar`. Same as first-party clipboard / clock. The widget still runs if some are missing.
- **`IpcHandler` target** is the plugin id. Extra surface; `shell call` is the primary path. Typed return `string` matches desktop-undo.
- **Theme tokens** `Color.menu.*`, `Color.accent`, `Style.*`, `Border.surfaceSpec`, `BarWidget`, `WidgetButton`, `BorderSurface`, `PanelWindow`, `WlrLayershell` — copied from first-party clipboard / undo and bound **directly** in `Theme.qml` so a theme switch updates live (200 ms `ColorAnimation`). A JS fallback wrapper would hide `Color.*` from QML's dependency tracker. Capture badge uses a fixed red (`Qt.rgba(0.86, 0.22, 0.22, 1)`) because no first-party danger token was confirmed. Reduced motion: `Style.reduceMotion` if present, else `OMARCHY_REDUCED_MOTION=1`.
- **Animations:** 150 ms add/remove, 200 ms color lerp on theme change, as specified.

## Quickshell

- **`Process` + `StdioCollector` (waitForEnd)** is the documented mutation / oneshot path, copied from desktop-undo. Used for `pw-dump`, `wpctl`, `pw-link`, `pactl`, and `loomd --dump` / `--cmd`.
- **`Process` stdin** (`stdinEnabled`, `write()`) is **not** clearly documented. Daemon mode tries `write()` inside try/catch and falls back to `--cmd` oneshots if it throws or is missing. `SplitParser.onRead` is used for daemon stdout; if that type is absent the host will fail to load `Backend.qml` — in that case the user still has the CLI path only after commenting the daemon `Process` out. Recorded so a later spike can swap in a Unix socket if needed.
- **`FileView.setText` / `text()` / `atomicWrites`** for `state.json`. Mode 0600 is not documented on FileView; positions are not secret, so we do not chmod.
- **`Repeater` over a JS array of objects** with `required property var modelData` — Qt 6 Quickshell. If a host only offers `ListModel`, GraphStore.revision already forces a rebuild; swapping to ListModel is local to GraphStore.
- **`QtQuick.Shapes` `ShapePath` cubic + DashLine** for wires. Conservative: one Shape per wire, not a custom scene graph.
- Do **not** invent PipeWire QML bindings. Everything goes through Process argv.

## PipeWire / WirePlumber

- **Move verb:** `wpctl set-target <stream> <sink>` first, then `pw-metadata <stream> target.object <sink>`. Spec says target metadata the way wpctl does. `wpctl set-target` exists on WirePlumber 0.5+; the metadata fallback covers 0.4. Never `pw-link` for move. Stickiness (restart the track) cannot be asserted on this macOS machine.
- **Mute:** `wpctl set-mute <id> 1|0` per stream in the BFS subgraph. Not SPA_PROP_mute param writes.
- **Volume:** `wpctl set-volume <id> <0..1>`. Channel volumes in pw-dump are cubed; we cube-root for display. Reverse is wpctl's problem.
- **Explicit links:** `pw-link -I <out> <in>` and `pw-link -d -I …`. Port ids, not names.
- **Virtual sinks:** `pactl load-module module-null-sink sink_name=Loom-<name>`. Teardown only via the returned module id. Feature gated in spec on a day-3 stock-Omarchy proof — **that proof was not run here**. The verb ships; `virtualSinks: false` disables it. Orphan cleanup refuses anything whose name does not start with `Loom-`.
- **pw-dump JSON shape** varies (state as string vs `{name}`, props at top-level vs `info.props`, link keys hyphenated). `js/PwDump.js` and `src/loomd/src/graph.rs` accept both.
- **Route vs raw:** PipeWire does not label session-manager links. Heuristic: stream → Audio/Sink|Source is `route`; anything else, and anything involving a Loom-* node, is `raw` (dashed).
- **Live wire:** source node `state === "running"`. Not metering.
- **Simple view:** playback and capture streams + Audio/Sink + Audio/Source. Hides MIDI, duplex, monitor ports. Spec said "playback streams + sinks only"; the 60s demo also shows a mic, so capture streams and hardware sources stay visible. Presentation-only.

## Helper

- Spec language is Rust, dynamically linked against system libpipewire. The `pipewire` crate API is feature-gated (`--features pipewire`) and isolated in `src/loomd/src/native.rs`. `build.sh` tries that feature, then CLI-only, then wraps `compat/loom-cli.sh`. QML must pass the full suite with `loomd` deleted.
- Native mode, if it compiles, subscribes to the registry and then re-parses via `pw-dump` rather than hand-walking SPA params (those APIs drift). Mutations still go through wpctl.
- Default `loomd` (no flags): try native when built with the feature, else CLI poller. `--cli` forces the poller.

## Out of scope (intentional)

- Real per-route peak metering (tribunal rejected as v1).
- A "demo scene" macro (tribunal rejected).
- Writing Hyprland config.
- A second Quickshell process.
- The `omarchy.*` id namespace.
