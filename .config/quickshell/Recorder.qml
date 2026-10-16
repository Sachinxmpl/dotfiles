pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Screen-recording state for the bar timer and the capture menu.
// aurora-rec writes ~/.cache/aurora/rec.state ("<start-epoch> <pid> <file>") while recording.
Singleton {
    id: rec

    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/"

    FileView {
        id: stateFile
        path: Quickshell.env("HOME") + "/.cache/aurora/rec.state"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoadFailed: rec.raw = ""
        onLoaded: rec.raw = text().trim()
    }
    property string raw: ""
    readonly property bool active: raw !== ""
    readonly property real startedAt: active ? Number(raw.split(" ")[0]) : 0
    readonly property string file: active ? raw.split(" ").slice(2).join(" ") : ""

    // mm:ss since the recording started
    property real now: Date.now() / 1000
    Timer { interval: 1000; repeat: true; running: rec.active; triggeredOnStart: true; onTriggered: rec.now = Date.now() / 1000 }
    readonly property string elapsed: {
        const s = Math.max(0, Math.floor(now - startedAt));
        const m = Math.floor(s / 60);
        return (m < 10 ? "0" : "") + m + ":" + String(s % 60).padStart(2, "0");
    }

    function stop() { Quickshell.execDetached([bin + "aurora-rec", "stop"]) }
    function start(mode, audio) { Quickshell.execDetached([bin + "aurora-rec", "start", mode, "--audio", audio]) }
    function shot(mode, edit, delay) {
        const cmd = [bin + "aurora-shot", mode];
        if (edit) cmd.push("--edit");
        if (delay > 0) cmd.push("--delay", String(delay));
        Quickshell.execDetached(cmd);
    }
}
