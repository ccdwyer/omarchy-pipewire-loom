import QtQuick
import Quickshell
import Quickshell.Io
import "js/Schema.js" as Schema
import "js/Graph.js" as Graph
import "js/PwDump.js" as PwDump
import "js/Commands.js" as Commands
import "js/Storm.js" as Storm
import "js/Mute.js" as Mute
import "js/ChannelMap.js" as ChannelMap

// v1.0 backend is the CLI path (pw-dump + wpctl + pw-link + pactl).
// Optional loomd is the same CLI poller speaking NDJSON (not native subscribe).
// After 3 daemon crashes, we stay on in-process CLI and raise the compat badge.

Item {
  id: root

  property var store: null
  property string pluginDir: ""
  property int pollMs: 1000
  property bool panelOpen: false

  readonly property string loomdBin: pluginDir + "/bin/loomd"
  readonly property string compatSh: pluginDir + "/compat/loom-cli.sh"

  property bool loomdPresent: false
  property bool probed: false
  property string mode: "cli"
  property int crashes: 0
  property bool waitingHello: false
  property var lastGraph: null
  property var storm: ({})
  property var workQueue: []
  property var workCurrent: null
  property string dumpBuf: ""

  function send(cmd) {
    if (!cmd)
      return
    if (root.mode === "loomd-daemon" && loomdProc.running) {
      if (root.writeDaemon(cmd))
        return
    }
    if (root.loomdPresent && root.mode !== "cli") {
      root.enqueue([root.loomdBin, "--cmd", JSON.stringify(cmd)], function (text) {
        root.ingestText(text)
      })
      return
    }
    root.runCliCommand(cmd)
  }

  function writeDaemon(cmd) {
    if (!loomdProc.running || !loomdProc.stdinEnabled)
      return false
    try {
      if (typeof loomdProc.write === "function") {
        loomdProc.write(JSON.stringify(cmd) + "\n")
        return true
      }
    } catch (e) {}
    return false
  }

  function ingestText(text) {
    var evs = Schema.parseStream(text)
    for (var i = 0; i < evs.length; i++)
      root.ingestEvent(evs[i])
  }

  function ingestEvent(ev) {
    if (!ev)
      return
    if (ev.t === "hello") {
      root.waitingHello = false
      helloTimer.stop()
      if (root.store)
        root.store.compatMode = !!ev.compat || ev.backend === "cli"
      if (root.store)
        root.store.backendName = ev.backend || root.mode
      if (root.store && typeof root.store.maybeAdopt === "function")
        Qt.callLater(function () { root.store.maybeAdopt() })
    }
    if (root.store)
      root.store.applyEvent(ev)
  }

  function ingestDump(text) {
    var graph = PwDump.parse(text)
    if (!root.store)
      return
    if (!root.lastGraph) {
      root.store.applyParsed(graph)
    } else {
      root.store.applyDiffFromPrev(root.lastGraph, graph)
    }
    root.lastGraph = graph
  }

  function enqueue(command, done) {
    root.workQueue.push({ command: command, done: done || null })
    root.runWork()
  }

  function runWork() {
    if (workProc.running || root.workCurrent)
      return
    if (!root.workQueue.length)
      return
    root.workCurrent = root.workQueue.shift()
    workProc.command = root.workCurrent.command
    workProc.running = true
  }

  function startDaemon() {
    if (!root.loomdPresent)
      return
    if (root.crashes >= 3) {
      root.useCli("loomd crashed 3×")
      return
    }
    root.mode = "loomd-daemon"
    root.waitingHello = true
    loomdProc.command = [root.loomdBin, "--cli"]
    loomdProc.stdinEnabled = true
    loomdProc.running = true
    helloTimer.restart()
  }

  function useCli(reason) {
    root.mode = "cli"
    if (root.store) {
      root.store.compatMode = true
      root.store.backendName = "cli"
      if (reason)
        root.store.emitToast("compat mode", "info")
    }
    if (loomdProc.running)
      loomdProc.running = false
    pollTimer.restart()
    root.pollNow()
  }

  function useOneshot() {
    root.mode = "loomd-oneshot"
    if (root.store) {
      root.store.compatMode = false
      root.store.backendName = "loomd"
    }
    pollTimer.restart()
    root.pollNow()
  }

  function pollNow() {
    if (root.mode === "loomd-daemon")
      return
    if (root.mode === "loomd-oneshot" && root.loomdPresent) {
      root.enqueue([root.loomdBin, "--dump"], function (text) {
        if (text && String(text).indexOf("\"t\":\"snapshot\"") >= 0)
          root.ingestText(text)
        else
          root.ingestDump(text)
      })
      return
    }
    root.enqueue(["pw-dump"], function (text, code) {
      if (code !== 0 && (!text || !String(text).length)) {
        if (root.store)
          root.store.emitToast("pw-dump unavailable", "warn")
        return
      }
      root.ingestDump(text)
    })
  }

  function runCliCommand(cmd) {
    var op = cmd.op
    if (op === "dump") {
      root.pollNow()
      return
    }
    if (op === "link" && cmd.fromNode !== undefined && cmd.toNode !== undefined && cmd.from === undefined) {
      var mapped = ChannelMap.autoMapNodes((root.store && root.store.raw && root.store.raw.ports) || [], cmd.fromNode, cmd.toNode)
      if (!mapped.ok) {
        if (root.store)
          root.store.applyEvent(Schema.makeErr(cmd.id, "link", "ambiguous", mapped.detail))
        return
      }
      for (var i = 0; i < mapped.pairs.length; i++)
        root.dispatchArgv(Commands.linkPorts(mapped.pairs[i].from, mapped.pairs[i].to), cmd, i === mapped.pairs.length - 1)
      return
    }
    if (op === "muteSubgraph") {
      var ids = cmd.nodes
      if (!ids && root.store)
        ids = Mute.streamIds(root.store.raw.nodes, root.store.raw.links, cmd.node)
      ids = ids || []
      if (!ids.length) {
        if (root.store) {
          root.store.emitToast("no streams in subgraph", "info")
          root.store.applyEvent(Schema.makeOk(cmd.id, "muteSubgraph"))
        }
        return
      }
      for (var m = 0; m < ids.length; m++)
        root.dispatchArgv(Commands.mute(ids[m], cmd.mute !== false), cmd, m === ids.length - 1)
      return
    }
    if (op === "spawnSink") {
      var spec = Commands.spawnSink(cmd.name)
      root.enqueue(spec.primary, function (text, code) {
        if (code !== 0) {
          if (root.store)
            root.store.applyEvent(Schema.makeErr(cmd.id, "spawnSink", "exec", String(text || "pactl failed")))
          return
        }
        var moduleId = parseInt(String(text || "").trim(), 10)
        if (root.store) {
          var ev = Schema.makeOk(cmd.id, "spawnSink")
          ev.name = spec.sinkName
          if (isFinite(moduleId))
            ev.moduleId = moduleId
          root.store.applyEvent(ev)
        }
        Qt.callLater(function () { root.pollNow() })
      })
      return
    }
    if (op === "destroySink") {
      root.enqueue(Commands.listModules().primary, function (text) {
        var check = Commands.verifyDestroySink(cmd.name, cmd.moduleId, Commands.parsePactlShortModules(text))
        if (!check.ok) {
          if (root.store)
            root.store.applyEvent(Schema.makeErr(cmd.id, "destroySink", "denied", check.err))
          return
        }
        root.dispatchArgv(Commands.destroyModule(cmd.moduleId), cmd, true)
      })
      return
    }
    if (op === "cleanupOrphans") {
      var destroy = cmd.destroy === true
      root.enqueue(Commands.listModules().primary, function (text) {
        var plan = Commands.reconcileLoomModules(Commands.parsePactlShortModules(text), destroy)
        var adopted = plan.adopted || []
        if (!destroy) {
          if (root.store) {
            var ev = Schema.makeOk(cmd.id, "cleanupOrphans")
            ev.destroy = false
            ev.adopted = adopted
            ev.removed = []
            root.store.applyEvent(ev)
          }
          Qt.callLater(function () { root.pollNow() })
          return
        }
        root.unloadLoomModules(cmd, adopted, [], [])
      })
      return
    }
    if (op === "move") {
      if (root.store && (!Graph.findNode(root.store.raw, cmd.stream) || !Graph.findNode(root.store.raw, cmd.target))) {
        if (root.store)
          root.store.applyEvent(Schema.makeErr(cmd.id, "move", "gone"))
        return
      }
      var dst = Graph.findNode(root.store.raw, cmd.target)
      var key = cmd.targetSerial || cmd.targetName || Commands.targetKey(dst)
      if (!key) {
        if (root.store)
          root.store.applyEvent(Schema.makeErr(cmd.id, "move", "gone", "no serial or name"))
        return
      }
      var mv = Commands.move(cmd.stream, key)
      root.enqueue(mv.primary, function (text, code) {
        if (root.store)
          root.store.applyEvent(code === 0 ? Schema.makeOk(cmd.id, "move") : Schema.makeErr(cmd.id, "move", "exec", String(text || "")))
        Qt.callLater(function () { root.pollNow() })
      })
      return
    }
    var built = Commands.argvFor(op, cmd)
    if (!built) {
      if (root.store)
        root.store.applyEvent(Schema.makeErr(cmd.id, op, "unsupported"))
      return
    }
    root.dispatchArgv(built, cmd, true)
  }

  function unloadLoomModules(cmd, remaining, removed, failed) {
    if (!remaining.length) {
      if (failed.length) {
        if (root.store) {
          var err = Schema.makeErr(cmd.id, "cleanupOrphans", "exec", "unload failed")
          err.failed = failed
          err.removed = removed
          err.retained = failed
          root.store.applyEvent(err)
        }
      } else if (root.store) {
        var ev = Schema.makeOk(cmd.id, "cleanupOrphans")
        ev.destroy = true
        ev.adopted = []
        ev.removed = removed
        root.store.applyEvent(ev)
      }
      Qt.callLater(function () { root.pollNow() })
      return
    }
    var next = remaining[0]
    var rest = remaining.slice(1)
    root.enqueue(Commands.destroyModule(next.moduleId).primary, function (text, code) {
      if (code === 0)
        removed.push(next)
      else
        failed.push(next)
      root.unloadLoomModules(cmd, rest, removed, failed)
    })
  }

  function dispatchArgv(built, cmd, ack) {
    if (!built || !built.primary)
      return
    root.enqueue(built.primary, function (text, code) {
      if (code !== 0 && built.fallback) {
        root.enqueue(built.fallback, function (t2, c2) {
          if (ack && root.store)
            root.store.applyEvent(c2 === 0 ? Schema.makeOk(cmd.id, cmd.op) : Schema.makeErr(cmd.id, cmd.op, "exec", String(t2 || "")))
          Qt.callLater(function () { root.pollNow() })
        })
        return
      }
      if (ack && root.store)
        root.store.applyEvent(code === 0 ? Schema.makeOk(cmd.id, cmd.op) : Schema.makeErr(cmd.id, cmd.op, "exec", String(text || "")))
      Qt.callLater(function () { root.pollNow() })
    })
  }

  Process {
    id: workProc
    running: false
    stdout: StdioCollector {
      id: workOut
      waitForEnd: true
    }
    onExited: {
      var text = workOut.text
      var job = root.workCurrent
      root.workCurrent = null
      if (job && job.done) {
        try {
          job.done(text, exitCode)
        } catch (e) {
          console.warn("pipewire-loom: work failed", e)
        }
      }
      root.runWork()
    }
  }

  Process {
    id: whichProc
    command: ["sh", "-c", "test -x \"$1\" && echo binary || echo missing", "sh", root.loomdBin]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(text || "").trim()
        root.loomdPresent = out === "binary"
        root.probed = true
        if (root.loomdPresent)
          root.startDaemon()
        else
          root.useCli("no loomd")
      }
    }
  }

  Process {
    id: loomdProc
    running: false
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function (data) {
        root.ingestText(data)
      }
    }
    onExited: {
      if (root.mode !== "loomd-daemon")
        return
      root.crashes += 1
      if (root.crashes >= 3)
        root.useCli("loomd crashed 3×")
      else
        restartTimer.restart()
    }
  }

  Timer {
    id: helloTimer
    interval: 2000
    repeat: false
    onTriggered: {
      if (!root.waitingHello)
        return
      root.waitingHello = false
      if (loomdProc.running)
        loomdProc.running = false
      if (root.loomdPresent)
        root.useOneshot()
      else
        root.useCli("no hello")
    }
  }

  Timer {
    id: restartTimer
    interval: 400
    repeat: false
    onTriggered: root.startDaemon()
  }

  Timer {
    id: pollTimer
    interval: Math.max(250, root.pollMs)
    running: root.mode !== "loomd-daemon"
    repeat: true
    onTriggered: root.pollNow()
  }

  Component.onCompleted: {
    root.storm = Storm.create()
    whichProc.running = true
  }
}
