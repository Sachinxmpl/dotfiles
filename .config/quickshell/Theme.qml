pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Aurora design tokens: every colour and size the shell uses lives here.
//
// Colours come from ~/.cache/aurora/colors.json, which matugen writes when you
// pick a wallpaper (see aurora-wall). If that file is missing, the original
// Aurora palette below is used. Edits to the file apply live.
Singleton {
    id: theme

    // ---- wallpaper colours (matugen) -------------------------------------
    FileView {
        id: colorsFile
        path: Quickshell.env("HOME") + "/.cache/aurora/colors.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property var m: {
        const t = colorsFile.text();
        if (!t) return ({});
        try { return JSON.parse(t); } catch (e) { return ({}); }
    }
    // m.key, or the Aurora default when there is no colors.json
    function pick(key, fallback) { return m[key] !== undefined ? m[key] : fallback; }

    // same colour with a different opacity:  Theme.alpha(Theme.accent, 0.3)
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    // ---- surfaces ----------------------------------------------------------
    readonly property color bg:        pick("bg", "#05080f")
    readonly property color surface:   pick("surface", "#0e1320")          // popups, OSD, toasts
    readonly property color card:      pick("card", "#1b2235")             // tiles, tracks, chips
    readonly property color cardHover: pick("cardHover", "#232b42")
    readonly property color cardHi:    pick("cardHi", "#2a3350")           // borders, pressed
    readonly property color panel:     alpha(pick("panel", "#0a0e18"), 0.72)  // the bar
    readonly property color well:      alpha(bg, 0.60)
    readonly property color hover:     alpha(text, 0.08)
    readonly property color border:    alpha(text, 0.09)
    readonly property color line:      alpha(text, 0.10)                   // popup outlines

    // ---- text --------------------------------------------------------------
    readonly property color text:    pick("text", "#e6edf7")
    readonly property color subtext: pick("subtext", "#c9d3e3")
    readonly property color muted:   pick("muted", "#9aa6bb")
    readonly property color dim:     pick("dim", "#5b6780")

    // ---- accents -----------------------------------------------------------
    readonly property color teal:    pick("primary", "#6ee7c8")
    readonly property color sky:     pick("secondary", "#7cc4ff")
    readonly property color violet:  pick("tertiary", "#a78bfa")
    readonly property color pink:    pick("pink", "#f9a8d4")
    readonly property color yellow:  pick("yellow", "#f5d58a")
    readonly property color red:     pick("red", "#ff7a90")
    readonly property color accent:  teal
    readonly property color onAccent: pick("onPrimary", "#05080f")         // text/icons on accent
    readonly property color accentSoft: alpha(accent, 0.14)
    readonly property color gradA:   pick("primaryContainer", "#1f8f74")   // avatar gradient
    readonly property color gradB:   pick("tertiaryContainer", "#6b4fbf")

    // ---- type --------------------------------------------------------------
    readonly property string font:     "Inter"
    readonly property string iconFont: "JetBrainsMono Nerd Font"
    readonly property string mono:     iconFont                     // code-ish text: bar, paths, numbers
    readonly property int    fontSize: 12

    // ---- shape -------------------------------------------------------------
    readonly property int barHeight: 44
    readonly property int radius:    14
    readonly property int radiusSm:  10
}
