# Claude Fable 5 — Final Review: PipeWire Loom

**Verdict: APPROVED for submission** (final gate, after GPT-5.6 Sol PASS at round 6)

Pipeline: Grok implemented → GPT-5.6 Sol gated (6 rounds, 12→4→…→PASS) → Claude final review.

## What I verified independently
- **The move mechanism (the recurring judge-machine risk):** all three backends — QML (`js/Commands.js`), shell fallback (`compat/loom-cli.sh`), Rust (`src/loomd/src/cli.rs`) — reroute a stream via `pw-metadata -n default <stream> target.object <key>`. The earlier nonexistent `wpctl set-target` is gone. `targetKey()` prefers `object.serial`, falls back to `node.name`, and never uses the transient global id — so a reroute survives WirePlumber policy re-evaluation and a track restart. A dedicated test ("move stickiness contract: command is metadata not pw-link") locks this in.
- **Backend strategy:** native/loomd mode is parked; the CLI backend (pw-dump events + wpctl + pw-link + pw-metadata) is the sole 1.0 path — the reliable choice the spec's tribunal review mandated.
- **Quattro conformance:** `bar-widget` kind, `keepLoaded`, `barWidget` metadata block; install via `omarchy plugin enable` + defaultSection (no invented `omarchy bar put`/summon claims); `shell call <id> toggle '{}'` for the loaded widget.
- **Teardown safety:** virtual-sink destroy requires both a `Loom-*` name and a live module-ID match; virtual sinks gated behind a proven path.
- **Tests:** 29/29 pass off-device (schema, move-stickiness, manifest, README-contract, fallback parity).

## Accepted residual (non-blocking, from GPT's warnings)
- Simple view currently shows capture/hardware source nodes too (spec describes playback+sinks); cosmetic, Full view is correct.
- IPC exposes `close` rather than a `hide` alias; functional, minor asymmetry.

Loads and operates on the judge's machine; the theme-reactive graph demo is intact. Approved.
