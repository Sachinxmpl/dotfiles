pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Night light: warms the screen through hyprsunset.
//   mode "off"  · never
//   mode "on"   · always (until you turn it off)
//   mode "auto" · sunset → sunrise for your location, fading in/out over ~40 min
// Changes ramp smoothly instead of snapping. Settings survive restarts.
//   qs ipc call night toggle | auto | off | warmer | cooler
Singleton {
    id: nl

    // ---- knobs (location defaults to Kathmandu; same as the dashboard weather)
    property real latitude: 27.7172
    property real longitude: 85.3240
    property int  fadeMinutes: 40        // auto mode: how long sunset/sunrise fades take
    readonly property int minTemp: 2500  // warmest allowed
    readonly property int maxTemp: 6000  // coolest still counted as "on"
    readonly property int neutral: 6500  // no tint

    // ---- settings (saved)
    property string mode: "off"
    property int temp: 4000

    // ---- live state
    property int applied: neutral        // what the screen is at right now
    property date now: new Date()
    readonly property var sun: sunTimes(now)
    readonly property real target: computeTarget()
    readonly property bool active: target < neutral - 50
    readonly property string summary: {
        if (mode === "off") return "Off";
        if (mode === "on") return temp + "K";
        const fmt = d => Qt.formatTime(d, "HH:mm");
        return active ? "Auto · until " + fmt(sun.nextRise) : "Auto · from " + fmt(sun.nextSet);
    }

    // ------------------------------------------------------------ persistence
    FileView {
        id: store
        path: Quickshell.statePath("nightlight.json")
        printErrors: false
        onLoaded: {
            try {
                const j = JSON.parse(text());
                if (["off", "on", "auto"].includes(j.mode)) nl.mode = j.mode;
                if (j.temp) nl.temp = Math.max(nl.minTemp, Math.min(nl.maxTemp, j.temp));
            } catch (e) {}
            nl.ready = true;
        }
        onLoadFailed: nl.ready = true
    }
    property bool ready: false
    function save() { if (ready) store.setText(JSON.stringify({ mode: mode, temp: temp })) }
    onModeChanged: save()
    onTempChanged: save()

    // ------------------------------------------------------------ public actions
    function setMode(m) { mode = m }
    function toggle() { mode = active ? "off" : "on" }
    function cycle() { mode = mode === "off" ? "on" : mode === "on" ? "auto" : "off" }
    function warmer() { temp = Math.max(minTemp, temp - 250); if (mode === "off") mode = "on" }
    function cooler() { temp = Math.min(maxTemp, temp + 250) }

    // ------------------------------------------------------------ sun maths (NOAA approximation)
    function sunOn(day) {
        const start = new Date(day.getFullYear(), 0, 0);
        const n = Math.floor((day - start) / 86400000);
        const g = 2 * Math.PI / 365 * (n - 1);
        const eq = 229.18 * (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g)
                   - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g));
        const de = 0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g) - 0.006758 * Math.cos(2 * g)
                   + 0.000907 * Math.sin(2 * g) - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g);
        const la = latitude * Math.PI / 180;
        let c = Math.cos(90.833 * Math.PI / 180) / (Math.cos(la) * Math.cos(de)) - Math.tan(la) * Math.tan(de);
        c = Math.max(-1, Math.min(1, c));                        // polar day/night safety
        const ha = Math.acos(c) * 180 / Math.PI;
        const utcMidnight = Date.UTC(day.getFullYear(), day.getMonth(), day.getDate());
        return {
            rise: new Date(utcMidnight + (720 - 4 * (longitude + ha) - eq) * 60000),
            set:  new Date(utcMidnight + (720 - 4 * (longitude - ha) - eq) * 60000)
        };
    }
    function sunTimes(t) {
        const today = sunOn(t);
        const tomorrow = sunOn(new Date(t.getFullYear(), t.getMonth(), t.getDate() + 1));
        return {
            rise: today.rise, set: today.set,
            nextRise: t < today.rise ? today.rise : tomorrow.rise,
            nextSet: t < today.set ? today.set : tomorrow.set
        };
    }

    // ------------------------------------------------------------ what the screen should be
    function computeTarget() {
        if (mode === "off") return neutral;
        if (mode === "on") return temp;
        // auto: 0 = day, 1 = full night, fading across sunset and sunrise
        const t = now.getTime(), f = fadeMinutes * 60000;
        const s = sun.set.getTime(), r = sun.rise.getTime();
        let k;
        if (t < r - f) k = 1;                                    // after midnight, before dawn fade
        else if (t < r) k = (r - t) / f;                         // dawn: fading out
        else if (t < s) k = 0;                                   // day
        else if (t < s + f) k = (t - s) / f;                     // dusk: fading in
        else k = 1;                                              // night
        return Math.round(neutral - (neutral - temp) * k);
    }

    // ------------------------------------------------------------ driving hyprsunset
    Component.onCompleted: {
        // hyprsunset must be running; start it untinted if it isn't
        Quickshell.execDetached(["sh", "-c", "pgrep -x hyprsunset >/dev/null || exec hyprsunset -i >/dev/null 2>&1"]);
        store.reload();
        startDelay.start();
    }
    Timer { id: startDelay; interval: 1200; onTriggered: nl.started = true }
    property bool started: false

    Timer {                                                       // keep "now" fresh for auto mode
        interval: 30000; running: true; repeat: true
        onTriggered: nl.now = new Date()
    }

    // ramp toward the target in small steps so it never snaps
    Timer {
        id: ramp
        interval: 40
        repeat: true
        running: nl.started && Math.abs(nl.applied - nl.target) >= 1
        onTriggered: {
            const d = nl.target - nl.applied;
            const step = Math.sign(d) * Math.min(Math.abs(d), 120);
            nl.push(nl.applied + step);
        }
    }
    function push(k) {
        applied = Math.round(k);
        if (setter.running) { pending = true; return; }
        send();
    }
    property bool pending: false
    function send() {
        setter.command = applied >= neutral - 5
            ? ["hyprctl", "hyprsunset", "identity"]
            : ["hyprctl", "hyprsunset", "temperature", String(applied)];
        setter.running = true;
    }
    Process {
        id: setter
        onExited: if (nl.pending) { nl.pending = false; nl.send(); }
    }
}
