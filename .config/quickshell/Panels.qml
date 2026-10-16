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
    readonly property bool anyOpen: ccOpen || launcherOpen || wallsOpen || dashOpen || overviewOpen || devOpen || captureOpen

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
    function closeAll() {
        ccOpen = false;
        launcherOpen = false;
        wallsOpen = false;
        dashOpen = false;
        overviewOpen = false;
        devOpen = false;
        captureOpen = false;
    }
}
