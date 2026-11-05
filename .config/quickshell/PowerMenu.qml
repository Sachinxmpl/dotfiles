// Aurora power menu: session actions + power profile + GPU mode
//   open:  Super+Esc · Super+Shift+E · power button in the bar
//   keys:  j/k or arrows move · Enter run · l s e r u p jump straight to an action
//          1 2 3 power profile · Esc / click outside close
//   logout, reboot, firmware and shutdown ask twice (press again within 3 s)

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower

PanelWindow {
    id: pm

    property bool shown: false
    visible: shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "power"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property int sel: 0
    property int armed: -1                       // action waiting for its second press

    readonly property var actions: [
        { name: "lock",     key: "l", icon: "", c: Theme.sky,    confirm: false, show: "loginctl lock-session",            cmd: ["loginctl", "lock-session"] },
        { name: "suspend",  key: "s", icon: "", c: Theme.violet, confirm: false, show: "systemctl suspend",                cmd: ["systemctl", "suspend"] },
        { name: "logout",   key: "e", icon: "", c: Theme.yellow, confirm: true,  show: "hl.dsp.exit()",                    cmd: [] },
        { name: "reboot",   key: "r", icon: "", c: Theme.pink,   confirm: true,  show: "systemctl reboot",                 cmd: ["systemctl", "reboot"] },
        { name: "firmware", key: "u", icon: "", c: Theme.muted,  confirm: true,  show: "systemctl reboot --firmware-setup", cmd: ["systemctl", "reboot", "--firmware-setup"] },
        { name: "shutdown", key: "p", icon: "", c: Theme.red,    confirm: true,  show: "systemctl poweroff",               cmd: ["systemctl", "poweroff"] }
    ]

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.isLaptopBattery
    readonly property string batteryText: {
        if (!hasBattery) return "";
        const pct = Math.round(battery.percentage * 100) + "%";
        const charging = battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged;
        return charging ? pct + " ⚡" : pct;
    }

    function close() { Panels.powerOpen = false }

    function run(i) {
        const a = actions[i];
        sel = i;
        if (a.confirm && armed !== i) { armed = i; armTimer.restart(); return; }
        armed = -1;
        pending = a;
        close();
        fire.restart();                          // let the menu fade out first
    }
    property var pending: null
    Timer {
        id: fire
        interval: 160
        onTriggered: {
            const a = pm.pending;
            pm.pending = null;
            if (!a) return;
            if (a.cmd.length) Quickshell.execDetached(a.cmd);
            else Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.exit()" : "exit");
        }
    }
    Timer { id: armTimer; interval: 3000; onTriggered: pm.armed = -1 }

    // ------------------------------------------------------------ open / close
    Connections {
        target: Panels
        function onPowerOpenChanged() {
            if (Panels.powerOpen) {
                hide.stop();
                pm.sel = 0;
                pm.armed = -1;
                pm.shown = true;
                Power.refresh();
                card.forceActiveFocus();
                appear.restart();
            } else {
                appear.stop();
                hide.restart();
            }
        }
    }
    ParallelAnimation {
        id: appear
        NumberAnimation { target: backdrop; property: "opacity"; to: 0.5; duration: 170; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "opacity"; to: 1; duration: 170; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "scale"; from: 0.96; to: 1; duration: 220; easing.type: Easing.OutQuint }
    }
    ParallelAnimation {
        id: hide
        onFinished: pm.shown = false
        NumberAnimation { target: backdrop; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InQuad }
        NumberAnimation { target: card; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InQuad }
        NumberAnimation { target: card; property: "scale"; to: 0.98; duration: 120; easing.type: Easing.InQuad }
    }

    Rectangle { id: backdrop; anchors.fill: parent; color: "black"; opacity: 0 }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: pm.close() }

    // ============================================================ the card
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 620
        height: body.implicitHeight + 2
        opacity: 0
        radius: Theme.radius
        color: Theme.bg
        border.width: 1
        border.color: Theme.alpha(pm.armed >= 0 ? Theme.red : Theme.accent, 0.35)
        Behavior on border.color { ColorAnimation { duration: 150 } }
        focus: true

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Keys.onPressed: e => {
            const k = e.key, n = pm.actions.length;
            if (k === Qt.Key_Escape) {
                if (pm.armed >= 0) pm.armed = -1; else pm.close();
            } else if (k === Qt.Key_J || k === Qt.Key_Down || k === Qt.Key_Tab) { pm.sel = (pm.sel + 1) % n; pm.armed = -1; }
            else if (k === Qt.Key_K || k === Qt.Key_Up || k === Qt.Key_Backtab) { pm.sel = (pm.sel + n - 1) % n; pm.armed = -1; }
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) pm.run(pm.sel);
            else if (k === Qt.Key_1) Power.setProfile("power-saver");
            else if (k === Qt.Key_2) Power.setProfile("balanced");
            else if (k === Qt.Key_3) Power.setProfile("performance");
            else {
                const ch = e.text.toLowerCase();
                const i = pm.actions.findIndex(a => a.key === ch);
                if (i < 0) return;
                if (pm.armed >= 0 && pm.armed !== i) pm.armed = -1;
                pm.run(i);
            }
            e.accepted = true;
        }

        ColumnLayout {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
            spacing: 0

            // ---------------------------------------------------- header
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 42
                radius: Math.max(0, card.radius - 1)
                color: Theme.surface
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: parent.radius; color: parent.color }
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 16
                    Text {
                        text: "  session"
                        font.family: Theme.mono
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: Theme.accent
                    }
                    Text {
                        text: "@" + (Quickshell.env("USER") || "you")
                        font.family: Theme.mono
                        font.pixelSize: 12
                        color: Theme.dim
                        Layout.leftMargin: 6
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "up " + Power.uptime + (pm.batteryText ? "  ·  " + pm.batteryText : "")
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: Theme.muted
                    }
                }
            }

            Text {
                Layout.leftMargin: 20
                Layout.topMargin: 12
                Layout.bottomMargin: 6
                text: "// pick one · the red ones ask twice"
                font.family: Theme.mono
                font.pixelSize: 11
                color: Theme.dim
            }

            // ---------------------------------------------------- actions
            Repeater {
                model: pm.actions
                Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool on: pm.sel === index
                    readonly property bool isArmed: pm.armed === index
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    implicitHeight: 38
                    radius: 6
                    color: isArmed ? Theme.alpha(Theme.red, 0.18)
                         : on ? Theme.alpha(Theme.accent, 0.12)
                         : rowArea.containsMouse ? Theme.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: 110 } }

                    Rectangle {
                        visible: row.on || row.isArmed
                        width: 2; height: parent.height - 12; radius: 1
                        anchors.verticalCenter: parent.verticalCenter
                        color: row.isArmed ? Theme.red : Theme.accent
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 14
                        spacing: 10
                        Text {
                            text: row.on ? "❯" : " "
                            font.family: Theme.mono
                            font.pixelSize: 13
                            color: row.isArmed ? Theme.red : Theme.accent
                            Layout.preferredWidth: 10
                        }
                        Text {
                            text: row.modelData.icon
                            font.family: Theme.mono
                            font.pixelSize: 14
                            color: row.modelData.c
                            Layout.preferredWidth: 18
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            text: row.modelData.name
                            font.family: Theme.mono
                            font.pixelSize: 13
                            font.weight: row.on ? Font.Bold : Font.Normal
                            color: row.on ? Theme.text : Theme.subtext
                            Layout.preferredWidth: 86
                        }
                        Rectangle {
                            implicitWidth: 20; implicitHeight: 20; radius: 4
                            color: Theme.alpha(Theme.bg, 0.7)
                            border.width: 1
                            border.color: row.on ? Theme.alpha(Theme.accent, 0.6) : Theme.cardHi
                            Text {
                                anchors.centerIn: parent
                                text: row.modelData.key
                                font.family: Theme.mono
                                font.pixelSize: 11
                                color: row.on ? Theme.accent : Theme.muted
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: row.isArmed ? "press " + row.modelData.key + " / enter again to " + row.modelData.name
                                 : (row.on ? "$ " : "") + row.modelData.show
                            font.family: Theme.mono
                            font.pixelSize: 11
                            color: row.isArmed ? Theme.red : row.on ? Theme.muted : Theme.dim
                        }
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: if (pm.armed < 0) pm.sel = row.index
                        onClicked: pm.run(row.index)
                    }
                }
            }

            // ---------------------------------------------------- power profile
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 16
                spacing: 12
                Text { text: "[profile]"; font.family: Theme.mono; font.pixelSize: 12; font.weight: Font.Bold; color: Theme.violet }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 22
                Layout.rightMargin: 22
                Layout.topMargin: 8
                spacing: 12
                Text {
                    visible: !Power.hasProfiles
                    text: "# power-profiles-daemon isn't running · sudo pacman -S power-profiles-daemon"
                    font.family: Theme.mono
                    font.pixelSize: 11
                    color: Theme.dim
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
                Rectangle {
                    visible: Power.hasProfiles
                    implicitWidth: profRow.implicitWidth + 6
                    implicitHeight: 30
                    radius: 6
                    color: Theme.alpha(Theme.surface, 0.8)
                    border.width: 1
                    border.color: Theme.cardHi
                    Row {
                        id: profRow
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: [
                                { v: "power-saver", t: "power-saver", icon: "", n: "1", c: Theme.teal },
                                { v: "balanced",    t: "balanced",    icon: "", n: "2", c: Theme.sky },
                                { v: "performance", t: "performance", icon: "", n: "3", c: Theme.yellow }
                            ]
                            Rectangle {
                                id: pseg
                                required property var modelData
                                readonly property bool on: Power.profile === modelData.v
                                width: psegRow.implicitWidth + 20
                                height: 24
                                radius: 4
                                color: on ? Theme.alpha(modelData.c, 0.2) : psegArea.containsMouse ? Theme.hover : "transparent"
                                border.width: on ? 1 : 0
                                border.color: Theme.alpha(modelData.c, 0.7)
                                Row {
                                    id: psegRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text { text: pseg.modelData.icon; font.family: Theme.mono; font.pixelSize: 11; color: pseg.on ? pseg.modelData.c : Theme.dim }
                                    Text { text: pseg.modelData.t; font.family: Theme.mono; font.pixelSize: 12; font.weight: pseg.on ? Font.Bold : Font.Normal; color: pseg.on ? Theme.text : Theme.muted }
                                    Text { text: pseg.modelData.n; font.family: Theme.mono; font.pixelSize: 10; color: Theme.dim }
                                }
                                MouseArea { id: psegArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Power.setProfile(pseg.modelData.v) }
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true; visible: Power.hasProfiles }
            }

            // ---------------------------------------------------- GPU mode
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 16
                spacing: 12
                Text { text: "[gpu]"; font.family: Theme.mono; font.pixelSize: 12; font.weight: Font.Bold; color: Theme.violet }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 22
                Layout.rightMargin: 22
                Layout.topMargin: 8
                spacing: 6
                Text {
                    visible: !Power.hasEnvy
                    text: "# optional: yay -S envycontrol to switch integrated / hybrid / nvidia"
                    font.family: Theme.mono
                    font.pixelSize: 11
                    color: Theme.dim
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
                Rectangle {
                    visible: Power.hasEnvy
                    implicitWidth: gpuRow.implicitWidth + 6
                    implicitHeight: 30
                    radius: 6
                    color: Theme.alpha(Theme.surface, 0.8)
                    border.width: 1
                    border.color: Theme.cardHi
                    opacity: Power.gpuBusy ? 0.5 : 1
                    Row {
                        id: gpuRow
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: [
                                { v: "integrated", d: "intel only · best battery" },
                                { v: "hybrid",     d: "intel + prime-run" },
                                { v: "nvidia",     d: "rtx always on" }
                            ]
                            Rectangle {
                                id: gseg
                                required property var modelData
                                readonly property bool on: Power.gpu === modelData.v
                                width: gsegText.implicitWidth + 22
                                height: 24
                                radius: 4
                                color: on ? Theme.accent : gsegArea.containsMouse ? Theme.hover : "transparent"
                                Text {
                                    id: gsegText
                                    anchors.centerIn: parent
                                    text: gseg.modelData.v
                                    font.family: Theme.mono
                                    font.pixelSize: 12
                                    font.weight: gseg.on ? Font.Bold : Font.Normal
                                    color: gseg.on ? Theme.onAccent : Theme.muted
                                }
                                MouseArea {
                                    id: gsegArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Power.setGpu(gseg.modelData.v)
                                }
                            }
                        }
                    }
                }
                Text {
                    visible: Power.hasEnvy
                    text: Power.gpuBusy ? "# waiting for your password…"
                        : Power.gpuError ? "# envycontrol: " + Power.gpuError
                        : Power.gpuPending ? "# switched " + Power.bootGpu + " → " + Power.gpu + " · reboot (r) to apply"
                        : "# running " + (Power.gpu || "?") + " · changing it needs a reboot"
                    font.family: Theme.mono
                    font.pixelSize: 11
                    color: Power.gpuError ? Theme.red : Power.gpuPending ? Theme.yellow : Theme.dim
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }

            // ---------------------------------------------------- status line
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 18
                implicitHeight: 26
                radius: Math.max(0, card.radius - 1)
                color: Theme.surface
                Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: parent.radius; color: parent.color }
                Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.border }
                RowLayout {
                    anchors.fill: parent
                    anchors.rightMargin: 14
                    spacing: 12
                    Rectangle {
                        Layout.fillHeight: true
                        implicitWidth: modeText.implicitWidth + 22
                        radius: Math.max(0, card.radius - 1)
                        color: pm.armed >= 0 ? Theme.red : Theme.accent
                        Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: parent.radius; color: parent.color }
                        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: parent.radius; color: parent.color }
                        Text {
                            id: modeText
                            anchors.centerIn: parent
                            text: pm.armed >= 0 ? "CONFIRM" : "NORMAL"
                            font.family: Theme.mono
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: Theme.onAccent
                        }
                    }
                    Text {
                        text: pm.actions[pm.sel].name
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: Theme.subtext
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "j/k move · enter run · 1-3 profile · esc close"
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: Theme.dim
                    }
                }
            }
        }
    }
}
