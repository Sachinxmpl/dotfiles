pragma Singleton

import QtQuick
import Quickshell

// Shared panel state. Only one panel is open at a time.
// (Named "Panels" because "State" clashes with a built-in Qt type.)
Singleton {
    property bool ccOpen: false
    property bool launcherOpen: false
    property string launcherPrefix: ""   // open the launcher straight into a mode (; ~ : ? > =)
    property bool wallsOpen: false
    property bool dashOpen: false
    property bool overviewOpen: false
    property bool devOpen: false
    property bool captureOpen: false
    property bool powerOpen: false
    property bool radarOpen: false
    property string radarMode: "wifi"   // wifi · bt
    property bool notifOpen: false
    property bool mediaOpen: false
    property bool audioOpen: false
    property bool gpuOpen: false
    property bool clipOpen: false
    property bool focusOpen: false
    // webcam mirror (Mirror.qml). The bubble mode floats over everything, so other panels don't close it.
    property bool mirrorOpen: false
    property bool mirrorBubble: false
    property bool mirrorRecording: false     // keeps it loaded until the clip is written
    property int  bubbleX: -1                // -1: bottom-right corner
    property int  bubbleY: -1
    property int  bubbleSize: 220
    readonly property bool anyOpen: ccOpen || launcherOpen || wallsOpen || dashOpen || overviewOpen || devOpen || captureOpen || powerOpen || radarOpen || notifOpen || mediaOpen || audioOpen || gpuOpen || clipOpen || focusOpen

    function toggleCc() {
        const v = !ccOpen;
        closeAll();
        ccOpen = v;
    }
    function toggleLauncher() {
        const v = !launcherOpen;
        closeAll();
        launcherOpen = v;
    }
    function toggleWalls() {
        const v = !wallsOpen;
        closeAll();
        wallsOpen = v;
    }
    function toggleDash() {
        const v = !dashOpen;
        closeAll();
        dashOpen = v;
    }
    function toggleOverview() {
        const v = !overviewOpen;
        closeAll();
        overviewOpen = v;
    }
    function toggleDev() {
        const v = !devOpen;
        closeAll();
        devOpen = v;
    }
    function toggleCapture() {
        const v = !captureOpen;
        closeAll();
        captureOpen = v;
    }
    function togglePower() {
        const v = !powerOpen;
        closeAll();
        powerOpen = v;
    }
    // same mode again closes it; the other mode switches tab
    function toggleRadar(m) {
        const close = radarOpen && radarMode === m;
        closeAll();
        radarMode = m;
        radarOpen = !close;
    }
    function toggleNotif() {
        const v = !notifOpen;
        closeAll();
        notifOpen = v;
    }
    function toggleMedia() {
        const v = !mediaOpen;
        closeAll();
        mediaOpen = v;
    }
    function toggleAudio() {
        const v = !audioOpen;
        closeAll();
        audioOpen = v;
    }
    function toggleGpu() {
        const v = !gpuOpen;
        closeAll();
        gpuOpen = v;
    }
    function toggleClip() {
        const v = !clipOpen;
        closeAll();
        clipOpen = v;
    }
    function toggleFocus() {
        const v = !focusOpen;
        closeAll();
        focusOpen = v;
    }
    function toggleMirror() {
        if (mirrorOpen) { mirrorOpen = false; return; }
        closeAll();
        mirrorBubble = false;
        mirrorOpen = true;
    }
    function toggleBubble() {
        if (mirrorOpen && mirrorBubble) { mirrorOpen = false; return; }
        mirrorBubble = true;
        mirrorOpen = true;
    }
    function closeAll() {
        if (!mirrorBubble && !mirrorRecording) mirrorOpen = false;
        ccOpen = false;
        launcherOpen = false;
        wallsOpen = false;
        dashOpen = false;
        overviewOpen = false;
        devOpen = false;
        captureOpen = false;
        powerOpen = false;
        radarOpen = false;
        notifOpen = false;
        mediaOpen = false;
        audioOpen = false;
        gpuOpen = false;
        clipOpen = false;
        focusOpen = false;
    }
}
