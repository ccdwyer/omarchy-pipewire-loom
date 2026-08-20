#!/usr/bin/env node
"use strict"

const fs = require("fs")
const path = require("path")
const vm = require("vm")
const assert = require("assert")

const ROOT = path.resolve(__dirname, "..")
const JS = path.join(ROOT, "js")
const FIX = path.join(__dirname, "fixtures")

function loadEngine(file) {
  const src = fs
    .readFileSync(path.join(JS, file), "utf8")
    .replace(/^\.pragma library\s*\n/, "")
  const sandbox = {
    console,
    Date,
    Math,
    JSON,
    String,
    Number,
    Array,
    Object,
    parseInt,
    isFinite,
    isNaN,
    exports: {},
    module: { exports: {} }
  }
  vm.createContext(sandbox)
  vm.runInContext(src, sandbox, { filename: file })
  const exported = {}
  for (const key of Object.keys(sandbox)) {
    if (
      [
        "console",
        "Date",
        "Math",
        "JSON",
        "String",
        "Number",
        "Array",
        "Object",
        "parseInt",
        "isFinite",
        "isNaN",
        "exports",
        "module"
      ].indexOf(key) >= 0
    )
      continue
    exported[key] = sandbox[key]
  }
  return exported
}

const Schema = loadEngine("Schema.js")
const PwDump = loadEngine("PwDump.js")
const Graph = loadEngine("Graph.js")
const ChannelMap = loadEngine("ChannelMap.js")
const Mute = loadEngine("Mute.js")
const Storm = loadEngine("Storm.js")
const Layout = loadEngine("Layout.js")
const SimpleView = loadEngine("SimpleView.js")
const Commands = loadEngine("Commands.js")
const Positions = loadEngine("Positions.js")
const Binds = loadEngine("Binds.js")

let passed = 0
let failed = 0

function test(name, fn) {
  try {
    fn()
    passed += 1
    process.stdout.write("ok  " + name + "\n")
  } catch (err) {
    failed += 1
    process.stderr.write("FAIL " + name + "\n" + (err && err.stack ? err.stack : err) + "\n")
  }
}

function fixture(name) {
  return fs.readFileSync(path.join(FIX, name), "utf8")
}

function jsonFix(name) {
  return JSON.parse(fixture(name))
}

function make60() {
  const items = [
    {
      id: 0,
      type: "PipeWire:Interface:Core",
      info: { props: { "clock.rate": 48000, "clock.quantum": 1024 } }
    },
    {
      id: 55,
      type: "PipeWire:Interface:Node",
      info: {
        state: "running",
        props: {
          "node.name": "speakers",
          "node.nick": "Speakers",
          "media.class": "Audio/Sink",
          "object.serial": 55
        }
      }
    }
  ]
  for (let i = 0; i < 58; i++) {
    const id = 200 + i
    items.push({
      id,
      type: "PipeWire:Interface:Node",
      info: {
        state: i % 3 === 0 ? "running" : "idle",
        props: {
          "node.name": "chrome." + i,
          "application.name": "Google Chrome",
          "media.class": "Stream/Output/Audio",
          "object.serial": id
        }
      }
    })
    items.push({
      id: 1000 + i,
      type: "PipeWire:Interface:Port",
      info: {
        direction: "output",
        props: { "node.id": id, "port.name": "output_FL", "audio.channel": "FL" }
      }
    })
  }
  return items
}

test("schema: parseLine ignores blanks and flags bad json", () => {
  assert.strictEqual(Schema.parseLine("  "), null)
  const bad = Schema.parseLine("{")
  assert.strictEqual(bad.t, "err")
  assert.strictEqual(bad.err, "parse")
})

test("schema: golden snapshot-simple.ndjson", () => {
  const evs = Schema.parseStream(fixture("snapshot-simple.ndjson"))
  assert.strictEqual(evs[0].t, "hello")
  assert.strictEqual(evs[0].backend, "cli")
  assert.strictEqual(evs[1].t, "snapshot")
  assert.strictEqual(evs[1].gen, 1)
  assert.strictEqual(evs[1].nodes.length, 2)
  assert.strictEqual(evs[1].links[0].kind, "route")
  assert.strictEqual(evs[1].links[0].live, true)
})

