import QtQuick

Rectangle {
  id: help
  property var theme: null
  radius: theme ? theme.radius : 10
  color: theme ? theme.surface : "#1c1c1c"
  border.width: 1
  border.color: theme ? theme.border : "#3a3a3a"
  width: 420
  height: col.height + 28

  Column {
    id: col
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 14
    spacing: 6

    Text {
      text: "Loom keys"
      color: help.theme ? help.theme.text : "#fff"
      font.family: help.theme ? help.theme.fontFamily : "sans-serif"
      font.pixelSize: help.theme ? help.theme.fontHeading : 16
      font.bold: true
    }

    Repeater {
      model: [
        "h j k l / arrows    walk nodes",
        "Tab                 simple ↔ full graph",
        "Enter               start / complete an explicit link",
        "Esc                 cancel drag, or close",
        "m                   mute / unmute subgraph (wpctl)",
        "n                   spawn Loom-<name> null sink",
        "x / Backspace       unlink selected · destroy Loom sink",
        "+ / -               volume on selection",
        "Drag node → sink    move (WirePlumber target.object)",
        "Drag port → port    explicit pw-link (dashed, fragile)",
        "?                   this overlay"
      ]
      delegate: Text {
        required property string modelData
        text: modelData
        color: help.theme ? help.theme.muted : "#aaa"
        font.family: help.theme ? help.theme.fontFamily : "sans-serif"
        font.pixelSize: help.theme ? help.theme.fontSmall : 11
      }
    }
  }
}
