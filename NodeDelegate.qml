import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: node

  property var theme: null
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
  signal droppedOn(var nodeData)

  width: nodeData && nodeData.w ? nodeData.w : 196
  height: nodeData && nodeData.h ? nodeData.h : 88
  x: nodeData && nodeData.x !== undefined ? nodeData.x : 0
  y: nodeData && nodeData.y !== undefined ? nodeData.y : 0
  opacity: 1

  readonly property color surface: theme ? theme.surface : "#1c1c1c"
  readonly property color text: theme ? theme.text : "#f2f2f2"
  readonly property color muted: theme ? theme.muted : "#888"
  readonly property color accent: theme ? theme.accent : "#c8a46b"
  readonly property color border: theme ? theme.border : "#3a3a3a"
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
    color: node.selected ? (theme ? theme.selectedBg : "#2a2a2a") : node.surface
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
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    preventStealing: true
    property real grabX: 0
    property real grabY: 0
    property bool dragging: false
    onPressed: function (ev) {
      body.grabX = ev.x
      body.grabY = ev.y
      body.dragging = false
      node.bodyPressed(node.nodeData, ev.x, ev.y)
    }
    onPositionChanged: function (ev) {
      if (!(ev.buttons & Qt.LeftButton))
        return
      var dx = ev.x - body.grabX
      var dy = ev.y - body.grabY
      if (!body.dragging && (Math.abs(dx) + Math.abs(dy) < 4))
        return
      body.dragging = true
      node.bodyDragged(node.nodeData, node.x + dx, node.y + dy)
    }
    onReleased: function (ev) {
      node.bodyReleased(node.nodeData)
      body.dragging = false
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
        onPressed: {
          var p = node.mapToItem(node.parent, width / 2, height / 2)
          node.portPressed(modelData, p.x, p.y)
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
        onPressed: {
          var p = node.mapToItem(node.parent, width / 2, height / 2)
          node.portPressed(modelData, p.x, p.y)
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
