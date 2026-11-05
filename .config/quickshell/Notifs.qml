pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Notification state. The NotificationServer itself lives in shell.qml
// (it has to be created at startup) and hands every notification to push().
//   Do Not Disturb: manual (Notifs.dnd) or on a schedule (Settings → Bar → notifications)
Singleton {
    id: root

    property var server: null           // set by shell.qml
    property bool dnd: false            // manual do not disturb: no pop-ups (history still kept)
    property var popups: []             // notifications currently shown as toasts
    property var times: ({})            // id → arrival time (ms); the spec has no timestamp

    // everything not yet dismissed, newest first
    readonly property var history: server ? server.trackedNotifications.values.slice().reverse() : []

    // ------------------------------------------------------------ do not disturb
    readonly property bool scheduled: Settings.o.dndSchedule === true
    property bool inWindow: false
    readonly property bool quiet: dnd || (scheduled && inWindow)
    function minutes(s) {
        const m = String(s || "").match(/^(\d{1,2}):(\d{2})$/);
        return m ? Math.min(23, +m[1]) * 60 + Math.min(59, +m[2]) : -1;
    }
    function checkWindow() {
        const a = minutes(Settings.o.dndFrom), b = minutes(Settings.o.dndTo);
        if (a < 0 || b < 0 || a === b) { inWindow = false; return; }
        const d = new Date(), now = d.getHours() * 60 + d.getMinutes();
        inWindow = a < b ? (now >= a && now < b) : (now >= a || now < b);   // window may cross midnight
    }
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.checkWindow() }
    Connections {
        target: Settings.o
        function onDndFromChanged() { root.checkWindow() }
        function onDndToChanged() { root.checkWindow() }
        function onDndScheduleChanged() { root.checkWindow() }
    }

    // ------------------------------------------------------------ incoming
    function push(n) {
        n.tracked = true;
        const t = Object.assign({}, times);
        t[n.id] = Date.now();
        times = t;
        n.closed.connect(() => root.dropPopup(n));
        if (quiet && n.urgency !== NotificationUrgency.Critical) return;
        popups = [n].concat(popups).slice(0, 4);
    }

    // hide the toast but keep it in history
    function dropPopup(n) {
        popups = popups.filter(p => p !== n);
    }

    // ------------------------------------------------------------ helpers for the centre
    function appOf(n) { return n.appName || n.desktopEntry || "system" }
    function timeOf(n) { return times[n.id] || 0 }
    function ago(ms) {
        if (!ms) return "";
        const s = Math.max(0, Math.round((Date.now() - ms) / 1000));
        if (s < 45) return "now";
        if (s < 3600) return Math.round(s / 60) + "m";
        if (s < 86400) return Math.floor(s / 3600) + "h";
        return Math.floor(s / 86400) + "d";
    }

    function dismissApp(app) {
        for (const n of history.slice()) if (appOf(n) === app) n.dismiss();
    }
    function clearAll() {
        for (const n of history.slice()) n.dismiss();
        popups = [];
    }
}
