import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "js/Binds.js" as Binds

BarWidget {
  id: root
  moduleName: "io.github.chris.pipewire-loom"

  // Inline shell.json settings (Quattro: no config file of our own).
  property bool simpleView: true
  property int pollMs: 1000
  property bool virtualSinks: false

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || ""
  property bool offerBinds: false
  property string offerNote: ""
  property var workQueue: []
  property var workCurrent: null
  readonly property string pluginId: "io.github.chris.pipewire-loom"

  readonly property string pluginDir: {
    var u = String(Qt.resolvedUrl("."))
    if (u.indexOf("file://") === 0)
      u = u.slice(7)
    if (u.length > 1 && u.charAt(u.length - 1) === "/")
      u = u.slice(0, u.length - 1)
    return u
  }
  readonly property string home: Quickshell.env("HOME") || "/tmp"
  readonly property string stateHome: {
    var xdg = Quickshell.env("XDG_STATE_HOME")
    if (xdg && xdg.length)
      return xdg + "/pipewire-loom"
    return home + "/.local/state/pipewire-loom"
  }

  readonly property bool opened: panelLoader.item ? !!panelLoader.item.opened : false

  function open(payloadJson) {
    if (panelLoader.item)
      panelLoader.item.open(payloadJson || "{}")
  }
  function close() {
    if (panelLoader.item)
      panelLoader.item.close()
  }
  function toggle(payloadJson) {
    if (root.opened)
      root.close()
    else
      root.open(payloadJson || "{}")
  }

  function applyBindPlan(plan) {
    var p = plan || Binds.offer
    root.offerBinds = !!p.needed
    root.offerNote = String(p.note || "")
    Binds.setOffer(p)
  }

  function enqueueWork(command, done) {
    workQueue.push({ command: command, done: done || null })
    runWork()
  }

  function runWork() {
    if (workProc.running || root.workCurrent)
      return
    if (!workQueue.length)
      return
    root.workCurrent = workQueue.shift()
    workProc.command = root.workCurrent.command
    workProc.running = true
  }

  function scanBinds() {
    enqueueWork(["hyprctl", "-j", "binds"], function(text, code) {
      if (Number(code) !== 0)
        return
      var plan = Binds.applyScan(text)
      root.applyBindPlan(plan)
      if (plan.needed && plan.toAdd && plan.toAdd.length && Binds.claimAuto())
        root.installBinds("auto")
    })
  }

  function notifyNewBinds(plan) {
    var body = Binds.notifyBody(plan.toAdd, plan.skipped)
    if (!body)
      return
    Quickshell.execDetached(Binds.notifyArgv("PipeWire Loom", "PipeWire Loom keybindings", body))
  }

  function installBinds(arg) {
    enqueueWork(["hyprctl", "-j", "binds"], function(text, code) {
      if (Number(code) !== 0) {
        root.offerNote = "could not read keybinds"
        return
      }
      var plan = Binds.applyScan(text)
      if (!plan.toAdd || !plan.toAdd.length) {
        root.applyBindPlan(plan)
        return
      }
      var lua = Binds.luaBlock(plan.toAdd)
      enqueueWork(["python3", root.pluginDir + "/compat/install-binds.py", root.pluginId, lua], function(out, instCode) {
        if (Number(instCode) !== 0) {
          root.offerNote = "could not write ~/.config/hypr/bindings.lua"
          return
        }
        root.notifyNewBinds(plan)
        Qt.callLater(root.scanBinds)
      })
    })
    return "ok"
  }

  Theme { id: theme }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.stateHome]
    running: true
    onExited: function() {
      store.statePath = root.stateHome + "/state.json"
    }
  }

  GraphStore {
    id: store
    statePath: ""
    simpleView: root.simpleView
    virtualSinks: root.virtualSinks
    backend: backend
  }

  Backend {
    id: backend
    store: store
    pluginDir: root.pluginDir
    pollMs: root.pollMs
    panelOpen: root.opened
  }

  Loader {
    id: panelLoader
    active: true
    sourceComponent: panelComp
    onLoaded: {
      if (item) {
        item.store = store
        item.theme = theme
        item.shell = root.shell
      }
    }
  }

  Component {
    id: panelComp
    Panel {}
  }

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    spacing: Style.space(4)

  WidgetButton {
    id: chip
    bar: root.bar
    text: store.streamCount > 0
          ? ("🎚 " + store.defaultSinkNick + " · " + store.streamCount)
          : ("🎚 " + store.defaultSinkNick)
    tooltipText: root.opened
                 ? "Hide PipeWire Loom"
                 : ("Loom — " + store.defaultSinkNick
                    + (store.compatMode ? " (compat)" : "")
                    + (store.captureLive ? " · capture live" : ""))
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton)
        root.toggle()
      else if (buttonCode === Qt.RightButton)
        store.toggleSimple()
    }

    Rectangle {
      visible: store.captureLive
      width: 7
      height: 7
      radius: 4
      color: theme.danger
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: 2
      anchors.topMargin: 2
      z: 2
    }
  }
  }

  Process {
    id: workProc
    running: false
    stdout: StdioCollector {
      id: workOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var text = workOut.text
      var job = root.workCurrent
      root.workCurrent = null
      if (job && job.done) {
        try {
          job.done(text, exitCode)
        } catch (e) {
          console.warn("pipewire-loom: work callback failed", e)
        }
      }
      root.runWork()
    }
  }

  Timer {
    id: bindScanTimer
    interval: 3000
    repeat: true
    running: true
    onTriggered: root.scanBinds()
  }

  IpcHandler {
    target: "io.github.chris.pipewire-loom"

    function open(arg: string): string { root.open(arg && arg.length ? arg : "{}"); return "ok" }
    function close(arg: string): string { root.close(); return "ok" }
    function toggle(arg: string): string { root.toggle(arg && arg.length ? arg : "{}"); return "ok" }
    function summon(arg: string): string { root.open(arg && arg.length ? arg : "{}"); return "ok" }
    function ping(arg: string): string { return "ok" }
    function installBinds(arg: string): string { return root.installBinds(arg) }
    function mute(arg: string): string { return store.muteSubgraph() }
    function spawnSink(arg: string): string { return store.spawnSink(arg) }
    function dump(arg: string): string { store.requestDump(); return "ok" }
    function status(arg: string): string {
      return JSON.stringify({
        opened: root.opened,
        backend: store.backendName,
        compat: store.compatMode,
        streams: store.streamCount,
        capture: store.captureLive,
        sink: store.defaultSinkNick,
        gen: store.gen,
        simple: store.simpleView,
        bindOfferNeeded: root.offerBinds,
        bindOfferNote: root.offerNote
      })
    }
  }

  Component.onCompleted: Qt.callLater(root.scanBinds)
}
