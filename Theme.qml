import QtQuick
import Quickshell
import qs.Commons

// Isolates Omarchy theme tokens. Visuals bind here so a missing token
// cannot take the whole plugin down — see ASSUMPTIONS.md.

QtObject {
  id: theme

  // Live bindings — a function wrapper would hide Color.* from the
  // dependency tracker and break the 200 ms theme lerp.
  property color bg: Color.menu.background
  property color surface: Color.menu.background
  property color text: Color.menu.text
  property color muted: Qt.rgba(text.r, text.g, text.b, 0.55)
  property color accent: Color.accent
  property color border: Color.menu.border
  property color scrim: Color.menu.scrim
  property color selectedBg: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color danger: Qt.rgba(0.86, 0.22, 0.22, 1)

  property int radius: _num(function () { return Style.cornerRadius }, 10)
  property int pad: _num(function () { return Style.spacing && Style.spacing.panelPadding }, 16)
  property int gap: _num(function () { return Style.spacing && Style.spacing.md }, 10)
  property int gapsOut: _num(function () { return Style.gapsOut }, 16)
  property string fontFamily: _str(function () { return Style.font && Style.font.menuFamily }, "sans-serif")
  property int fontHeading: _num(function () { return Style.font && Style.font.heading }, 16)
  property int fontBody: _num(function () { return Style.font && Style.font.body }, 13)
  property int fontSmall: _num(function () { return Style.font && Style.font.small }, 11)
  property var borderSpec: {
    try {
      return Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
    } catch (e) {
      return null
    }
  }

  property bool reduceMotion: {
    try {
      if (Style && Style.reduceMotion)
        return true
    } catch (e) {}
    try {
      if (Quickshell && Quickshell.env && Quickshell.env("OMARCHY_REDUCED_MOTION") === "1")
        return true
    } catch (e2) {}
    return false
  }

  property int motionMs: reduceMotion ? 0 : 150
  property int themeMs: reduceMotion ? 0 : 200

  function _num(fn, fallback) {
    try {
      var n = fn()
      if (typeof n === "number" && isFinite(n))
        return n
    } catch (e) {}
    return fallback
  }

  function _str(fn, fallback) {
    try {
      var s = fn()
      if (s)
        return String(s)
    } catch (e) {}
    return fallback
  }
}
