pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Live audio spectrum from cava (sudo pacman -S cava).
// It only runs while something is playing, so it costs nothing when the music stops.
//   Cava.values   → `bars` numbers between 0 and 1, about 60 times a second
//   Cava.band(i, n) → the spectrum squeezed into n groups (the bar pill uses 5)
Singleton {
    id: cava

    readonly property int bars: 48
    property var values: []
    property bool available: false          // cava is installed
    property string error: ""                // last failure, shown in the media panel
    readonly property bool wanted: Settings.o.visualizer !== false
    readonly property bool playing: Mpris.players.values.some(p => p.isPlaying)
    readonly property bool live: available && wanted && playing && error === ""

    function band(i, n) {
        const v = values;
        if (!v.length) return 0;
        const per = v.length / n, a = Math.floor(i * per), b = Math.max(a + 1, Math.floor((i + 1) * per));
        let s = 0;
        for (let k = a; k < b; k++) s += v[k] || 0;
        return s / (b - a);
    }

    // is cava installed?
    Process {
        running: true
        command: ["sh", "-c", "command -v cava >/dev/null && echo yes"]
        stdout: StdioCollector { onStreamFinished: cava.available = text.trim() === "yes" }
    }

    // the config is written next to the socket dir each start, so there is nothing to install
    readonly property string conf: [
        "[general]", "bars = " + bars, "framerate = 60", "autosens = 1", "lower_cutoff_freq = 40",
        "[input]", "method = pipewire", "source = auto",
        "[output]", "method = raw", "raw_target = /dev/stdout", "data_format = ascii",
        "ascii_max_range = 1000", "bar_delimiter = 59", "frame_delimiter = 10", "channels = mono",
        "[smoothing]", "noise_reduction = 72"
    ].join("\n")

    property double started: 0
    Process {
        id: proc
        running: cava.live
        command: ["sh", "-c",
            "c=\"${XDG_RUNTIME_DIR:-/tmp}/aurora-cava.conf\"; printf '%s\\n' \"$1\" > \"$c\"; exec cava -p \"$c\"",
            "sh", cava.conf]
        onRunningChanged: {
            if (running) { cava.started = Date.now(); return; }
            cava.values = [];
        }
        onExited: code => {
            // died straight away → don't keep restarting it, say why instead
            // (when we stopped it ourselves, live is already false)
            if (cava.live && code !== 0 && Date.now() - cava.started < 3000)
                cava.error = (errOut.text || "").trim().split("\n").pop() || ("cava exited with code " + code);
        }
        stdout: SplitParser {
            onRead: data => {
                if (!cava.live) return;               // a late frame after stopping
                const parts = data.split(";");
                const out = new Array(cava.bars);
                for (let i = 0; i < cava.bars; i++) out[i] = Math.min(1, (+parts[i] || 0) / 1000);
                cava.values = out;
            }
        }
        stderr: StdioCollector { id: errOut }
    }
    // a new song is a good moment to try again after a failure
    function retry() { error = "" }
}
