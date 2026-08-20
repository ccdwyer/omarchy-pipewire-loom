import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

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

  Theme { id: theme }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.stateHome]
    running: true
    onExited: {
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

  implicitWidth: chip.implicitWidth
  implicitHeight: chip.implicitHeight

  WidgetButton {
    id: chip
    anchors.fill: parent
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

  IpcHandler {
    target: "io.github.chris.pipewire-loom"

    function open(arg: string): string { root.open(arg && arg.length ? arg : "{}"); return "ok" }
    function close(arg: string): string { root.close(); return "ok" }
    function toggle(arg: string): string { root.toggle(arg && arg.length ? arg : "{}"); return "ok" }
    function summon(arg: string): string { root.open(arg && arg.length ? arg : "{}"); return "ok" }
    function ping(arg: string): string { return "ok" }
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
        simple: store.simpleView
      })
    }
  }
}
