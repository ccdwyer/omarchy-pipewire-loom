import QtQuick

Rectangle {
  id: help
  property var theme: null
  Theme { id: tokens }
  readonly property var pal: theme ? theme : tokens
  radius: pal.radius
  color: pal.surface
  border.width: 1
  border.color: pal.border
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
      color: help.pal.text
      font.family: help.pal.fontFamily
      font.pixelSize: help.pal.fontHeading
      font.bold: true
    }

    Repeater {
      model: [
        "h j k l / arrows    walk nodes",
        "Tab                 simple ↔ full graph",
        "Enter               start / complete an explicit link",
        "Esc                 cancel drag, or close",
        "m                   mute / unmute subgraph (wpctl)",
        "n                   spawn Loom sink (off unless virtualSinks)",
        "x / Backspace       unlink selected · destroy Loom sink",
        "+ / -               volume on selection",
        "Drag node → sink    move (WirePlumber target.object)",
        "Drag port → port    explicit pw-link (dashed, fragile)",
        "?                   this overlay"
      ]
      delegate: Text {
        required property string modelData
        text: modelData
        color: help.pal.muted
        font.family: help.pal.fontFamily
        font.pixelSize: help.pal.fontSmall
      }
    }
  }
}
