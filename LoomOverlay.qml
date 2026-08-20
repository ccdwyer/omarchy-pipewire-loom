import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "js/Layout.js" as Layout

Item {
  id: root

  property string moduleName: "io.github.chris.pipewire-loom"
  property var store: null
  property var theme: null
  property var shell: null
  Theme { id: tokens }
  readonly property var pal: theme ? theme : tokens
  property bool opened: false
  property bool showHelp: false
  property string dragKind: ""
  property var dragNode: null
  property var dragPort: null
  property real ghostX1: 0
  property real ghostY1: 0
  property real ghostX2: 0
  property real ghostY2: 0
  property bool ghostOn: false
  property real viewScale: 1
  property int spawnSerial: 0
  property string lastNameHint: "Mix"

  readonly property int motionMs: theme ? theme.motionMs : 150
  readonly property int themeMs: theme ? theme.themeMs : 200

  function open(payloadJson) {
    root.opened = true
    root.showHelp = false
    root.cancelDrag()
    if (root.store)
      root.store.requestDump()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.cancelDrag()
    root.opened = false
    root.showHelp = false
  }

  function toggle() {
    if (root.opened)
      root.close()
    else
      root.open("{}")
  }

  function cancelDrag() {
    root.dragKind = ""
    root.dragNode = null
    root.dragPort = null
    root.ghostOn = false
  }

  function nodeAt(gx, gy) {
    if (!root.store)
      return null
    var nodes = root.store.viewNodes || []
    for (var i = nodes.length - 1; i >= 0; i--) {
      var n = nodes[i]
      if (gx >= n.x && gx <= n.x + n.w && gy >= n.y && gy <= n.y + n.h)
        return n
    }
    return null
  }

  function portAt(gx, gy) {
    if (!root.store)
      return null
    var nodes = root.store.viewNodes || []
    var ports = root.store.viewPorts || []
    var byNode = {}
    var i
    for (i = 0; i < nodes.length; i++)
      byNode[nodes[i].id] = nodes[i]
    var best = null
    var bestD = 14
    for (i = 0; i < ports.length; i++) {
      var p = ports[i]
      if (p.monitor)
        continue
      var node = byNode[p.node]
      if (!node)
        continue
      var count = Layout.countDir(node, ports, p.dir)
      var idx = Layout.indexOfPort(node, ports, p.id, p.dir)
      var a = Layout.portAnchor(node, p, idx, count, p.dir)
      var dx = gx - a.x
      var dy = gy - a.y
      var d = Math.sqrt(dx * dx + dy * dy)
      if (d <= bestD) {
        bestD = d
        best = p
      }
    }
    return best
  }

  function handlePortReleased(gx, gy) {
    var p = root.portAt(gx, gy)
    if (p && (!root.dragPort || p.id !== root.dragPort.id)) {
      root.finishLinkToPort(p)
      return
    }
    var hit = root.nodeAt(gx, gy)
    if (hit)
      root.finishLinkToNode(hit)
    else
      root.cancelDrag()
  }

  function handleBodyPressed(nodeData) {
    if (root.store)
      root.store.select(nodeData.id)
    if (root.dragKind === "link-wait") {
      root.finishLinkToNode(nodeData)
      return
    }
    root.dragKind = "node"
    root.dragNode = nodeData
    if (root.store)
      root.store.dragging = true
  }

  function handleBodyDragged(nodeData, nx, ny) {
    if (root.dragKind !== "node" || !root.store)
      return
    if (nx < 0)
      nx = 0
    if (ny < 0)
      ny = 0
    root.store.persistPosition(nodeData.id, nx, ny, false)
    nodeData.x = nx
    nodeData.y = ny
  }

  function handleBodyReleased(nodeData) {
    if (root.dragKind === "node") {
      if (root.store) {
        // Persist the drop into viewNodes + positions, then redraw wires
        // from those same nodes. Do NOT rebuild() from raw here: that
        // relayouts to the default columns and snaps the cables back.
        root.store.persistPosition(nodeData.id, nodeData.x, nodeData.y, true)
        root.store.dragging = false
      }
      var target = root.nodeAt(nodeData.x + nodeData.w / 2, nodeData.y + nodeData.h / 2)
      // After a drag, also hit-test other nodes under the pointer via last ghost? 
      // Node-on-node move: if this node overlaps another sink, treat as drop.
      var nodes = (root.store && root.store.viewNodes) || []
      var hit = null
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].id === nodeData.id)
          continue
        var a = nodeData
        var b = nodes[i]
        var overlap = a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
        if (overlap)
          hit = b
      }
      if (hit && root.store)
        root.store.moveStream(nodeData.id, hit.id)
      root.cancelDrag()
    }
  }

  function handlePortPressed(port, gx, gy) {
    root.dragKind = "port"
    root.dragPort = port
    root.ghostOn = true
    root.ghostX1 = gx
    root.ghostY1 = gy
    root.ghostX2 = gx
    root.ghostY2 = gy
  }

  function finishLinkToNode(nodeData) {
    if (!root.store || !root.dragPort)
      return
    var fromNode = root.dragPort.node
    var toNode = nodeData.id
    if (root.dragPort.dir === "in") {
      fromNode = nodeData.id
      toNode = root.dragPort.node
    }
    var src = root.store.nodeById(fromNode)
    var dst = root.store.nodeById(toNode)
    var srcPlay = src && String(src.mediaClass || "").indexOf("Stream/Output") === 0
    var dstPlay = dst && String(dst.mediaClass || "").indexOf("Stream/Output") === 0
    var srcSink = src && (src.kind === "sink" || String(src.mediaClass || "").indexOf("Audio/Sink") === 0)
    var dstSink = dst && (dst.kind === "sink" || String(dst.mediaClass || "").indexOf("Audio/Sink") === 0)
    if (srcPlay && dstSink)
      root.store.moveStream(fromNode, toNode)
    else if (dstPlay && srcSink)
      root.store.moveStream(toNode, fromNode)
    else
      root.store.linkNodes(fromNode, toNode)
    root.cancelDrag()
  }

  function finishLinkToPort(port) {
    if (!root.store || !root.dragPort || !port)
      return
    var a = root.dragPort
    var b = port
    if (a.dir === b.dir) {
      root.store.emitToast("same direction", "warn")
      root.cancelDrag()
      return
    }
    var from = a.dir === "out" ? a.id : b.id
    var to = a.dir === "out" ? b.id : a.id
    root.store.linkPorts(from, to)
    root.cancelDrag()
  }

  function startLinkFromSelected() {
    if (!root.store)
      return
    var node = root.store.nodeById(root.store.selectedId)
    if (!node)
      return
    if (root.dragKind === "link-wait") {
      root.finishLinkToNode(node)
      return
    }
    var ports = root.store.viewPorts || []
    var out = null
    for (var i = 0; i < ports.length; i++) {
      if (ports[i].node === node.id && ports[i].dir === "out" && !ports[i].monitor) {
        out = ports[i]
        break
      }
    }
    if (!out) {
      root.store.emitToast("no output port", "info")
      return
    }
    root.dragKind = "link-wait"
    root.dragPort = out
    root.ghostOn = true
    var ac = 1
    var ap = { x: node.x + node.w, y: node.y + node.h / 2 }
    root.ghostX1 = ap.x
    root.ghostY1 = ap.y
    root.ghostX2 = ap.x + 40
    root.ghostY2 = ap.y
  }

  function onKey(event) {
    if (!root.store)
      return
    var k = event.key
    var ch = event.text
    if (k === Qt.Key_Escape) {
      if (root.dragKind) {
        root.cancelDrag()
        event.accepted = true
        return
      }
      if (root.showHelp) {
        root.showHelp = false
        event.accepted = true
        return
      }
      root.close()
      event.accepted = true
      return
    }
    if (k === Qt.Key_Question || ch === "?") {
      root.showHelp = !root.showHelp
      event.accepted = true
      return
    }
    if (k === Qt.Key_Tab) {
      root.store.toggleSimple()
      event.accepted = true
      return
    }
    if (k === Qt.Key_H || k === Qt.Key_Left) {
      root.store.selectDelta(-1, 0)
      event.accepted = true
      return
    }
    if (k === Qt.Key_L || k === Qt.Key_Right) {
      root.store.selectDelta(1, 0)
      event.accepted = true
      return
    }
    if (k === Qt.Key_K || k === Qt.Key_Up) {
      root.store.selectDelta(0, -1)
      event.accepted = true
      return
    }
    if (k === Qt.Key_J || k === Qt.Key_Down) {
      root.store.selectDelta(0, 1)
      event.accepted = true
      return
    }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      root.startLinkFromSelected()
      event.accepted = true
      return
    }
    if (ch === "m" || k === Qt.Key_M) {
      root.store.muteSubgraph()
      event.accepted = true
      return
    }
    if (ch === "n" || k === Qt.Key_N) {
      if (root.store.virtualSinks)
        root.store.spawnSink(root.lastNameHint)
      else
        root.store.emitToast("virtual sinks disabled", "info")
      event.accepted = true
      return
    }
    if (ch === "x" || k === Qt.Key_X || k === Qt.Key_Backspace || k === Qt.Key_Delete) {
      root.store.unlinkSelected()
      event.accepted = true
      return
    }
    if (ch === "+" || k === Qt.Key_Plus || k === Qt.Key_Equal) {
      root.store.nudgeVolume(0.05)
      event.accepted = true
      return
    }
    if (ch === "-" || k === Qt.Key_Minus) {
      root.store.nudgeVolume(-0.05)
      event.accepted = true
      return
    }
  }

  Connections {
    target: root.store
    function onGone() { root.cancelDrag() }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "pipewire-loom"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.pal.scrim
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: root.motionMs } }
      Behavior on color { ColorAnimation { duration: root.themeMs } }
      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }
    }

    BorderSurface {
      id: stage
      width: Math.min(panel.width - (root.theme ? root.theme.gapsOut * 2 : 32), 1280)
      height: Math.min(panel.height - (root.theme ? root.theme.gapsOut * 2 : 32), 780)
      anchors.centerIn: parent
      radius: root.theme ? root.theme.radius : 10
      color: root.pal.bg
      borderSpec: root.theme ? root.theme.borderSpec : null
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.98
      Behavior on opacity { NumberAnimation { duration: root.motionMs } }
      Behavior on scale { NumberAnimation { duration: root.motionMs } }
      Behavior on color { ColorAnimation { duration: root.themeMs } }

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) { root.onKey(event) }
      }

      Column {
        anchors.fill: parent
        anchors.margins: root.theme ? root.theme.pad : 16
        spacing: 8

        Row {
          id: header
          width: parent.width
          height: 28
          spacing: 12

          Text {
            text: "PipeWire Loom"
            color: root.pal.text
            font.family: root.theme ? root.theme.fontFamily : "sans-serif"
            font.pixelSize: root.theme ? root.theme.fontHeading : 16
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: root.themeMs } }
          }

          Text {
            text: root.store
                  ? ((root.store.simpleView ? "simple" : "full")
                     + " · " + root.store.streamCount + " live"
                     + " · " + (root.store.viewLinks ? root.store.viewLinks.length : 0) + " wires")
                  : ""
            color: root.pal.muted
            font.family: root.theme ? root.theme.fontFamily : "sans-serif"
            font.pixelSize: root.theme ? root.theme.fontSmall : 11
            anchors.verticalCenter: parent.verticalCenter
          }

          Rectangle {
            visible: root.store && root.store.compatMode
            width: compatLabel.width + 12
            height: 20
            radius: 6
            color: "transparent"
            border.width: 1
            border.color: root.pal.muted
            anchors.verticalCenter: parent.verticalCenter
            Text {
              id: compatLabel
              anchors.centerIn: parent
              text: "compat mode"
              color: root.pal.muted
              font.family: root.theme ? root.theme.fontFamily : "sans-serif"
              font.pixelSize: 10
            }
          }

          Item { width: 8; height: 1 }

          Text {
            text: "Tab view  ·  m mute"
                   + (root.store && root.store.virtualSinks ? "  ·  n sink" : "")
                   + "  ·  ? keys  ·  Esc"
            color: root.pal.muted
            font.family: root.theme ? root.theme.fontFamily : "sans-serif"
            font.pixelSize: root.theme ? root.theme.fontSmall : 11
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Item {
          width: parent.width
          height: parent.height - 36

          Flickable {
            id: flick
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: Math.max(width, ((root.store && root.store.canvasW) || 960) * root.viewScale)
            contentHeight: Math.max(height, ((root.store && root.store.canvasH) || 640) * root.viewScale)
            interactive: root.dragKind === ""

            Item {
              id: canvas
              width: (root.store && root.store.canvasW) || 960
              height: (root.store && root.store.canvasH) || 640
              scale: root.viewScale
              transformOrigin: Item.TopLeft

              readonly property var wireModel: {
                var _ = root.store ? root.store.revision : 0
                return (root.store && root.store.wires) ? root.store.wires : []
              }
              // Do not key nodes on revision: persistPosition bumps it every
              // drag pixel to refresh wires, and recreating boxes steals the grab.
              readonly property var nodeModel: (root.store && root.store.viewNodes) ? root.store.viewNodes : []

              // Wires under nodes.
              Repeater {
                model: canvas.wireModel
                delegate: Item {
                  required property var modelData
                  x: 0
                  y: 0
                  width: canvas.width
                  height: canvas.height
                  Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.GeometryRenderer
                    opacity: modelData.muted ? 0.32 : 1
                    ShapePath {
                      strokeWidth: modelData.live ? 2.6 : 1.4
                      strokeColor: root.pal.accent
                      fillColor: "transparent"
                      strokeStyle: modelData.raw ? ShapePath.DashLine : ShapePath.SolidLine
                      dashPattern: [5, 4]
                      capStyle: ShapePath.RoundCap
                      startX: modelData.x1
                      startY: modelData.y1
                      PathCubic {
                        x: modelData.x2
                        y: modelData.y2
                        control1X: modelData.x1 + Math.max(40, Math.abs(modelData.x2 - modelData.x1) * 0.45)
                        control1Y: modelData.y1
                        control2X: modelData.x2 - Math.max(40, Math.abs(modelData.x2 - modelData.x1) * 0.45)
                        control2Y: modelData.y2
                      }
                      Behavior on strokeColor { ColorAnimation { duration: root.themeMs } }
                    }
                  }
                  Text {
                    visible: modelData.latencyMs !== undefined && modelData.latencyMs !== null
                    x: (modelData.x1 + modelData.x2) / 2 - width / 2
                    y: (modelData.y1 + modelData.y2) / 2 - height / 2
                    text: "buf ≈ " + Number(modelData.latencyMs).toFixed(1) + "ms"
                    color: root.pal.muted
                    font.family: root.pal.fontFamily
                    font.pixelSize: root.pal.fontSmall
                  }
                }
              }

              Shape {
                visible: root.ghostOn
                width: canvas.width
                height: canvas.height
                preferredRendererType: Shape.GeometryRenderer
                ShapePath {
                  strokeWidth: 2
                  strokeColor: root.pal.accent
                  fillColor: "transparent"
                  strokeStyle: ShapePath.DashLine
                  dashPattern: [4, 4]
                  startX: root.ghostX1
                  startY: root.ghostY1
                  PathCubic {
                    x: root.ghostX2
                    y: root.ghostY2
                    control1X: root.ghostX1 + 60
                    control1Y: root.ghostY1
                    control2X: root.ghostX2 - 60
                    control2Y: root.ghostY2
                  }
                }
              }

              Repeater {
                id: nodeRepeater
                model: canvas.nodeModel
                delegate: NodeDelegate {
                  required property var modelData
                  required property int index
                  theme: root.theme
                  store: root.store
                  nodeData: modelData
                  ports: root.store ? root.store.viewPorts : []
                  selected: root.store && root.store.selectedId === modelData.id
                  highlightPortIds: root.store ? root.store.highlightPortIds : []
                  opacity: 1
                  Component.onCompleted: {
                    if (root.theme && root.theme.reduceMotion)
                      return
                    opacity = 0
                    appear.interval = Math.min(index * 8, 120)
                    appear.start()
                  }
                  Timer {
                    id: appear
                    interval: 0
                    repeat: false
                    onTriggered: parent.opacity = 1
                  }
                  onBodyPressed: function (n) { root.handleBodyPressed(n) }
                  onBodyDragged: function (n, nx, ny) { root.handleBodyDragged(n, nx, ny) }
                  onBodyReleased: function (n) { root.handleBodyReleased(n) }
                  onPortPressed: function (p, gx, gy) { root.handlePortPressed(p, gx, gy) }
                  onPortMoved: function (gx, gy) {
                    root.ghostX2 = gx
                    root.ghostY2 = gy
                  }
                  onPortReleased: function (p, gx, gy) {
                    if (root.dragKind === "port" || root.dragKind === "link-wait")
                      root.handlePortReleased(gx, gy)
                  }
                  onDroppedOn: function (n) {
                    if (root.dragKind === "port")
                      root.finishLinkToNode(n)
                  }
                }
              }

              MouseArea {
                id: canvasDrag
                anchors.fill: parent
                // Keyboard link-wait has no port grab; this overlay tracks
                // the pointer. Port drags keep their own MouseArea (no
                // preventStealing) and map ev.x/ev.y into canvas coords.
                enabled: root.dragKind === "link-wait"
                hoverEnabled: enabled
                acceptedButtons: Qt.LeftButton
                z: 20
                onPositionChanged: function (ev) {
                  root.ghostX2 = ev.x
                  root.ghostY2 = ev.y
                }
                onReleased: function (ev) {
                  root.handlePortReleased(ev.x, ev.y)
                }
              }
            }
          }

          MouseArea {
            anchors.fill: flick
            acceptedButtons: Qt.NoButton
            onWheel: function (ev) {
              if (ev.modifiers & Qt.ControlModifier) {
                var s = root.viewScale + (ev.angleDelta.y > 0 ? 0.1 : -0.1)
                if (s < 0.4)
                  s = 0.4
                if (s > 2.2)
                  s = 2.2
                root.viewScale = s
                ev.accepted = true
              }
            }
          }

          Text {
            visible: root.store && root.store.emptyGraph
            anchors.centerIn: parent
            text: "No audio streams — play something"
            color: root.pal.muted
            font.family: root.theme ? root.theme.fontFamily : "sans-serif"
            font.pixelSize: root.theme ? root.theme.fontHeading : 16
          }

          Rectangle {
            visible: root.store && root.store.lastToast.length && root.store.toastSerial > 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            width: toastText.width + 20
            height: 28
            radius: 8
            color: root.pal.surface
            border.width: 1
            border.color: root.pal.border
            Text {
              id: toastText
              anchors.centerIn: parent
              text: root.store ? root.store.lastToast : ""
              color: root.pal.text
              font.family: root.theme ? root.theme.fontFamily : "sans-serif"
              font.pixelSize: root.theme ? root.theme.fontSmall : 11
            }
          }

          HelpOverlay {
            visible: root.showHelp
            theme: root.theme
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
          }
        }
      }
    }
  }
}
