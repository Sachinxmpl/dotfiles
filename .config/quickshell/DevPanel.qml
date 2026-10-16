// Aurora Dev panel: git state of the terminal you're in, docker containers, listening ports.
//   Opens from the bar's dev pill or Super+Shift+D.  Esc / click outside closes.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: panel

    property bool shown: false
    visible: shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "devpanel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: Panels.devOpen = false
    }

    Connections {
        target: Panels
        function onDevOpenChanged() {
            if (Panels.devOpen) {
                hide.stop();
                panel.shown = true;
                Dev.refresh();
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
        NumberAnimation { target: card; property: "opacity"; to: 1; duration: 170; easing.type: Easing.OutQuad }
        NumberAnimation { target: slide; property: "y"; from: -10; to: 0; duration: 220; easing.type: Easing.OutQuint }
    }
    ParallelAnimation {
        id: hide
        onFinished: panel.shown = false
        NumberAnimation { target: card; property: "opacity"; to: 0; duration: 110; easing.type: Easing.InQuad }
        NumberAnimation { target: slide; property: "y"; to: -6; duration: 110; easing.type: Easing.InQuad }
    }
    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: Panels.devOpen = false
    }

    readonly property string home: Quickshell.env("HOME")
    function tilde(p) { return p ? p.replace(home, "~") : "" }

    // ------------------------------------------------------------ pieces
    component Mono: Text {
        font.family: Theme.iconFont
        font.pixelSize: 12
        color: Theme.text
        elide: Text.ElideRight
    }
    component Caption: Text {
        font.family: Theme.iconFont
        font.pixelSize: 10
        font.letterSpacing: 1.4
        color: Theme.muted
    }
    component Tag: Rectangle {
        id: tag
        property string text
        property color tint: Theme.accent
        implicitWidth: tagText.implicitWidth + 14
        implicitHeight: 20
        radius: 6
        color: Theme.alpha(tint, 0.14)
        Text {
            id: tagText
            anchors.centerIn: parent
            text: tag.text
            color: tag.tint
            font.family: Theme.iconFont
            font.pixelSize: 11
        }
    }
    // small icon button with a tooltip-ish label on hover
    component Act: Rectangle {
        id: act
        property string icon
        property string tip: ""
        property color tint: Theme.subtext
        signal clicked()
        implicitWidth: 28; implicitHeight: 28
        radius: 8
        color: actArea.containsMouse ? Theme.cardHover : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
        Text {
            anchors.centerIn: parent
            text: act.icon
            color: actArea.containsMouse ? Theme.accent : act.tint
            font.family: Theme.iconFont
            font.pixelSize: 14
        }
        MouseArea {
            id: actArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: act.clicked()
        }
        Rectangle {
            visible: actArea.containsMouse && act.tip !== ""
            z: 10
            anchors.bottom: parent.top
            anchors.bottomMargin: 4
            anchors.horizontalCenter: parent.horizontalCenter
            width: tipText.implicitWidth + 12; height: 20; radius: 6
            color: Theme.cardHi
            Text { id: tipText; anchors.centerIn: parent; text: act.tip; color: Theme.text; font.family: Theme.font; font.pixelSize: 10 }
        }
    }
    component Button: Rectangle {
        id: btn
        property string icon
        property string label
        signal clicked()
        implicitWidth: btnRow.implicitWidth + 18
        implicitHeight: 30
        radius: 9
        color: btnArea.containsMouse ? Theme.cardHover : Theme.card
        Behavior on color { ColorAnimation { duration: 100 } }
        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 6
            Text { text: btn.icon; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
            Text { text: btn.label; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: btnArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
    }
    component Section: Rectangle {
        default property alias content: inner.data
        Layout.fillWidth: true
        implicitHeight: inner.implicitHeight + 24
        radius: Theme.radius
        color: Theme.alpha(Theme.card, 0.5)
        border.width: 1
        border.color: Theme.border
        ColumnLayout {
            id: inner
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 8
        }
    }

    // ------------------------------------------------------------ card
    Rectangle {
        id: card
        opacity: 0
        transform: Translate { id: slide; y: -10 }
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Theme.barHeight + 8
        anchors.rightMargin: 8
        width: 470
        height: col.implicitHeight + 28
        radius: Theme.radius + 6
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 12

            // ---- header:  ~/code/loadgate
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: ""; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 16 }
                Mono {
                    Layout.fillWidth: true
                    text: Dev.cwd ? panel.tilde(Dev.cwd) : "focus a terminal to track its folder"
                    color: Dev.cwd ? Theme.subtext : Theme.muted
                    font.pixelSize: 13
                }
                Act { icon: "󰑐"; tip: "refresh"; onClicked: Dev.refresh() }
            }

            // ---- git
            Section {
                RowLayout {
                    Layout.fillWidth: true
                    Caption { text: "GIT" }
                    Item { Layout.fillWidth: true }
                    Tag { visible: Dev.git !== null && Dev.git.changed > 0; text: "● " + (Dev.git ? Dev.git.changed : 0) + " changed"; tint: Theme.yellow }
                    Tag { visible: Dev.git !== null && Dev.git.ahead > 0;   text: "↑" + (Dev.git ? Dev.git.ahead : 0); tint: Theme.sky }
                    Tag { visible: Dev.git !== null && Dev.git.behind > 0;  text: "↓" + (Dev.git ? Dev.git.behind : 0); tint: Theme.pink }
                    Tag { visible: Dev.git !== null && Dev.git.changed === 0 && Dev.git.ahead === 0 && Dev.git.behind === 0; text: "✓ clean"; tint: Theme.accent }
                }
                RowLayout {
                    visible: Dev.git !== null
                    Layout.fillWidth: true
                    spacing: 10
                    Mono { text: Dev.git ? Dev.git.repo : ""; font.pixelSize: 17; font.weight: Font.Bold }
                    Tag { text: " " + (Dev.git ? Dev.git.branch : ""); tint: Theme.violet }
                    Item { Layout.fillWidth: true }
                }
                Flow {
                    visible: Dev.git !== null
                    Layout.fillWidth: true
                    spacing: 6
                    Button { icon: "󰨞"; label: "editor";   onClicked: { Dev.openEditor(Dev.git.path); Panels.devOpen = false } }
                    Button { icon: "";  label: "terminal"; onClicked: { Dev.openTerminal(Dev.git.path); Panels.devOpen = false } }
                    Button { icon: "";  label: "lazygit";  onClicked: { Dev.lazygit(Dev.git.path); Panels.devOpen = false } }
                    Button { icon: "";  label: "remote";   onClicked: { Dev.openRemote(Dev.git.path); Panels.devOpen = false } }
                }
                Mono {
                    visible: Dev.git === null
                    text: Dev.cwd ? "not a git repo" : "no terminal focused yet"
                    color: Theme.muted
                }
            }

            // ---- docker
            Section {
                visible: Dev.docker !== "none"
                RowLayout {
                    Layout.fillWidth: true
                    Caption { text: "CONTAINERS" }
                    Item { Layout.fillWidth: true }
                    Mono {
                        text: Dev.docker === "ok" ? Dev.running + " running · " + Dev.containers.length + " total" : "docker is off"
                        color: Theme.muted
                        font.pixelSize: 11
                    }
                }
                Button {
                    visible: Dev.docker === "off"
                    icon: "󰐊"; label: "start docker"
                    onClicked: Dev.sh("pkexec systemctl start docker")
                }
                Mono {
                    visible: Dev.docker === "ok" && Dev.containers.length === 0
                    text: "no containers"
                    color: Theme.muted
                }
                Repeater {
                    model: Dev.containers.slice(0, 8)
                    RowLayout {
                        required property var modelData
                        readonly property bool up: modelData.state === "running"
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: parent.up ? Theme.accent : Theme.dim }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Mono { Layout.fillWidth: true; text: modelData.name; color: parent.parent.up ? Theme.text : Theme.muted }
                            Mono {
                                Layout.fillWidth: true
                                text: modelData.image + "  ·  " + modelData.status
                                      + (modelData.ports ? "  ·  " + modelData.ports.replace(/0\.0\.0\.0:|\[::\]:/g, "").split(", ").filter((v, i, a) => a.indexOf(v) === i).join(" ") : "")
                                color: Theme.muted
                                font.pixelSize: 10
                            }
                        }
                        Act { icon: "󰦨"; tip: "logs";  onClicked: Dev.ctr("logs", modelData.name) }
                        Act { visible: parent.up; icon: ""; tip: "shell"; onClicked: Dev.ctr("shell", modelData.name) }
                        Act { visible: parent.up; icon: "󰑓"; tip: "restart"; onClicked: Dev.ctr("restart", modelData.name) }
                        Act {
                            icon: parent.up ? "󰓛" : "󰐊"
                            tip: parent.up ? "stop" : "start"
                            tint: parent.up ? Theme.red : Theme.accent
                            onClicked: Dev.ctr(parent.up ? "stop" : "start", modelData.name)
                        }
                    }
                }
            }

            // ---- ports
            Section {
                RowLayout {
                    Layout.fillWidth: true
                    Caption { text: "LISTENING" }
                    Item { Layout.fillWidth: true }
                    Mono { text: Dev.ports.length + " tcp ports"; color: Theme.muted; font.pixelSize: 11 }
                }
                Mono {
                    visible: Dev.ports.length === 0
                    text: "nothing listening"
                    color: Theme.muted
                }
                Repeater {
                    model: Dev.ports.slice(0, 10)
                    RowLayout {
                        required property var modelData
                        readonly property bool mine: modelData.pid !== "-"
                        Layout.fillWidth: true
                        spacing: 10
                        Mono {
                            Layout.preferredWidth: 62
                            text: ":" + modelData.port
                            color: parent.mine ? Theme.accent : Theme.subtext
                            font.weight: Font.Bold
                        }
                        Mono {
                            Layout.fillWidth: true
                            text: (parent.mine ? modelData.proc + "  pid " + modelData.pid : "system") + "  ·  " + modelData.host
                            color: parent.mine ? Theme.text : Theme.muted
                        }
                        Act { icon: "󰖟"; tip: "open"; onClicked: { Quickshell.execDetached(["xdg-open", "http://localhost:" + modelData.port]); Panels.devOpen = false } }
                        Act { visible: parent.mine; icon: "󰅖"; tip: "kill"; tint: Theme.red; onClicked: Dev.killPort(modelData) }
                    }
                }
            }
        }
    }
}