test("schema: storm fixture replaces generation", () => {
  const evs = Schema.parseStream(fixture("storm.ndjson"))
  let state = Graph.empty()
  for (const ev of evs) {
    const next = Graph.applyEvent(state, ev)
    if (next && !next.mismatch)
      state = next
  }
  assert.strictEqual(state.gen, 2)
  assert.strictEqual(state.nodes.length, 2)
})

test("pwdump: simple session", () => {
  const g = PwDump.parse(fixture("pwdump-simple.json"))
  assert.strictEqual(g.nodes.length, 3)
  const sink = g.nodes.find((n) => n.id === 55)
  assert.ok(sink)
  assert.strictEqual(sink.kind, "sink")
  assert.strictEqual(sink.isDefault, true)
  assert.strictEqual(g.defaults.sink, 55)
  const ff = g.nodes.find((n) => n.id === 77)
  assert.strictEqual(ff.kind, "source")
  assert.strictEqual(ff.state, "running")
  assert.strictEqual(ff.identity, "Firefox|Stream/Output/Audio|0")
  assert.ok(g.ports.some((p) => p.monitor))
  assert.strictEqual(g.links.length, 2)
  assert.strictEqual(g.links[0].kind, "route")
  assert.strictEqual(g.links[0].live, true)
  assert.ok(g.graph.latencyMs > 20 && g.graph.latencyMs < 23)
})

test("pwdump: chrome mess identities are stable per serial order", () => {
  const g = PwDump.parse(fixture("pwdump-chrome-mess.json"))
  const chrome = g.nodes.filter((n) => n.app === "Google Chrome")
  assert.ok(chrome.length >= 3)
  const outs = chrome.filter((n) => n.mediaClass === "Stream/Output/Audio")
  outs.sort((a, b) => a.serial - b.serial)
  assert.strictEqual(outs[0].identity, "Google Chrome|Stream/Output/Audio|0")
  assert.strictEqual(outs[1].identity, "Google Chrome|Stream/Output/Audio|1")
  const midi = g.nodes.find((n) => n.kind === "midi")
  assert.ok(midi)
  const dup = g.nodes.find((n) => n.kind === "filter")
  assert.ok(dup)
})

test("pwdump: bluetooth / hotplug default sink flips", () => {
  const before = PwDump.parse(fixture("pwdump-simple.json"))
  const after = PwDump.parse(fixture("pwdump-hotplug-after.json"))
  assert.strictEqual(before.defaults.sink, 55)
  assert.strictEqual(after.defaults.sink, 66)
  const d = Graph.diff(before, after, before.gen || 0, 10)
  assert.ok(d.event)
  assert.ok(d.n > 0)
})

test("pwdump: 60-node dump applies as one snapshot", () => {
  const g = PwDump.parse(JSON.stringify(make60()))
  assert.ok(g.nodes.length >= 59)
  const ev = Graph.diff(null, g, 0, 10)
  assert.strictEqual(ev.event.t, "snapshot")
  const state = Graph.applyEvent(Graph.empty(), ev.event)
  assert.ok(state.nodes.length >= 59)
})

test("graph: stale generation requests snapshot (mismatch)", () => {
  let state = Graph.applyEvent(Graph.empty(), {
    t: "snapshot",
    gen: 4,
    nodes: [{ id: 1, serial: 1, name: "a", nick: "a", app: "a", mediaClass: "Audio/Sink", kind: "sink", state: "idle", mute: false, volume: 1, isDefault: false, isCapture: false, isLoom: false, channels: [], identity: "a|Audio/Sink|0" }],
    ports: [],
    links: [],
    defaults: {},
    graph: {}
  })
  const r = Graph.applyEvent(state, { t: "diff", gen: 2, remNodes: [1] })
  assert.strictEqual(r.mismatch, true)
})

