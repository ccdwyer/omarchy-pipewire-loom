import QtQuick
import Quickshell
import qs.Commons

// Isolates Omarchy theme tokens. Visuals bind here so a missing token
// cannot take the whole plugin down — see ASSUMPTIONS.md.

QtObject {
  id: theme

  // Token-only colors. No hex literals. If a token is missing, derive
  // from another token or from a channel mix of Color.accent / Color.menu.text.
  property color accent: _live(function () { return Color.accent }, Qt.rgba(0.78, 0.64, 0.42, 1))
  property color bg: _live(function () { return Color.menu.background }, Qt.rgba(accent.r * 0.12, accent.g * 0.12, accent.b * 0.12, 1))
  property color surface: _live(function () { return Color.menu.background }, bg)
  property color text: _live(function () { return Color.menu.text }, Qt.rgba(0.95, 0.95, 0.95, 1))
  property color muted: Qt.rgba(text.r, text.g, text.b, 0.55)
  property color border: _live(function () { return Color.menu.border }, Qt.rgba(text.r, text.g, text.b, 0.22))
  property color scrim: _live(function () { return Color.menu.scrim }, Qt.rgba(0, 0, 0, 0.66))
  property color selectedBg: _live(function () { return Color.menu.selectedBackground }, Qt.rgba(accent.r, accent.g, accent.b, 0.22))
  property color selectedText: _live(function () { return Color.menu.selectedText }, text)
  property color danger: _live(function () { return Color.error }, Qt.rgba(text.r, accent.g * 0.25, accent.b * 0.25, 1))

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

  function _live(fn, fallback) {
    try {
      var c = fn()
      if (c !== undefined && c !== null && c !== "")
        return c
    } catch (e) {}
    return fallback
  }

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
