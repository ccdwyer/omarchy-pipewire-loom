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
  property bool bindScanned: false
  property bool bindMenuOpen: false
  property string offerNote: ""
  property string bindKeys: ""
  property string bindSuggested: ""
  property string bindChangeTo: ""
  property var workQueue: []
  property var workCurrent: null
  readonly property string pluginId: "io.github.chris.pipewire-loom"
  readonly property string bindPretty: Binds.humanKeys(root.bindKeys)
  readonly property string suggestedPretty: Binds.humanKeys(root.bindSuggested)
  readonly property string changePretty: Binds.humanKeys(root.bindChangeTo)

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
    root.bindKeys = String(p.current || "")
    root.bindSuggested = String(p.suggested || "")
    root.bindChangeTo = String(p.changeTo || "")
    root.bindScanned = true
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
      root.applyBindPlan(Binds.applyScan(text))
    })
  }

  function notifyNewBinds(plan) {
    var body = Binds.notifyBody(plan.toAdd || plan.items || [], plan.skipped)
    if (!body)
      return
    Quickshell.execDetached(Binds.notifyArgv("PipeWire Loom", "PipeWire Loom keybindings", body))
  }

  function writeLuaBlock(lua, items, skipped) {
    enqueueWork(["python3", root.pluginDir + "/compat/install-binds.py", root.pluginId, lua], function(out, instCode) {
      if (Number(instCode) !== 0) {
        root.offerNote = "could not write ~/.config/hypr/bindings.lua"
        return
      }
      root.notifyNewBinds({ toAdd: items || [], skipped: skipped || [] })
      root.bindMenuOpen = false
      Qt.callLater(root.scanBinds)
    })
  }

  function installBinds(arg) {
    var mode = String(arg || "")
    if (mode === "remove")
      return root.removeBinds()
    if (mode === "change")
      return root.changeBinds()
    enqueueWork(["hyprctl", "-j", "binds"], function(text, code) {
      if (Number(code) !== 0) {
        root.offerNote = "could not read keybinds"
        return
      }
      var plan = Binds.applyScan(text)
      root.applyBindPlan(plan)
      if (!plan.toAdd || !plan.toAdd.length) {
        root.bindMenuOpen = true
        return
      }
      root.writeLuaBlock(Binds.luaBlock(plan.toAdd), plan.toAdd, plan.skipped)
    })
    return "ok"
  }

  function changeBinds() {
    enqueueWork(["hyprctl", "-j", "binds"], function(text, code) {
      if (Number(code) !== 0) {
        root.offerNote = "could not read keybinds"
        return
      }
      var plan = Binds.applyScan(text)
      root.applyBindPlan(plan)
      if (!plan.changeItem) {
        root.offerNote = root.offerNote || "no free combo to change to"
        root.bindMenuOpen = true
        return
      }
      root.writeLuaBlock(Binds.luaBlock([plan.changeItem]), [plan.changeItem], [])
    })
    return "ok"
  }

  function removeBinds() {
    enqueueWork(["python3", root.pluginDir + "/compat/install-binds.py", "--remove", root.pluginId], function(out, instCode) {
      if (Number(instCode) !== 0) {
        root.offerNote = "could not update ~/.config/hypr/bindings.lua"
        return
      }
      root.bindMenuOpen = false
      Qt.callLater(root.scanBinds)
    })
    return "ok"
  }

  function onKeysChipPressed(buttonCode) {
    if (buttonCode === Qt.RightButton) {
      root.bindMenuOpen = !root.bindMenuOpen
      return
    }
    if (buttonCode !== Qt.LeftButton)
      return
    if (root.offerBinds && root.bindSuggested && !root.bindMenuOpen)
      root.installBinds("")
    else
      root.bindMenuOpen = !root.bindMenuOpen
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

  // qs.Ui exports a type named Panel (host bar-popout). Instantiating
  // that type, or loading a bare "Panel.qml" path, hits the host popout,
  // so Super+Shift+L toggled qs.Ui.Panel.opened and never mapped
  // pipewire-loom. LoomOverlay.qml is a unique filename to avoid that.
  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("LoomOverlay.qml")
    onLoaded: {
      if (!item || item.store === undefined) {
        console.warn("pipewire-loom: overlay loader did not get LoomOverlay")
        return
      }
      item.store = store
      item.theme = theme
      item.shell = root.shell
    }
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
                      + (store.captureLive ? " · capture live" : "")
                      + (root.bindScanned
                         ? (root.offerBinds
                            ? " · no hotkey"
                            : (root.bindPretty ? (" · " + root.bindPretty) : ""))
                         : ""))
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

    WidgetButton {
      id: keysChip
      visible: root.bindScanned
      bar: root.bar
      active: root.bindMenuOpen
      text: root.offerBinds ? "Set hotkey" : (root.bindPretty || "hotkey")
      tooltipText: root.offerBinds
                   ? (root.suggestedPretty
                      ? ("Set " + root.suggestedPretty + " — Omarchy uses Super+L for layout and Super+Shift+A for ChatGPT")
                      : (root.offerNote || "No free suggested combo"))
                   : (root.bindPretty + " — click to change or remove")
      onPressed: function (buttonCode) {
        root.onKeysChipPressed(buttonCode)
      }
    }
  }

  QtObject {
    id: bindMenuOwner
    function close() { root.bindMenuOpen = false }
  }

  PopupCard {
    id: bindMenu
    anchorItem: keysChip
    bar: root.bar
    owner: bindMenuOwner
    open: root.bindMenuOpen
    contentWidth: bindMenu.fittedContentWidth(Style.space(280))
    contentHeight: bindMenu.fittedContentHeight(bindCol.implicitHeight)

    Column {
      id: bindCol
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        text: "PipeWire Loom hotkey"
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: root.offerBinds
              ? (root.suggestedPretty
                 ? ("Not set. Suggested " + root.suggestedPretty + ".")
                 : (root.offerNote || "Not set."))
              : ("Current: " + (root.bindPretty || "set"))
        color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.3)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        visible: root.offerBinds
        text: "Omarchy already uses Super+L for layout and Super+Shift+A for ChatGPT. This plugin never unbinds someone else's key."
        color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }

      Button {
        visible: root.offerBinds && root.bindSuggested.length > 0
        text: "Set " + root.suggestedPretty
        foreground: root.bar ? root.bar.foreground : Color.foreground
        onClicked: root.installBinds("")
      }

      Button {
        visible: !root.offerBinds && root.bindChangeTo.length > 0
        text: "Change to " + root.changePretty
        foreground: root.bar ? root.bar.foreground : Color.foreground
        onClicked: root.changeBinds()
      }

      Button {
        visible: !root.offerBinds && root.bindKeys.length > 0
        text: "Remove hotkey"
        foreground: root.bar ? root.bar.foreground : Color.foreground
        onClicked: root.removeBinds()
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
    function removeBinds(arg: string): string { return root.removeBinds() }
    function changeBinds(arg: string): string { return root.changeBinds() }
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
        bindOfferNote: root.offerNote,
        hotkey: root.bindKeys,
        hotkeySuggested: root.bindSuggested
      })
    }
  }

  Component.onCompleted: Qt.callLater(root.scanBinds)
}