test("graph: diff add/remove then apply", () => {
  const a = Object.assign(Graph.empty(), PwDump.parse(fixture("pwdump-simple.json")), { gen: 1 })
  const b = Object.assign(Graph.empty(), PwDump.parse(fixture("pwdump-hotplug-after.json")), { gen: 1 })
  const d = Graph.diff(a, b, 1, 50)
  assert.ok(d.event, "expected a diff or snapshot event")
  const next = Graph.applyEvent(a, d.event)
  assert.ok(next && next.nodes, "applyEvent should return a graph")
  assert.ok(next.nodes.some((n) => n.id === 66))
  assert.ok(next.defaults.sink === 66)
})

test("channelmap: stereo, a2dp, 5.1, ambiguous, mono fan-out", () => {
  const stereo = jsonFix("channel-stereo.json")
  const s = ChannelMap.autoMap(stereo.from, stereo.to)
  assert.strictEqual(s.ok, true)
  assert.strictEqual(s.pairs.length, 2)
  assert.strictEqual(s.pairs[0].from, 1)
  assert.strictEqual(s.pairs[0].to, 3)

  const a2dp = jsonFix("channel-a2dp.json")
  assert.strictEqual(ChannelMap.autoMap(a2dp.from, a2dp.to).ok, true)

  const five = jsonFix("channel-51.json")
  const f = ChannelMap.autoMap(five.from, five.to)
  assert.strictEqual(f.ok, true)
  assert.strictEqual(f.pairs.length, 6)

  const amb = jsonFix("channel-ambiguous.json")
  const a = ChannelMap.autoMap(amb.from, amb.to)
  assert.strictEqual(a.ok, false)
  assert.strictEqual(a.reason, "ambiguous")

  const mono = ChannelMap.autoMap(
    [{ id: 1, node: 1, dir: "out", channel: "MONO", monitor: false }],
    [
      { id: 2, node: 2, dir: "in", channel: "FL", monitor: false },
      { id: 3, node: 2, dir: "in", channel: "FR", monitor: false }
    ]
  )
  assert.strictEqual(mono.ok, true)
  assert.strictEqual(mono.mode, "fan-out")
  assert.strictEqual(mono.pairs.length, 2)
})

test("mute: BFS walks links and returns stream ids only", () => {
  const g = PwDump.parse(fixture("pwdump-simple.json"))
  const ids = Mute.streamIds(g.nodes, g.links, 55)
  assert.ok(ids.indexOf(77) >= 0)
  assert.ok(ids.indexOf(55) < 0)
})

test("mute: isolated hardware node is empty — no device mute fallback", () => {
  const ids = Mute.streamIds(
    [{ id: 55, mediaClass: "Audio/Sink", kind: "sink" }],
    [],
    55
  )
  assert.strictEqual(ids.length, 0)
})

test("pwdump: custom node quantum emits per-route latencyMs", () => {
  const data = jsonFix("pwdump-simple.json")
  const node = data.filter((x) => x.id === 77 && x.type.indexOf("Node") >= 0)[0]
  node.info.props["clock.quantum"] = 256
  const g = PwDump.parse(JSON.stringify(data))
  const ff = g.nodes.find((n) => n.id === 77)
  assert.strictEqual(ff.quantum, 256)
  const lat = g.links.filter((l) => l.fromNode === 77)
  assert.ok(lat.length)
  assert.ok(lat.every((l) => l.latencyMs !== null && l.latencyMs !== undefined))
  assert.ok(lat[0].latencyMs < 10)
})

test("pwdump: graph-default quantum leaves latencyMs null", () => {
  const g = PwDump.parse(fixture("pwdump-simple.json"))
  assert.ok(g.links.every((l) => l.latencyMs === null || l.latencyMs === undefined))
})

test("storm: >10 events in 100ms flips", () => {
  let t = Storm.create()
  const now = 1000
  t = Storm.ingest(t, now, 11)
  assert.strictEqual(Storm.isStorm(t), true)
  const c = Storm.consume(t, now)
  assert.strictEqual(c.storm, true)
  assert.ok(c.n >= 11)
  assert.strictEqual(Storm.isStorm(t), false)
})

