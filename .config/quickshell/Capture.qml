// Aurora capture menu: screenshots + screen recording, macOS-style bar at the bottom.
//   Print opens it.  1-3 screenshot region/window/screen · 4-5 record region/screen
//   E toggle "edit after" · D cycle delay · A cycle audio · Esc close
// Quick keys without the menu: Shift+Print region → clipboard, Ctrl+Print full screen,
// Super+Shift+R start/stop a region recording.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: cap

    // ---- remembered while the shell runs
    property bool editAfter: false
    property int  delay: 0                       // 0 · 3 · 5 seconds
    property string audio: "none"                // none · system · mic

    property bool shown: false
    visible: shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "capture"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle { id: backdrop; anchors.fill: parent; color: "black"; opacity: 0 }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: Panels.captureOpen = false }

    Connections {
        target: Panels
        function onCaptureOpenChanged() {
            if (Panels.captureOpen) {
                hide.stop();
                cap.shown = true;
                keys.forceActiveFocus();
                appear.restart();
            } else {
                appear.stop();
                hide.restart();
            }
        }
    }
    ParallelAnimation {
        id: appear
        NumberAnimation { target: backdrop; property: "opacity"; to: 0.12; duration: 160 }
        NumberAnimation { target: card; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutQuad }
        NumberAnimation { target: rise; property: "y"; from: 18; to: 0; duration: 240; easing.type: Easing.OutQuint }
    }
    ParallelAnimation {
        id: hide
        onFinished: cap.shown = false
        NumberAnimation { target: backdrop; property: "opacity"; to: 0; duration: 110 }
        NumberAnimation { target: card; property: "opacity"; to: 0; duration: 110; easing.type: Easing.InQuad }
    }

    // run an action after the menu is gone, so it isn't in the picture
    function go(fn) { Panels.captureOpen = false; fn(); }
    function shot(mode) { go(() => Recorder.shot(mode, cap.editAfter, cap.delay)) }
    function record(mode) { go(() => Recorder.start(mode, cap.audio)) }

    Item {
        id: keys
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) Panels.captureOpen = false;
            else if (e.key === Qt.Key_1 || e.key === Qt.Key_Return) cap.shot("region");
            else if (e.key === Qt.Key_2) cap.shot("window");
            else if (e.key === Qt.Key_3 || e.key === Qt.Key_Print) cap.shot("screen");
            else if (e.key === Qt.Key_4) Recorder.active ? cap.go(() => Recorder.stop()) : cap.record("region");
            else if (e.key === Qt.Key_5) Recorder.active ? cap.go(() => Recorder.stop()) : cap.record("screen");
            else if (e.key === Qt.Key_E) cap.editAfter = !cap.editAfter;
            else if (e.key === Qt.Key_D) cap.delay = cap.delay === 0 ? 3 : cap.delay === 3 ? 5 : 0;
            else if (e.key === Qt.Key_A) cap.audio = cap.audio === "none" ? "system" : cap.audio === "system" ? "mic" : "none";
            else return;
            e.accepted = true;
        }
    }

    // ------------------------------------------------------------ pieces
    // big square action: icon + label + key hint
    component Action: Rectangle {
        id: act
        property string icon
        property string label
        property string hint
        property color tint: Theme.accent
        signal clicked()
        implicitWidth: 78; implicitHeight: 74
        radius: 14
        color: actArea.containsMouse ? Theme.alpha(tint, 0.16) : "transparent"
        border.width: 1
        border.color: actArea.containsMouse ? Theme.alpha(tint, 0.5) : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
        Column {
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: act.icon
                color: act.tint
                font.family: Theme.iconFont
                font.pixelSize: 22
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: act.label
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 11
                font.weight: Font.Medium
            }
        }
        Text {
            anchors { right: parent.right; top: parent.top; margins: 6 }
            text: act.hint
            color: Theme.dim
            font.family: Theme.mono
            font.pixelSize: 9
        }
        MouseArea { id: actArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: act.clicked() }
    }
    // small option toggle: icon + value
    component Opt: Rectangle {
        id: opt
        property string icon
        property string value
        property bool on: false
        property string hint
        signal clicked()
        implicitWidth: optRow.implicitWidth + 20; implicitHeight: 30
        radius: 9
        color: on ? Theme.alpha(Theme.accent, 0.16) : (optArea.containsMouse ? Theme.cardHover : Theme.card)
        Behavior on color { ColorAnimation { duration: 100 } }
        Row {
            id: optRow
            anchors.centerIn: parent
            spacing: 6
            Text { text: opt.icon; color: opt.on ? Theme.accent : Theme.subtext; font.family: Theme.iconFont; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            Text { text: opt.value; color: opt.on ? Theme.text : Theme.subtext; font.family: Theme.mono; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
            Text { text: opt.hint; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: optArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: opt.clicked() }
    }
    component Divider: Rectangle { implicitWidth: 1; implicitHeight: 60; color: Theme.line; Layout.alignment: Qt.AlignVCenter }
    component Caption: Text {
        font.family: Theme.mono
        font.pixelSize: 9
        font.letterSpacing: 1.4
        color: Theme.muted
    }

    // ------------------------------------------------------------ the bar
    Rectangle {
        id: card
        opacity: 0
        transform: Translate { id: rise; y: 0 }
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 56
        width: row.implicitWidth + 28
        height: row.implicitHeight + 28
        radius: 22
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 10

            // screenshots
            ColumnLayout {
                spacing: 4
                Caption { text: "SCREENSHOT"; Layout.leftMargin: 6 }
                Row {
                    spacing: 2
                    Action { icon: ""; label: "Region"; hint: "1"; onClicked: cap.shot("region") }
                    Action { icon: ""; label: "Window"; hint: "2"; onClicked: cap.shot("window") }
                    Action { icon: ""; label: "Screen"; hint: "3"; onClicked: cap.shot("screen") }
                }
            }
            Divider {}

            // recording
            ColumnLayout {
                spacing: 4
                Caption { text: Recorder.active ? "RECORDING " + Recorder.elapsed : "RECORD"; color: Recorder.active ? Theme.red : Theme.muted; Layout.leftMargin: 6 }
                Row {
                    spacing: 2
                    Action {
                        visible: !Recorder.active
                        icon: ""; label: "Region"; hint: "4"; tint: Theme.red
                        onClicked: cap.record("region")
                    }
                    Action {
                        visible: !Recorder.active
                        icon: ""; label: "Screen"; hint: "5"; tint: Theme.red
                        onClicked: cap.record("screen")
                    }
                    Action {
                        visible: Recorder.active
                        implicitWidth: 158
                        icon: ""; label: "Stop recording"; hint: "4"; tint: Theme.red
                        onClicked: cap.go(() => Recorder.stop())
                    }
                }
            }
            Divider {}

            // options
            ColumnLayout {
                spacing: 6
                Caption { text: "OPTIONS"; Layout.leftMargin: 2 }
                Opt {
                    icon: ""; value: cap.editAfter ? "edit after" : "no edit"; hint: "e"
                    on: cap.editAfter
                    onClicked: cap.editAfter = !cap.editAfter
                }
                Opt {
                    icon: ""; value: cap.delay === 0 ? "no delay" : cap.delay + "s delay"; hint: "d"
                    on: cap.delay > 0
                    onClicked: cap.delay = cap.delay === 0 ? 3 : cap.delay === 3 ? 5 : 0
                }
                Opt {
                    icon: cap.audio === "mic" ? "" : cap.audio === "system" ? "" : ""
                    value: cap.audio === "none" ? "no audio" : cap.audio === "system" ? "system audio" : "microphone"; hint: "a"
                    on: cap.audio !== "none"
                    onClicked: cap.audio = cap.audio === "none" ? "system" : cap.audio === "system" ? "mic" : "none"
                }
            }

            // open folders
            ColumnLayout {
                spacing: 6
                Layout.alignment: Qt.AlignBottom
                Opt { icon: ""; value: "shots"; onClicked: cap.go(() => Quickshell.execDetached(["nautilus", Quickshell.env("HOME") + "/Pictures/Screenshots"])) }
                Opt { icon: ""; value: "videos"; onClicked: cap.go(() => Quickshell.execDetached(["nautilus", Quickshell.env("HOME") + "/Videos/Recordings"])) }
            }
        }
    }
}
