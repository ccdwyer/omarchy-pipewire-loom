import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: node

  property var theme: null
  Theme { id: tokens }
  readonly property var pal: theme ? theme : tokens
  property var store: null
  property var nodeData: ({})
  property var ports: []
  property bool selected: false
  property var highlightPortIds: []

  property int motionMs: theme ? theme.motionMs : 150
  property int themeMs: theme ? theme.themeMs : 200

  signal bodyPressed(var nodeData, real mx, real my)
  signal bodyDragged(var nodeData, real nx, real ny)
  signal bodyReleased(var nodeData)
  signal portPressed(var port, real gx, real gy)
  signal portMoved(real gx, real gy)
  signal portReleased(var port, real gx, real gy)
  signal droppedOn(var nodeData)

  width: nodeData && nodeData.w ? nodeData.w : 196
  height: nodeData && nodeData.h ? nodeData.h : 88
  opacity: 1
  z: body.drag.active ? 20 : 0

  function applyLayout() {
    if (body && body.drag && body.drag.active)
      return
    x = (nodeData && nodeData.x !== undefined) ? nodeData.x : 0
    y = (nodeData && nodeData.y !== undefined) ? nodeData.y : 0
    width = (nodeData && nodeData.w) ? nodeData.w : 196
    height = (nodeData && nodeData.h) ? nodeData.h : 88
  }

  onNodeDataChanged: applyLayout()
  Component.onCompleted: applyLayout()

  readonly property color surface: pal.surface
  readonly property color text: pal.text
  readonly property color muted: pal.muted
  readonly property color accent: pal.accent
  readonly property color border: pal.border
  readonly property int radius: theme ? theme.radius : 10

  readonly property var inPorts: {
    var list = []
    var id = nodeData && nodeData.id
    for (var i = 0; i < (ports || []).length; i++) {
      if (ports[i].node === id && ports[i].dir === "in" && !ports[i].monitor)
        list.push(ports[i])
    }
    return list
  }
  readonly property var outPorts: {
    var list = []
    var id = nodeData && nodeData.id
    for (var i = 0; i < (ports || []).length; i++) {
      if (ports[i].node === id && ports[i].dir === "out" && !ports[i].monitor)
        list.push(ports[i])
    }
    return list
  }

  Behavior on opacity { NumberAnimation { duration: node.motionMs } }

  Rectangle {
    id: chrome
    anchors.fill: parent
    radius: node.radius
    color: node.selected ? pal.selectedBg : node.surface
    border.width: node.selected ? 2 : 1
    border.color: node.selected ? node.accent : node.border
    Behavior on color { ColorAnimation { duration: node.themeMs } }
    Behavior on border.color { ColorAnimation { duration: node.themeMs } }

    Rectangle {
      visible: nodeData && nodeData.state === "running"
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 3
      radius: 2
      color: node.accent
      opacity: nodeData && nodeData.mute ? 0.3 : 1
      Behavior on color { ColorAnimation { duration: node.themeMs } }
    }
  }

  MouseArea {
    id: body
    // Title strip only — a full-card drag.target steals port-to-port drawing.
    height: 40
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    preventStealing: true
    drag.target: node
    drag.axis: Drag.XAndYAxis
    drag.threshold: 4
    drag.minimumX: 0
    drag.minimumY: 0
    drag.smoothed: false
    onPressed: function (ev) {
      node.bodyPressed(node.nodeData, ev.x, ev.y)
    }
    onPositionChanged: function (ev) {
      if (!body.drag.active)
        return
      node.bodyDragged(node.nodeData, node.x, node.y)
    }
    onReleased: function (ev) {
      // drag.active is already false here; still persist the Item's x/y.
      node.bodyDragged(node.nodeData, node.x, node.y)
      node.bodyReleased(node.nodeData)
    }
    onClicked: function (ev) {
      if (ev.button === Qt.RightButton && node.store)
        node.store.select(node.nodeData.id)
    }
  }

  DropArea {
    anchors.fill: parent
    onDropped: node.droppedOn(node.nodeData)
  }

  Column {
    anchors.fill: parent
    anchors.leftMargin: 12
    anchors.rightMargin: 12
    anchors.topMargin: 8
    anchors.bottomMargin: 8
    spacing: 2

    Text {
      width: parent.width
      text: (nodeData && (nodeData.nick || nodeData.app || nodeData.name)) || "node"
      textFormat: Text.PlainText
      color: node.text
      elide: Text.ElideRight
      font.family: theme ? theme.fontFamily : "sans-serif"
      font.pixelSize: theme ? theme.fontBody : 13
      font.bold: true
      Behavior on color { ColorAnimation { duration: node.themeMs } }
    }

    Text {
      width: parent.width
      text: {
        var bits = []
        if (nodeData && nodeData.app && nodeData.nick && nodeData.app !== nodeData.nick)
          bits.push(nodeData.app)
        if (nodeData && nodeData.kind)
          bits.push(nodeData.kind)
        if (nodeData && nodeData.isDefault)
          bits.push("default")
        if (nodeData && nodeData.isLoom)
          bits.push("loom")
        if (nodeData && nodeData.mute)
          bits.push("muted")
        return bits.join(" · ")
      }
      textFormat: Text.PlainText
      color: node.muted
      elide: Text.ElideRight
      font.family: theme ? theme.fontFamily : "sans-serif"
      font.pixelSize: theme ? theme.fontSmall : 11
    }

    Text {
      visible: body.containsMouse || node.selected
      width: parent.width
      text: nodeData ? ("vol " + Math.round((nodeData.volume || 0) * 100) + "%") : ""
      color: node.muted
      font.family: theme ? theme.fontFamily : "sans-serif"
      font.pixelSize: theme ? theme.fontSmall : 11
    }
  }

  Repeater {
    model: node.inPorts
    delegate: Item {
      required property var modelData
      required property int index
      width: 24
      height: 24
      x: -12
      y: node.portY(index, node.inPorts.length)
      z: 8
      Rectangle {
        anchors.centerIn: parent
        width: 10
        height: 10
        radius: 5
        color: node.portHighlighted(modelData.id) ? node.accent : node.surface
        border.width: 2
        border.color: node.portHighlighted(modelData.id) ? node.text : node.accent
        Behavior on color { ColorAnimation { duration: node.themeMs } }
      }
      MouseArea {
        anchors.fill: parent
        preventStealing: true
        onPressed: function (ev) {
          var p = mapToItem(node.parent, ev.x, ev.y)
          node.portPressed(modelData, p.x, p.y)
        }
        onPositionChanged: function (ev) {
          if (!(ev.buttons & Qt.LeftButton))
            return
          var p = mapToItem(node.parent, ev.x, ev.y)
          node.portMoved(p.x, p.y)
        }
        onReleased: function (ev) {
          var p = mapToItem(node.parent, ev.x, ev.y)
          node.portReleased(modelData, p.x, p.y)
        }
      }
    }
  }

  Repeater {
    model: node.outPorts
    delegate: Item {
      required property var modelData
      required property int index
      width: 24
      height: 24
      x: node.width - 12
      y: node.portY(index, node.outPorts.length)
      z: 8
      Rectangle {
        anchors.centerIn: parent
        width: 10
        height: 10
        radius: 5
        color: node.portHighlighted(modelData.id) ? node.accent : node.surface
        border.width: 2
        border.color: node.portHighlighted(modelData.id) ? node.text : node.accent
        Behavior on color { ColorAnimation { duration: node.themeMs } }
      }
      MouseArea {
        anchors.fill: parent
        preventStealing: true
        onPressed: function (ev) {
          var p = mapToItem(node.parent, ev.x, ev.y)
          node.portPressed(modelData, p.x, p.y)
        }
        onPositionChanged: function (ev) {
          if (!(ev.buttons & Qt.LeftButton))
            return
          var p = mapToItem(node.parent, ev.x, ev.y)
          node.portMoved(p.x, p.y)
        }
        onReleased: function (ev) {
          var p = mapToItem(node.parent, ev.x, ev.y)
          node.portReleased(modelData, p.x, p.y)
        }
      }
    }
  }

  function portY(index, count) {
    var n = count < 1 ? 1 : count
    var top = (node.height - n * 24) / 2
    if (top < 24)
      top = 24
    return top + index * 24
  }

  function portHighlighted(id) {
    var ids = node.highlightPortIds || []
    for (var i = 0; i < ids.length; i++) {
      if (ids[i] === id)
        return true
    }
    return false
  }
}