test("layout: sources left, sinks right, serial order, user pos wins", () => {
  const g = PwDump.parse(fixture("pwdump-simple.json"))
  const laid = Layout.layout(g.nodes.slice(), g.ports, {})
  const src = laid.nodes.find((n) => n.id === 77)
  const sink = laid.nodes.find((n) => n.id === 55)
  assert.ok(src.x < sink.x)
  const ident = src.identity
  const user = {}
  user[ident] = { x: 400, y: 220 }
  const laid2 = Layout.layout(g.nodes.slice(), g.ports, user)
  const src2 = laid2.nodes.find((n) => n.id === 77)
  assert.strictEqual(src2.x, 400)
  assert.strictEqual(src2.y, 220)
  assert.strictEqual(src2.userPlaced, true)
})

test("layout copies nodes so QML can see x/y updates", () => {
  const g = PwDump.parse(fixture("pwdump-simple.json"))
  const before = g.nodes.find((n) => n.id === 77)
  assert.strictEqual(before.x, undefined)
  const laid = Layout.layout(g.nodes, g.ports, {})
  const after = g.nodes.find((n) => n.id === 77)
  assert.strictEqual(after.x, undefined, "layout must not mutate raw graph nodes")
  const vis = laid.nodes.find((n) => n.id === 77)
  assert.ok(vis !== after)
  assert.ok(typeof vis.x === "number")
})

test("layout applies id: backup when identity misses", () => {
  const g = PwDump.parse(fixture("pwdump-simple.json"))
  const laid = Layout.layout(g.nodes, g.ports, { "id:77": { x: 12, y: 34 } })
  const src = laid.nodes.find((n) => n.id === 77)
  assert.strictEqual(src.x, 12)
  assert.strictEqual(src.y, 34)
  assert.strictEqual(src.userPlaced, true)
})

test("positions set copies the map so a drop survives rebuild", () => {
  const a = Positions.emptyState()
  const b = Positions.set(a, "Google Chrome|Stream/Output/Audio|0", 228, 111)
  assert.strictEqual(a.positions["Google Chrome|Stream/Output/Audio|0"], undefined)
  assert.strictEqual(b.positions["Google Chrome|Stream/Output/Audio|0"].x, 228)
  assert.strictEqual(b.positions["Google Chrome|Stream/Output/Audio|0"].y, 111)
  const g = PwDump.parse(fixture("pwdump-simple.json"))
  const ident = g.nodes.find((n) => n.id === 77).identity
  const pos = Positions.set(Positions.emptyState(), ident, 400, 220).positions
  const laid = Layout.layout(g.nodes, g.ports, pos)
  const src = laid.nodes.find((n) => n.id === 77)
  assert.strictEqual(src.x, 400)
  const store = fs.readFileSync(path.join(ROOT, "GraphStore.qml"), "utf8")
  assert.ok(store.indexOf("if (store.dragging)") >= 0)
  assert.ok(store.indexOf("writingState") >= 0)
  assert.ok(store.indexOf("plainPositions") >= 0)
  assert.ok(store.indexOf("placedById") >= 0)
  assert.ok(store.indexOf("layoutPositions") >= 0)
  const del = fs.readFileSync(path.join(ROOT, "NodeDelegate.qml"), "utf8")
  assert.ok(del.indexOf("drag.active is already false") >= 0)
  const overlaySrc = fs.readFileSync(path.join(ROOT, "LoomOverlay.qml"), "utf8")
  const rel = overlaySrc.split("function handleBodyReleased")[1].split("function handlePortPressed")[0]
  assert.ok(rel.indexOf("store.rebuild(") < 0, "drop must not relayout from raw graph")
})

test("node boxes move their Item on drag, not only JS x/y", () => {
  const src = fs.readFileSync(path.join(ROOT, "NodeDelegate.qml"), "utf8")
  assert.ok(src.indexOf("drag.target: node") >= 0)
  assert.ok(src.indexOf("x: nodeData") < 0)
  assert.ok(src.indexOf("function applyLayout()") >= 0)
  const overlay = fs.readFileSync(path.join(ROOT, "LoomOverlay.qml"), "utf8")
  assert.ok(overlay.indexOf("recreating boxes steals the grab") >= 0)
})

