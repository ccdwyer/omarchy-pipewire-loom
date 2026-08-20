# PipeWire Loom NDJSON schema

Version 1. Both backends (`loomd` and the CLI poller) emit and accept this
schema. QML never talks PipeWire; it only speaks these lines.

Lines are JSON objects, one per line, UTF-8, no framing. Unknown `t` / `op`
values are ignored (forward-compatible). Empty lines are ignored.

## Events (backend → UI)

Every event has `t`. Snapshots and diffs carry `gen` (uint, monotonic). A
generation bump means "throw away your graph and take this".

### `hello`

```json
{"t":"hello","backend":"cli","version":1,"compat":false}
```

- `backend`: `"cli"` or `"loomd"`
- `compat`: `true` when the CLI path is active (missing/crashed helper)

### `snapshot`

Full replace. Used on connect, on storm, and whenever the backend cannot
reconcile a diff.

```json
{
  "t": "snapshot",
  "gen": 4,
  "nodes": [ { "id": 42, "...": "..." } ],
  "ports": [ { "id": 80, "...": "..." } ],
  "links": [ { "id": 200, "...": "..." } ],
  "defaults": { "sink": 55, "source": 12, "sinkName": "alsa_output...", "sourceName": "alsa_input..." },
  "graph": { "quantum": 1024, "rate": 48000, "latencyMs": 21.333 }
}
```

### `diff`

Incremental. All arrays optional. Ids are PipeWire global ids (ints).

```json
{
  "t": "diff",
  "gen": 4,
  "addNodes": [],
  "remNodes": [99],
  "updNodes": [],
  "addPorts": [],
  "remPorts": [],
  "updPorts": [],
  "addLinks": [],
  "remLinks": [200],
  "updLinks": [],
  "defaults": { "sink": 55 }
}
```

If `gen` does not match the UI's current generation, the UI requests a snapshot
(`{"op":"dump"}`) and ignores the diff.

### `storm`

Warning that a snapshot follows, replacing diffs. Same `gen` as the snapshot
that comes next (or `gen+1` if the snapshot bumps).

```json
{"t":"storm","gen":5,"n":18,"windowMs":100}
```

### `ok` / `err`

Command acknowledgements. `id` echoes the command id.

```json
{"t":"ok","id":"a1b2","op":"move"}
{"t":"ok","id":"a1b2","op":"spawnSink","name":"Loom-Mix","moduleId":12}
{"t":"ok","id":"a1b2","op":"cleanupOrphans","destroy":false,"adopted":[{"name":"Loom-Mix","moduleId":12}],"removed":[]}
{"t":"err","id":"a1b2","op":"move","err":"gone"}
```

`err` values: `gone`, `ambiguous`, `denied`, `unsupported`, `parse`, `exec`.

### `toast`

Non-fatal UI notice (node vanished mid-drag, orphan cleanup, spawn failed).

```json
{"t":"toast","level":"warn","msg":"stream gone"}
```

## Objects

### Node

| field | type | notes |
|---|---|---|
| `id` | int | PipeWire global id |
| `serial` | int | `object.serial` if present, else `id` |
| `name` | string | `node.name` |
| `nick` | string | nick, description, or application.name |
| `app` | string | `application.name` (empty for devices) |
| `mediaClass` | string | e.g. `Stream/Output/Audio`, `Audio/Sink` |
| `kind` | string | `source` \| `filter` \| `sink` \| `midi` \| `video` \| `other` |
| `state` | string | `running` \| `idle` \| `suspended` \| `error` \| `unknown` |
| `mute` | bool | |
| `volume` | number | 0..1 linear |
| `isDefault` | bool | default sink or source |
| `isCapture` | bool | capture stream or hardware source in a capturing role |
| `isLoom` | bool | `node.name` / nick starts with `Loom-` |
| `channels` | string[] | channel names, e.g. `["FL","FR"]` |
| `identity` | string | `app\|mediaClass\|index-within-app` for position persistence |
| `moduleId` | int? | pactl module id, Loom sinks only |

### Port

| field | type | notes |
|---|---|---|
| `id` | int | |
| `node` | int | owner node id |
| `name` | string | `port.name` |
| `dir` | string | `out` \| `in` |
| `channel` | string | `audio.channel` or derived (`FL`, `FR`, `MONO`, `AUX0`, …) |
| `monitor` | bool | |
| `physical` | bool | |

### Link

| field | type | notes |
|---|---|---|
| `id` | int | |
| `from` | int | output port id |
| `to` | int | input port id |
| `fromNode` | int | |
| `toNode` | int | |
| `kind` | string | `route` (session-manager / target.object) or `raw` (explicit `pw-link`) |
| `live` | bool | source stream `state === "running"` |
| `muted` | bool | either endpoint muted |
| `latencyMs` | number\|null | only when this route differs from graph default |

## Commands (UI → backend)

Every command has `op` and `id` (string, UI-generated).

```json
{"op":"dump","id":"1"}
{"op":"move","id":"2","stream":77,"target":55,"targetSerial":9901,"targetName":"alsa_output.hw"}
{"op":"link","id":"3","from":80,"to":91}
{"op":"link","id":"4","fromNode":77,"toNode":55}
{"op":"unlink","id":"5","link":200}
{"op":"unlink","id":"6","from":80,"to":91}
{"op":"volume","id":"7","node":77,"vol":0.8}
{"op":"mute","id":"8","node":77,"mute":true}
{"op":"muteSubgraph","id":"9","node":77,"mute":true}
{"op":"spawnSink","id":"10","name":"Recording"}
{"op":"destroySink","id":"11","name":"Loom-Recording","moduleId":12}
{"op":"cleanupOrphans","id":"12","destroy":false}
```

### Semantics

- **`move`**: `pw-metadata -n default <stream-id> target.object <serial-or-name>`.
  `targetSerial` (preferred) or `targetName` — never the target's transient
  global id. Sticky verb. Never a raw `pw-link`.
- **`link` with ports**: explicit `pw-link`. Drawn dashed; policy-fragile.
- **`link` with nodes**: auto-map channels. If the map is ambiguous
  (mismatched counts other than mono fan-out), return `{"err":"ambiguous"}`
  and do not link anything.
- **`mute` / `muteSubgraph`**: `wpctl set-mute <id> 1|0`. Subgraph is BFS over
  current links; mute is applied to **stream** nodes only.
- **`spawnSink`**: `pactl load-module module-null-sink sink_name=Loom-<name>`.
  Never touches a device whose name does not start with `Loom-`. Success
  includes `name` and `moduleId` so the UI can persist teardown.
- **`destroySink`**: requires `name` starting with `Loom-` **and** a
  `moduleId` that currently belongs to that exact live `module-null-sink`.
  Anything else returns `denied`.
- **`cleanupOrphans`**: `destroy:false` (startup) lists live `Loom-*`
  null-sink modules as `adopted`. `destroy:true` unloads only those modules
  and returns them as `removed`.
- Stale ids: `{"err":"gone"}`.

## Storm rule

Coalesce at 30 Hz. If more than 10 events arrive in 100 ms, emit `storm` then
a `snapshot` with a bumped `gen`. The UI replaces the model wholesale.

## Golden fixtures

See `tests/fixtures/`:

- `snapshot-simple.ndjson`
- `storm.ndjson`
- `pwdump-simple.json` / `pwdump-chrome-mess.json` / `pwdump-bluetooth.json`
- `pwdump-hotplug-after.json`
