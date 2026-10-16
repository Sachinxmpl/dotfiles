pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Notification state. The NotificationServer itself lives in shell.qml
// (it has to be created at startup) and hands every notification to push().
Singleton {
    id: root

    property var server: null           // set by shell.qml
    property bool dnd: false            // do not disturb: no pop-ups (history still kept)
    property var popups: []             // notifications currently shown as toasts

    // everything not yet dismissed, newest first
    readonly property var history: server ? server.trackedNotifications.values.slice().reverse() : []

    function push(n) {
        n.tracked = true;
        n.closed.connect(() => root.dropPopup(n));
        if (dnd && n.urgency !== NotificationUrgency.Critical) return;
        popups = [n].concat(popups).slice(0, 4);
    }

    // hide the toast but keep it in history
    function dropPopup(n) {
        popups = popups.filter(p => p !== n);
    }

    function clearAll() {
        for (const n of history.slice()) n.dismiss();
        popups = [];
    }
}