test("overlay moves a playback stream onto a sink instead of pw-link", () => {
  const src = fs.readFileSync(path.join(ROOT, "LoomOverlay.qml"), "utf8")
  assert.ok(src.indexOf("moveStream") >= 0)
  assert.ok(src.indexOf("Stream/Output") >= 0)
  assert.ok(src.indexOf("wireModel") >= 0)
  const store = fs.readFileSync(path.join(ROOT, "GraphStore.qml"), "utf8")
  assert.ok(store.indexOf("no audio ports on that node") >= 0)
})

test("simple view hides midi, duplex, monitors", () => {
  const g = PwDump.parse(fixture("pwdump-chrome-mess.json"))
  const full = SimpleView.filter(g, false)
  const simple = SimpleView.filter(g, true)
  assert.ok(full.nodes.some((n) => n.kind === "midi"))
  assert.ok(!simple.nodes.some((n) => n.kind === "midi"))
  assert.ok(!simple.nodes.some((n) => n.kind === "filter"))
  assert.ok(!simple.ports.some((p) => p.monitor))
  assert.ok(simple.nodes.some((n) => n.app === "Google Chrome"))
  assert.strictEqual(SimpleView.activeStreamCount(g.nodes), 1)
  assert.strictEqual(SimpleView.captureLive(g.nodes), true)
})

test("commands: move uses target metadata, spawn is Loom- prefixed", () => {
  const mv = Commands.move(77, 9901)
  assert.strictEqual(mv.primary[0], "pw-metadata")
  assert.strictEqual(mv.primary[1], "-n")
  assert.strictEqual(mv.primary[2], "default")
  assert.strictEqual(mv.primary[3], "77")
  assert.strictEqual(mv.primary[4], "target.object")
  assert.strictEqual(mv.primary[5], "9901")
  assert.ok(!mv.fallback)
  assert.strictEqual(Commands.targetKey({ id: 55, serial: 9901, name: "alsa" }), "9901")
  assert.strictEqual(Commands.targetKey({ id: 55, name: "alsa" }), "alsa")
  const sp = Commands.spawnSink("Recording")
  assert.strictEqual(sp.sinkName, "Loom-Recording")
  assert.ok(sp.primary.indexOf("module-null-sink") >= 0)
  assert.strictEqual(Commands.sanitizeSinkName("alsa_output.pci"), "Loom-alsa_outputpci")
  const denied = Commands.sanitizeSinkName("Loom-Mix")
  assert.strictEqual(denied, "Loom-Mix")
})

test("commands: pactl short parsers find Loom sinks only", () => {
  const sinks = Commands.parsePactlShortSinks(
    "0\talsa_output.pci\tmodule-alsa-card.c\n1\tLoom-Mix\tmodule-null-sink.c\n"
  )
  const loom = Commands.loomSinks(sinks)
  assert.strictEqual(loom.length, 1)
  assert.strictEqual(loom[0].name, "Loom-Mix")
  const mods = Commands.parsePactlShortModules(
    "12\tmodule-null-sink\tsink_name=Loom-Mix\n13\tmodule-alsa-card\tdevice_id=0\n"
  )
  assert.strictEqual(Commands.loomModules(mods).length, 1)
})

test("positions: composite identity, persist roundtrip", () => {
  const g = PwDump.parse(fixture("pwdump-chrome-mess.json"))
  const a = g.nodes.find((n) => n.id === 101)
  const b = g.nodes.find((n) => n.id === 102)
  assert.notStrictEqual(a.identity, b.identity)
  let st = Positions.emptyState()
  st = Positions.set(st, a.identity, 10, 20)
  const raw = Positions.serialize(st)
  const loaded = Positions.load(raw)
  const got = Positions.get(loaded, a.identity)
  assert.ok(got, "expected persisted position for " + a.identity)
  assert.strictEqual(got.x, 10)
  assert.strictEqual(got.y, 20)
})

