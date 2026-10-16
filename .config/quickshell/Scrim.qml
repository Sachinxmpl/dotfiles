// Full-screen layer behind any open panel (control centre, launcher).
// A click anywhere outside the panel lands here and closes it.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    // only the control centre uses this; the launcher has its own built-in backdrop
    visible: Panels.ccOpen
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore      // cover the bar too
    color: Qt.rgba(0, 0, 0, 0.12)
    WlrLayershell.namespace: "scrim"         // (not "aurora-*", so it isn't blurred)
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: Panels.closeAll()
    }
}
