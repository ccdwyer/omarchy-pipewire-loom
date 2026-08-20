import QtQuick
import Quickshell.Io
import "js/Schema.js" as Schema
import "js/Graph.js" as Graph
import "js/Layout.js" as Layout
import "js/SimpleView.js" as SimpleView
import "js/ChannelMap.js" as ChannelMap
import "js/Mute.js" as Mute
import "js/Positions.js" as Positions
import "js/Commands.js" as Commands

// Owns the graph model. Backends feed NDJSON (or parsed pw-dump) in;
// verbs go out as commands. One instance, created by BarWidget.

Item {
  id: store

  property var backend: null
  property string statePath: ""
  property bool simpleView: true
  property bool virtualSinks: false

  property int gen: 0
  property var raw: ({ nodes: [], ports: [], links: [], defaults: ({}), graph: ({}) })
  property var viewNodes: []
  property var viewPorts: []
  property var viewLinks: []
  property var wires: []
  property var positions: ({})
  property var loomModules: ({})
  property var placedById: ({})
  property bool dragging: false
  property bool writingState: false
  property int canvasW: 960
  property int canvasH: 640
  property int revision: 0
  property int selectedId: -1
  property bool compatMode: true
  property string backendName: "cli"
  property string lastToast: ""
  property string lastToastLevel: "info"
  property var highlightPortIds: []
  property int toastSerial: 0
  property bool emptyGraph: true
  property int streamCount: 0
  property bool captureLive: false
  property string defaultSinkNick: "—"
  property bool defaultSinkIsLoom: false
  property var lastMuted: []
  property bool lastMutedOn: false
  property int lastMutedRoot: -1

  signal outbound(var cmd)
  signal toast(string msg, string level)
  signal highlight(var ids)
  signal gone()

  property bool stateLoaded: false
  property bool adoptedOnce: false

  function bump() {
    store.revision += 1
  }

  function onOk(ev) {
    if (!ev)
      return
    if (ev.op === "spawnSink") {
      var nm = ev.name || ev.sinkName
      var mid = ev.moduleId !== undefined ? ev.moduleId : ev.module_id
      if (nm && mid !== undefined && mid !== null && String(mid).length)
        store.rememberModule(String(nm), mid)
      return
    }
    if (ev.op === "cleanupOrphans") {
      var i
      if (ev.destroy || (ev.removed && ev.removed.length && !(ev.adopted && ev.adopted.length))) {
        var nextMods = {}
        if (ev.adopted && ev.adopted.length) {
          for (i = 0; i < ev.adopted.length; i++) {
            if (ev.adopted[i].name && ev.adopted[i].moduleId !== undefined)
              nextMods[ev.adopted[i].name] = ev.adopted[i].moduleId
          }
        }
        store.loomModules = nextMods
        store.saveState()
        return
      }
      if (ev.adopted && ev.adopted.length) {
        for (i = 0; i < ev.adopted.length; i++) {
          if (ev.adopted[i].name && ev.adopted[i].moduleId !== undefined)
            store.rememberModule(ev.adopted[i].name, ev.adopted[i].moduleId)
        }
      }
    }
  }

  function emitToast(msg, level) {
    store.lastToast = String(msg || "")
    store.lastToastLevel = level || "info"
    store.toastSerial += 1
    store.toast(store.lastToast, store.lastToastLevel)
  }

  function applyLine(line) {
    var ev = Schema.parseLine(line)
    if (!ev)
      return
    store.applyEvent(ev)
  }

  function applyEvent(ev) {
    if (!ev)
      return
    if (ev.t === "hello") {
      store.backendName = ev.backend || store.backendName
      store.compatMode = ev.compat !== undefined ? !!ev.compat : store.compatMode
      store.bump()
      return
    }
    if (ev.t === "toast") {
      store.emitToast(ev.msg, ev.level || "info")
      return
    }
    if (ev.t === "err") {
      if (ev.op === "cleanupOrphans") {
        var keep = ev.retained || ev.failed || []
        var nextMods = {}
        for (var f = 0; f < keep.length; f++) {
          if (keep[f].name && keep[f].moduleId !== undefined)
            nextMods[keep[f].name] = keep[f].moduleId
        }
        store.loomModules = nextMods
        store.saveState()
      }
      if (ev.err === "gone") {
        store.gone()
        store.emitToast("gone", "warn")
      } else if (ev.err === "ambiguous") {
        store.emitToast("ambiguous channel map", "warn")
      } else {
        store.emitToast(ev.msg || ev.err || "error", "warn")
      }
      return
    }
    if (ev.t === "ok") {
      store.onOk(ev)
      return
    }
    if (ev.t === "storm")
      return

    var next = Graph.applyEvent(store.raw, ev)
    if (next && next.mismatch) {
      store.requestDump()
      return
    }
    if (!next)
      return
    store.raw = next
    store.gen = next.gen || store.gen
    store.rebuild()
  }

  function applyParsed(graph) {
    var ev = {
      t: "snapshot",
      gen: (store.gen || 0) + 1,
      nodes: graph.nodes,
      ports: graph.ports,
      links: graph.links,
      defaults: graph.defaults,
      graph: graph.graph
    }
    store.applyEvent(ev)
  }

  function applyDiffFromPrev(prev, nextGraph) {
    var d = Graph.diff(prev, nextGraph, store.gen, 10)
    if (!d.event)
      return
    if (d.storm)
      store.applyEvent(Schema.makeStorm((store.gen || 0) + 1, d.n, 100))
    store.applyEvent(d.event)
  }

  function plainPositions() {
    try {
      return JSON.parse(JSON.stringify(store.positions || {}))
    } catch (e) {
      return {}
    }
  }

  function setPlaced(nodeId, x, y) {
    var next = {}
    var src = store.placedById || {}
    var keys = Object.keys(src)
    for (var i = 0; i < keys.length; i++)
      next[keys[i]] = src[keys[i]]
    next[String(nodeId)] = { x: x, y: y }
    store.placedById = next
  }

  function layoutPositions() {
    var pos = store.plainPositions()
    var placed = store.placedById || {}
    var keys = Object.keys(placed)
    var i
    for (i = 0; i < keys.length; i++) {
      var p = placed[keys[i]]
      if (!p || typeof p.x !== "number" || typeof p.y !== "number")
        continue
      pos["id:" + keys[i]] = { x: p.x, y: p.y }
    }
    var vn = store.viewNodes || []
    for (i = 0; i < vn.length; i++) {
      var n = vn[i]
      if (!n || !n.userPlaced || typeof n.x !== "number" || typeof n.y !== "number")
        continue
      pos["id:" + n.id] = { x: n.x, y: n.y }
      if (n.identity)
        pos[n.identity] = { x: n.x, y: n.y }
    }
    return pos
  }

  function rebuild() {
    if (store.dragging)
      return
    var filtered = SimpleView.filter(store.raw, store.simpleView)
    var laid = Layout.layout(filtered.nodes, filtered.ports, store.layoutPositions())
    store.viewNodes = laid.nodes
    store.viewPorts = filtered.ports
    store.viewLinks = filtered.links
    store.canvasW = Math.max(800, laid.width)
    store.canvasH = Math.max(480, laid.height)
    store.wires = store.buildWires(laid.nodes, filtered.ports, filtered.links)
    store.emptyGraph = SimpleView.activeStreamCount(store.raw.nodes) === 0 && !(store.raw.nodes && store.raw.nodes.length)
    if (store.raw.nodes && store.raw.nodes.length && SimpleView.activeStreamCount(store.raw.nodes) === 0)
      store.emptyGraph = !filtered.nodes.length
    store.streamCount = SimpleView.activeStreamCount(store.raw.nodes)
    store.captureLive = SimpleView.captureLive(store.raw.nodes)
    var sink = SimpleView.defaultSink(store.raw.nodes, store.raw.defaults)
    store.defaultSinkNick = sink ? (sink.nick || sink.name || "sink") : "—"
    store.defaultSinkIsLoom = !!(sink && sink.isLoom)
    store.emptyGraph = filtered.nodes.length === 0
    store.bump()
  }

  function buildWires(nodes, ports, links) {
    var byNode = {}
    var i
    for (i = 0; i < (nodes || []).length; i++)
      byNode[nodes[i].id] = nodes[i]
    var out = []
    for (i = 0; i < (links || []).length; i++) {
      var l = links[i]
      var a = byNode[l.fromNode]
      var b = byNode[l.toNode]
      if (!a || !b)
        continue
      var ai = Layout.indexOfPort(a, ports, l.from, "out")
      var bi = Layout.indexOfPort(b, ports, l.to, "in")
      var ac = Layout.countDir(a, ports, "out")
      var bc = Layout.countDir(b, ports, "in")
      var ap = Layout.portAnchor(a, null, ai, ac, "out")
      var bp = Layout.portAnchor(b, null, bi, bc, "in")
      out.push({
        id: l.id,
        from: l.from,
        to: l.to,
        fromNode: l.fromNode,
        toNode: l.toNode,
        x1: ap.x,
        y1: ap.y,
        x2: bp.x,
        y2: bp.y,
        live: !!l.live,
        muted: !!l.muted,
        raw: l.kind === "raw",
        latencyMs: l.latencyMs === undefined ? null : l.latencyMs
      })
    }
    return out
  }

  function nodeById(id) {
    return Graph.findNode({ nodes: store.viewNodes }, id) || Graph.findNode(store.raw, id)
  }

  function portById(id) {
    return Graph.findPort({ ports: store.viewPorts }, id) || Graph.findPort(store.raw, id)
  }

  function send(cmd) {
    store.outbound(cmd)
    if (store.backend && typeof store.backend.send === "function")
      store.backend.send(cmd)
  }

  function requestDump() {
    store.send(Schema.makeCommand("dump", {}))
  }

  function select(id) {
    store.selectedId = id
    store.highlightPortIds = []
    store.bump()
  }

  function selectDelta(dx, dy) {
    var nodes = store.viewNodes || []
    if (!nodes.length)
      return
    var cur = store.nodeById(store.selectedId)
    if (!cur) {
      store.select(nodes[0].id)
      return
    }
    var best = null
    var bestScore = 1e15
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n.id === cur.id)
        continue
      var vx = n.x - cur.x
      var vy = n.y - cur.y
      if (dx && vx * dx <= 0)
        continue
      if (dy && vy * dy <= 0)
        continue
      var score = Math.abs(vx) + Math.abs(vy)
      if (dx)
        score += Math.abs(vy) * 2
      if (dy)
        score += Math.abs(vx) * 2
      if (score < bestScore) {
        bestScore = score
        best = n
      }
    }
    if (best)
      store.select(best.id)
  }

  function toggleSimple() {
    store.simpleView = !store.simpleView
    store.rebuild()
  }

  function moveStream(streamId, sinkId) {
    if (!Graph.findNode(store.raw, streamId) || !Graph.findNode(store.raw, sinkId)) {
      store.emitToast("gone", "warn")
      store.gone()
      return "gone"
    }
    var src = Graph.findNode(store.raw, streamId)
    var dst = Graph.findNode(store.raw, sinkId)
    if (!src || String(src.mediaClass || "").indexOf("Stream/Output") !== 0) {
      // Not a playback stream — fall through to explicit auto-link.
      return store.linkNodes(streamId, sinkId)
    }
    var key = Commands.targetKey(dst)
    if (!key) {
      store.emitToast("target has no serial or name", "warn")
      return "gone"
    }
    store.send(Schema.makeCommand("move", {
      stream: streamId,
      target: sinkId,
      targetSerial: dst.serial,
      targetName: dst.name
    }))
    return "ok"
  }

  function linkPorts(fromId, toId) {
    if (!Graph.findPort(store.raw, fromId) || !Graph.findPort(store.raw, toId)) {
      store.emitToast("gone", "warn")
      store.gone()
      return "gone"
    }
    store.send(Schema.makeCommand("link", { from: fromId, to: toId }))
    return "ok"
  }

  function linkNodes(fromNode, toNode) {
    var mapped = ChannelMap.autoMapNodes(store.raw.ports, fromNode, toNode)
    if (!mapped.ok) {
      var ids = []
      var ports = store.raw.ports || []
      for (var i = 0; i < ports.length; i++) {
        if ((ports[i].node === fromNode || ports[i].node === toNode) && !ports[i].monitor)
          ids.push(ports[i].id)
      }
      store.highlightPortIds = ids
      store.highlight(ids)
      var detail = mapped.detail || ""
      store.emitToast(detail === "no ports" ? "no audio ports on that node" : ("ambiguous map (" + detail + ")"), "warn")
      return "ambiguous"
    }
    store.highlightPortIds = []
    for (var p = 0; p < mapped.pairs.length; p++)
      store.send(Schema.makeCommand("link", { from: mapped.pairs[p].from, to: mapped.pairs[p].to }))
    return "ok"
  }

  function unlink(linkId) {
    var link = Graph.findLink(store.raw, linkId)
    if (!link) {
      store.emitToast("gone", "warn")
      return "gone"
    }
    store.send(Schema.makeCommand("unlink", { link: linkId, from: link.from, to: link.to }))
    return "ok"
  }

  function unlinkSelected() {
    var id = store.selectedId
    var links = store.viewLinks || []
    for (var i = 0; i < links.length; i++) {
      if (links[i].fromNode === id || links[i].toNode === id)
        store.unlink(links[i].id)
    }
    var node = store.nodeById(id)
    if (node && node.isLoom)
      store.destroySink(node.name || node.nick)
  }

  function setVolume(nodeId, vol) {
    if (!Graph.findNode(store.raw, nodeId))
      return "gone"
    store.send(Schema.makeCommand("volume", { node: nodeId, vol: vol }))
    return "ok"
  }

  function nudgeVolume(delta) {
    var node = store.nodeById(store.selectedId)
    if (!node)
      return
    var v = (node.volume || 0) + delta
    if (v < 0)
      v = 0
    if (v > 1)
      v = 1
    store.setVolume(node.id, v)
  }

  function muteNode(nodeId, on) {
    if (!Graph.findNode(store.raw, nodeId))
      return "gone"
    store.send(Schema.makeCommand("mute", { node: nodeId, mute: !!on }))
    return "ok"
  }

  function muteSubgraph(nodeId) {
    var id = nodeId === undefined ? store.selectedId : nodeId
    if (id < 0)
      return "gone"
    if (!Graph.findNode(store.raw, id)) {
      store.emitToast("gone", "warn")
      return "gone"
    }
    var turnOn = true
    if (store.lastMutedRoot === id && store.lastMutedOn)
      turnOn = false
    var ids = Mute.streamIds(store.raw.nodes, store.raw.links, id)
    if (!ids.length) {
      store.emitToast("no streams in subgraph", "info")
      return "ok"
    }
    store.lastMuted = ids
    store.lastMutedOn = turnOn
    store.lastMutedRoot = id
    store.send(Schema.makeCommand("muteSubgraph", { node: id, mute: turnOn, nodes: ids }))
    return "ok"
  }

  function spawnSink(name) {
    if (!store.virtualSinks) {
      store.emitToast("virtual sinks disabled", "info")
      return "denied"
    }
    store.send(Schema.makeCommand("spawnSink", { name: name || "Mix" }))
    return "ok"
  }

  function destroySink(name) {
    var n = String(name || "")
    if (n.indexOf("Loom-") !== 0) {
      store.emitToast("will not touch non-Loom devices", "warn")
      return "denied"
    }
    var moduleId = store.loomModules[n]
    store.send(Schema.makeCommand("destroySink", { name: n, moduleId: moduleId }))
    return "ok"
  }

  function adoptLoomSinks() {
    store.send(Schema.makeCommand("cleanupOrphans", { destroy: false }))
    return "ok"
  }

  function cleanupOrphans() {
    store.send(Schema.makeCommand("cleanupOrphans", { destroy: true }))
    return "ok"
  }

  function persistPosition(nodeId, x, y, save) {
    var node = store.nodeById(nodeId)
    if (!node)
      return
    store.setPlaced(nodeId, x, y)
    var ident = node.identity || Positions.identityOf(node, store.raw.nodes)
    var cur = store.plainPositions()
    var next = Positions.set({ positions: cur, loomModules: store.loomModules }, ident, x, y)
    next.positions["id:" + nodeId] = { x: x, y: y }
    store.positions = next.positions
    node.x = x
    node.y = y
    node.userPlaced = true
    store.wires = store.buildWires(store.viewNodes, store.viewPorts, store.viewLinks)
    store.bump()
    if (save !== false)
      store.saveState()
  }

  function rememberModule(name, moduleId) {
    var next = {}
    var keys = Object.keys(store.loomModules || {})
    for (var i = 0; i < keys.length; i++)
      next[keys[i]] = store.loomModules[keys[i]]
    next[name] = moduleId
    store.loomModules = next
    store.saveState()
  }

  function loadStateText(text) {
    var s = Positions.load(text)
    store.positions = s.positions || {}
    store.loomModules = s.loomModules || {}
    store.stateLoaded = true
    store.rebuild()
    store.maybeAdopt()
  }

  function maybeAdopt() {
    if (store.adoptedOnce || !store.stateLoaded || !store.statePath)
      return
    store.adoptedOnce = true
    store.adoptLoomSinks()
  }

  function saveState() {
    if (!stateFile.path)
      return
    try {
      store.writingState = true
      stateFile.setText(Positions.serialize({ positions: store.positions, loomModules: store.loomModules }))
      Qt.callLater(function () { store.writingState = false })
    } catch (e) {
      store.writingState = false
    }
  }

  FileView {
    id: stateFile
    path: store.statePath
    atomicWrites: true
    printErrors: false
    watchChanges: false
    onLoaded: {
      if (store.writingState)
        return
      store.loadStateText(text())
    }
    onLoadFailed: {
      if (store.writingState)
        return
      if (!store.statePath)
        return
      if (Object.keys(store.plainPositions()).length)
        return
      store.loadStateText("{}")
    }
  }

  onSimpleViewChanged: store.rebuild()
}