test("graph: same-id state/mute/volume/default emit a change", () => {
  const a = PwDump.parse(fixture("pwdump-simple.json"))
  a.gen = 1
  const bRunning = JSON.parse(JSON.stringify(a))
  const ff = bRunning.nodes.find((n) => n.id === 77)
  ff.state = "idle"
  const d = Graph.diff(a, bRunning, 1, 50)
  assert.ok(d.event, "state change must produce an event")
  assert.ok(d.n >= 1)
  const muted = JSON.parse(JSON.stringify(a))
  muted.nodes.find((n) => n.id === 77).mute = true
  assert.ok(Graph.diff(a, muted, 1, 50).n >= 1)
  const vol = JSON.parse(JSON.stringify(a))
  vol.nodes.find((n) => n.id === 55).volume = 0.1
  assert.ok(Graph.diff(a, vol, 1, 50).n >= 1)
  const def = JSON.parse(JSON.stringify(a))
  def.defaults.sink = 999
  assert.ok(Graph.diff(a, def, 1, 50).event)
})

test("commands: loom name extract + reconcile adopt", () => {
  assert.strictEqual(Commands.loomNameFromArgument("sink_name=Loom-Mix"), "Loom-Mix")
  assert.strictEqual(Commands.loomNameFromArgument("device_id=0"), "")
  const mods = Commands.parsePactlShortModules(
    "12\tmodule-null-sink\tsink_name=Loom-Mix\n13\tmodule-alsa-card\tdevice_id=0\n14\tmodule-null-sink\tsink_name=alsa_output\n"
  )
  const plan = Commands.reconcileLoomModules(mods, false)
  assert.strictEqual(plan.adopted.length, 1)
  assert.strictEqual(plan.adopted[0].name, "Loom-Mix")
  assert.strictEqual(String(plan.adopted[0].moduleId), "12")
})

test("commands: destroySink refuses non-Loom and mismatched moduleId", () => {
  const mods = Commands.parsePactlShortModules(
    "12\tmodule-null-sink\tsink_name=Loom-Mix\n13\tmodule-alsa-card\tdevice_id=0\n"
  )
  assert.strictEqual(Commands.verifyDestroySink("Loom-Mix", 12, mods).ok, true)
  assert.strictEqual(Commands.verifyDestroySink("alsa_output.pci", 12, mods).ok, false)
  assert.strictEqual(Commands.verifyDestroySink("Loom-Mix", 99, mods).ok, false)
  assert.strictEqual(Commands.verifyDestroySink("Loom-Other", 12, mods).ok, false)
})

test("graph: identity/channels/moduleId/port name/link endpoints count as changes", () => {
  const a = PwDump.parse(fixture("pwdump-simple.json"))
  a.gen = 1
  const ident = JSON.parse(JSON.stringify(a))
  ident.nodes[0].identity = "changed|x|0"
  assert.ok(Graph.diff(a, ident, 1, 50).n >= 1)
  const ch = JSON.parse(JSON.stringify(a))
  ch.nodes.find((n) => n.id === 77).channels = ["MONO"]
  assert.ok(Graph.diff(a, ch, 1, 50).n >= 1)
  const mid = JSON.parse(JSON.stringify(a))
  mid.nodes.find((n) => n.id === 55).moduleId = 7
  assert.ok(Graph.diff(a, mid, 1, 50).n >= 1)
  const pname = JSON.parse(JSON.stringify(a))
  pname.ports[0].name = "renamed"
  pname.ports[0].physical = true
  assert.ok(Graph.diff(a, pname, 1, 50).n >= 1)
  const lep = JSON.parse(JSON.stringify(a))
  lep.links[0].fromNode = 1
  lep.links[0].latencyMs = 8
  assert.ok(Graph.diff(a, lep, 1, 50).n >= 1)
  const q = JSON.parse(JSON.stringify(a))
  q.graph.quantum = 64
  const dq = Graph.diff(a, q, 1, 50)
  assert.ok(dq.event, "quantum change must emit")
})

test("schema.md destroySink example includes moduleId", () => {
  const md = fs.readFileSync(path.join(ROOT, "schema.md"), "utf8")
  assert.ok(/destroySink.*"moduleId"/.test(md.replace(/\n/g, " ")))
})

test("schema: spawnSink ok carries name and moduleId", () => {
  const ev = Schema.parseLine(
    '{"t":"ok","id":"1","op":"spawnSink","name":"Loom-Mix","moduleId":12}'
  )
  assert.strictEqual(ev.t, "ok")
  assert.strictEqual(ev.op, "spawnSink")
  assert.strictEqual(ev.name, "Loom-Mix")
  assert.strictEqual(ev.moduleId, 12)
})

test("manifest: virtualSinks defaults false", () => {
  const man = JSON.parse(fs.readFileSync(path.join(ROOT, "manifest.json"), "utf8"))
  assert.strictEqual(man.barWidget.defaults.virtualSinks, false)
})

test("readme: enable + defaultSection, no bar put / summon", () => {
  const md = fs.readFileSync(path.join(ROOT, "README.md"), "utf8")
  assert.ok(md.indexOf("omarchy plugin enable io.github.chris.pipewire-loom") >= 0)
  assert.ok(md.indexOf("omarchy bar put") < 0)
  assert.ok(md.indexOf("shell summon io.github.chris.pipewire-loom") < 0)
  assert.ok(md.indexOf("toggle '{}'") >= 0)
})

test("binds: empty live list offers SUPER+SHIFT+L", () => {
  const p = Binds.plan([])
  assert.strictEqual(p.needed, true)
  assert.strictEqual(p.toAdd.length, 1)
  assert.strictEqual(p.toAdd[0].chosen, "SUPER + SHIFT + L")
  assert.ok(Binds.luaBlock(p.toAdd).indexOf("o.bind(\"SUPER + SHIFT + L\"") === 0)
  assert.ok(p.toAdd[0].chosen !== "SUPER + SHIFT + A")
})

test("binds: stock ChatGPT SUPER+SHIFT+A is not stolen", () => {
  const live = [
    { modmask: 65, key: "A", dispatcher: "__lua", arg: "306", description: "ChatGPT" }
  ]
  const p = Binds.plan(live)
  assert.strictEqual(p.toAdd[0].chosen, "SUPER + SHIFT + L")
})

test("binds: occupied preferred uses SUPER+ALT+L", () => {
  const live = [
    { modmask: 65, key: "L", dispatcher: "exec", arg: "other", description: "taken" }
  ]
  const p = Binds.plan(live)
  assert.strictEqual(p.toAdd[0].chosen, "SUPER + ALT + L")
})

test("binds: already-ours via lua description hides the offer", () => {
  const live = [
    { modmask: 65, key: "L", dispatcher: "__lua", arg: "15", description: "PipeWire Loom" }
  ]
  const p = Binds.plan(live)
  assert.strictEqual(p.needed, false)
  assert.strictEqual(p.toAdd.length, 0)
})

test("binds: notify body lists assigned keys", () => {
  const body = Binds.notifyBody([{ chosen: "SUPER + SHIFT + L", desc: "PipeWire Loom" }], [])
  assert.ok(body.indexOf("SUPER + SHIFT + L — PipeWire Loom") === 0)
  const argv = Binds.notifyArgv("PipeWire Loom", "PipeWire Loom keybindings", body)
  assert.strictEqual(argv[0], "omarchy")
  assert.strictEqual(argv[1], "notification")
  assert.strictEqual(argv[2], "send")
  assert.strictEqual(argv[4], "PipeWire Loom")
  assert.strictEqual(argv[7], "PipeWire Loom keybindings")
})

test("binds: claimAuto is one-shot", () => {
  assert.strictEqual(Binds.claimAuto(), true)
  assert.strictEqual(Binds.claimAuto(), false)
})

test("qml: no keys chip; bar widget auto-claims", () => {
  const src = fs.readFileSync(path.join(ROOT, "BarWidget.qml"), "utf8")
  assert.ok(src.indexOf("Add keybindings") < 0)
  assert.ok(src.indexOf('text: "keys"') < 0)
  assert.ok(src.indexOf("Binds.claimAuto()") >= 0)
  assert.ok(src.indexOf("notifyArgv(") >= 0)
})

test("bar widget loads LoomOverlay.qml, not the host qs.Ui Panel type", () => {
  const src = fs.readFileSync(path.join(ROOT, "BarWidget.qml"), "utf8")
  assert.ok(src.indexOf('Qt.resolvedUrl("LoomOverlay.qml")') >= 0)
  assert.ok(!/\bPanel\s*\{/.test(src), "bare Panel { } is qs.Ui.Panel, not the overlay")
  const overlay = fs.readFileSync(path.join(ROOT, "LoomOverlay.qml"), "utf8")
  assert.ok(overlay.indexOf('WlrLayershell.namespace: "pipewire-loom"') >= 0)
  assert.ok(overlay.indexOf("visible: root.opened") >= 0)
})

test("link uses port names, not pw-link -I", () => {
  const argv = Commands.argvFor("link", {
    from: 74,
    to: 57,
    fromName: "Google Chrome:output_FL",
    toName: "alsa_output.pci-0000_01_00.1.hdmi-stereo:playback_FL"
  })
  assert.ok(argv)
  assert.ok(argv.primary.join(" ").indexOf("pw-link -I") < 0)
  assert.strictEqual(argv.primary[0], "pw-link")
  assert.strictEqual(argv.primary[1], "Google Chrome:output_FL")
  const analog = { name: "alsa_input.pci-0000_00_1f.3.analog-stereo", nick: "ALC1220 Analog" }
  const cap = { name: "capture_FL", alias: "ALC1220 Analog:capture_FL" }
  assert.strictEqual(Commands.portLinkName(analog, cap), "alsa_input.pci-0000_00_1f.3.analog-stereo:capture_FL")
  const src = fs.readFileSync(path.join(ROOT, "NodeDelegate.qml"), "utf8")
  assert.ok(src.indexOf("preventStealing: true") >= 0)
  assert.ok(src.indexOf("Title strip only") >= 0)
  const overlay = fs.readFileSync(path.join(ROOT, "LoomOverlay.qml"), "utf8")
  assert.ok(overlay.indexOf("nodeRepeater.itemAt") >= 0)
  assert.ok(overlay.indexOf("propagateComposedEvents") >= 0)
})

test("unlink uses pw-link -d link-id and clears stream target.object", () => {
  const byId = Commands.argvFor("unlink", { link: 78, from: 74, to: 57 })
  assert.ok(byId)
  assert.strictEqual(byId.primary.join(" "), "pw-link -d 78")
  const clr = Commands.argvFor("clearTarget", { stream: 39 })
  assert.strictEqual(clr.primary.join(" "), "pw-metadata -n default -d 39 target.object")
  const store = fs.readFileSync(path.join(ROOT, "GraphStore.qml"), "utf8")
  assert.ok(store.indexOf("clearTarget") >= 0)
  const overlay = fs.readFileSync(path.join(ROOT, "LoomOverlay.qml"), "utf8")
  assert.ok(overlay.indexOf('sequence: "X"') >= 0)
  assert.ok(overlay.indexOf('sequence: "Backspace"') >= 0)
})

test("move stickiness contract: command is metadata not pw-link", () => {
  const argv = Commands.argvFor("move", { stream: 88, target: 66, targetSerial: 12004, targetName: "bluez_out" })
  assert.ok(argv)
  const joined = argv.primary.join(" ")
  assert.ok(joined.indexOf("pw-link") < 0)
  assert.ok(joined.indexOf("wpctl") < 0)
  assert.ok(joined.indexOf("set-target") < 0)
  assert.ok(joined.indexOf("pw-metadata -n default 88 target.object 12004") >= 0)
  assert.ok(Commands.argvFor("move", { stream: 88, target: 66 }) === null)
})

process.stdout.write("\n" + passed + " passed, " + failed + " failed\n")
process.exit(failed ? 1 : 0)
