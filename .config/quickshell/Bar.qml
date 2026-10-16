// Aurora top bar: glass strip with grouped segments
//   left:   launcher · workspaces · active window
//   centre: date · clock · now playing
//   right:  wifi · bluetooth · volume · battery | notifications · control centre

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import Quickshell.Networking
import Quickshell.Bluetooth

PanelWindow {
    id: bar

    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.barHeight
    // flush with the screen edge; windows start right below the bar
    exclusiveZone: Theme.barHeight
    color: "transparent"
    WlrLayershell.namespace: "aurora-bar"

    // ------------------------------------------------------------ reusable bits
    component Icon: Text {
        font.family: Theme.iconFont
        font.pixelSize: 15
        color: Theme.subtext
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }

    component Label: Text {
        font.family: Theme.mono
        font.pixelSize: Theme.fontSize
        color: Theme.text
        verticalAlignment: Text.AlignVCenter
    }

    // rounded dark "well" that groups items
    component Well: Rectangle {
        color: Theme.well
        radius: Theme.radiusSm
        implicitHeight: 32
    }

    // square icon button with hover
    component IconButton: Rectangle {
        id: btn
        property string icon: ""
        property color iconColor: Theme.subtext
        property bool highlighted: false
        signal clicked(var mouse)
        implicitWidth: 34
        implicitHeight: 34
        radius: Theme.radiusSm
        color: highlighted ? Theme.accentSoft : (area.containsMouse ? Theme.hover : Theme.well)
        Behavior on color { ColorAnimation { duration: 120 } }

        Icon {
            anchors.centerIn: parent
            text: btn.icon
            color: btn.highlighted ? Theme.accent : btn.iconColor
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: mouse => btn.clicked(mouse)
        }
    }

    // ------------------------------------------------------------ data
    SystemClock { id: clock; precision: SystemClock.Minutes }

    // audio: track the default output so volume/mute stay live
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [bar.sink] }
    readonly property bool sinkReady: sink !== null && sink.audio !== null
    readonly property real volume: sinkReady ? sink.audio.volume : 0
    readonly property bool muted: sinkReady ? sink.audio.muted : false

    // battery
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.isLaptopBattery
    readonly property int batteryPct: hasBattery ? Math.round(battery.percentage * 100) : 0
    readonly property bool charging: hasBattery
        && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged)

    // network
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wifiNetwork: wifiDevice ? (wifiDevice.networks.values.find(n => n.connected) ?? null) : null
    readonly property bool wiredUp: Networking.devices.values.some(d => d.type === DeviceType.Wired && d.connected)

    // bluetooth
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btOn: btAdapter !== null && btAdapter.enabled
    readonly property int btConnected: Bluetooth.devices.values.filter(d => d.connected).length

    // media: prefer whatever is playing, else the first player
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null

    // workspaces: always show 1-5, plus any higher one that exists
    readonly property var workspaceIds: {
        const ids = [1, 2, 3, 4, 5];
        for (const ws of Hyprland.workspaces.values)
            if (ws.id > 0 && !ids.includes(ws.id)) ids.push(ws.id);
        return ids.sort((a, b) => a - b);
    }

    function goToWorkspace(id) {
        const ws = Hyprland.workspaces.values.find(w => w.id === id);
        if (ws) ws.activate();
        else Hyprland.dispatch(Hyprland.usingLua ? `hl.dsp.focus({ workspace = ${id} })` : `workspace ${id}`);
    }

    function run(cmd) { Quickshell.execDetached(cmd) }

    // ------------------------------------------------------------ the strip
    Rectangle {
        id: strip
        anchors.fill: parent
        color: Theme.panel

        // hairline along the bottom edge
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: Theme.border
        }

        // ================= LEFT =================
        RowLayout {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            // launcher: two aurora arcs
            Rectangle {
                implicitWidth: 34; implicitHeight: 34
                radius: Theme.radiusSm
                color: launchArea.containsMouse ? Theme.alpha(Theme.accent, 0.22) : Theme.accentSoft
                Behavior on color { ColorAnimation { duration: 120 } }

                Canvas {
                    anchors.centerIn: parent
                    width: 20; height: 20
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        ctx.strokeStyle = Theme.accent;
                        ctx.lineWidth = 2.2;
                        ctx.lineCap = "round";
                        ctx.beginPath(); ctx.moveTo(2, 16); ctx.bezierCurveTo(5, 5, 15, 5, 18, 16); ctx.stroke();
                        ctx.beginPath(); ctx.moveTo(6, 16); ctx.bezierCurveTo(8, 10.5, 12, 10.5, 14, 16); ctx.stroke();
                    }
                }
                MouseArea {
                    id: launchArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Panels.toggleLauncher()
                }
            }

            // workspaces
            Well {
                implicitWidth: wsRow.implicitWidth + 6
                RowLayout {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: bar.workspaceIds

                        Rectangle {
                            id: wsPill
                            required property int modelData
                            readonly property var ws: Hyprland.workspaces.values.find(w => w.id === modelData) ?? null
                            readonly property bool active: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
                            readonly property bool occupied: ws !== null && ws.toplevels.values.length > 0

                            implicitWidth: active ? 38 : 26
                            implicitHeight: 26
                            radius: 8
                            color: active ? Theme.accent : (wsArea.containsMouse ? Theme.hover : "transparent")
                            Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Label {
                                anchors.centerIn: parent
                                text: wsPill.modelData
                                font.weight: wsPill.active ? Font.DemiBold : Font.Normal
                                color: wsPill.active ? Theme.bg : (wsPill.occupied ? Theme.text : Theme.dim)
                            }
                            // small dot under occupied, inactive workspaces
                            Rectangle {
                                visible: wsPill.occupied && !wsPill.active
                                width: 4; height: 4; radius: 2
                                color: Theme.accent
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 2
                            }
                            MouseArea {
                                id: wsArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bar.goToWorkspace(wsPill.modelData)
                            }
                        }
                    }
                }
                // scroll over workspaces to move between them
                WheelHandler {
                    onWheel: event => {
                        const cur = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1;
                        const next = Math.max(1, cur + (event.angleDelta.y < 0 ? 1 : -1));
                        bar.goToWorkspace(next);
                    }
                }
            }

            // active window title
            Label {
                Layout.maximumWidth: 360
                elide: Text.ElideRight
                color: Theme.muted
                text: Hyprland.activeToplevel && Hyprland.activeToplevel.workspace
                      && Hyprland.focusedWorkspace
                      && Hyprland.activeToplevel.workspace.id === Hyprland.focusedWorkspace.id
                      ? Hyprland.activeToplevel.title : ""
            }
        }

        // ================= CENTRE =================
        RowLayout {
            anchors.centerIn: parent
            spacing: 10

            // date + clock: click opens the dashboard (also Super+D)
            Rectangle {
                implicitHeight: 30
                implicitWidth: clockRow.implicitWidth + 20
                radius: 15
                color: Panels.dashOpen ? Theme.accentSoft : (clockArea.containsMouse ? Theme.hover : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }
                RowLayout {
                    id: clockRow
                    anchors.centerIn: parent
                    spacing: 10
                    Label {
                        text: Qt.formatDateTime(clock.date, "ddd d MMM")
                        font.weight: Font.DemiBold
                    }
                    Label {
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        font.weight: Font.Bold
                        color: Theme.accent
                    }
                }
                MouseArea {
                    id: clockArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Panels.toggleDash()
                }
            }

            // now playing pill (only when a player exists)
            Rectangle {
                visible: bar.player !== null
                implicitHeight: 28
                implicitWidth: musicRow.implicitWidth + 18
                radius: 14
                color: musicArea.containsMouse ? Theme.hover : Theme.well
                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                    id: musicRow
                    anchors.centerIn: parent
                    spacing: 7

                    // little equaliser that dances while playing
                    Row {
                        spacing: 2
                        height: 14
                        Layout.alignment: Qt.AlignVCenter
                        Repeater {
                            model: 4
                            Rectangle {
                                required property int index
                                width: 2
                                radius: 1
                                color: Theme.accent
                                y: (14 - height) / 2
                                height: 5
                                SequentialAnimation on height {
                                    running: bar.player !== null && bar.player.isPlaying
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 12 - index * 2; duration: 260 + index * 70 }
                                    NumberAnimation { to: 4 + index; duration: 300 + index * 50 }
                                }
                            }
                        }
                    }
                    Label {
                        Layout.maximumWidth: 160
                        elide: Text.ElideRight
                        font.pixelSize: 11
                        color: Theme.muted
                        text: bar.player ? (bar.player.trackTitle || bar.player.identity) : ""
                    }
                }
                MouseArea {
                    id: musicArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    // left: play/pause · right: next track
                    onClicked: mouse => {
                        if (!bar.player) return;
                        if (mouse.button === Qt.RightButton) bar.player.next();
                        else bar.player.togglePlaying();
                    }
                }
            }
        }

        // ================= RIGHT =================
        RowLayout {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            // recording: red pulsing dot + timer while aurora-rec runs → click to stop
            Rectangle {
                visible: Recorder.active
                implicitHeight: 32
                implicitWidth: recRow.implicitWidth + 22
                radius: Theme.radiusSm
                color: recArea.containsMouse ? Theme.alpha(Theme.red, 0.30) : Theme.alpha(Theme.red, 0.18)
                Row {
                    id: recRow
                    anchors.centerIn: parent
                    spacing: 8
                    Rectangle {
                        width: 9; height: 9; radius: 5
                        color: Theme.red
                        anchors.verticalCenter: parent.verticalCenter
                        SequentialAnimation on opacity {
                            running: Recorder.active
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 600 }
                            NumberAnimation { to: 1; duration: 600 }
                        }
                    }
                    Text {
                        text: recArea.containsMouse ? "stop" : Recorder.elapsed
                        color: Theme.text
                        font.family: Theme.mono
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    id: recArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Recorder.stop()
                }
            }

            // system: cpu · mem · temp, like a tmux status line → click for the dashboard
            Well {
                implicitWidth: sysRow.implicitWidth + 22
                color: sysArea.containsMouse ? Theme.hover : Theme.well
                Row {
                    id: sysRow
                    anchors.centerIn: parent
                    spacing: 12
                    Kv {
                        key: "cpu"
                        value: Math.round(Stats.cpu) + "%"
                        valueColor: Stats.cpu > 85 ? Theme.red : Stats.cpu > 60 ? Theme.yellow : Theme.text
                    }
                    Kv {
                        key: "mem"
                        value: Stats.memUsed.toFixed(1) + "G"
                        valueChars: 5
                        valueColor: Stats.memPct > 90 ? Theme.red : Stats.memPct > 75 ? Theme.yellow : Theme.text
                    }
                    Kv {
                        visible: Stats.temp > 0
                        key: ""
                        value: Math.round(Stats.temp) + "°"
                        valueChars: 3
                        valueColor: Stats.temp > 85 ? Theme.red : Stats.temp > 72 ? Theme.yellow : Theme.text
                    }
                }
                MouseArea {
                    id: sysArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Panels.toggleDash()
                }
            }

            // dev pill:  branch ● · containers · dev servers  → click for the Dev panel
            Rectangle {
                id: devPill
                readonly property int myPorts: Dev.ports.filter(p => p.pid !== "-").length
                implicitHeight: 32
                implicitWidth: devRow.implicitWidth + 22
                radius: Theme.radiusSm
                color: Panels.devOpen ? Theme.accentSoft : (devArea.containsMouse ? Theme.hover : Theme.well)
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on implicitWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                clip: true

                RowLayout {
                    id: devRow
                    anchors.centerIn: parent
                    spacing: 10

                    Text {
                        visible: Dev.git === null && Dev.running === 0 && devPill.myPorts === 0
                        text: ""
                        color: Theme.subtext
                        font.family: Theme.iconFont
                        font.pixelSize: 14
                    }
                    // git branch of the terminal you're in
                    Row {
                        visible: Dev.git !== null
                        spacing: 5
                        Text { text: ""; color: Theme.violet; font.family: Theme.iconFont; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: Dev.git ? Dev.git.branch : ""
                            color: Theme.text
                            font.family: Theme.iconFont
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 130)
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: Dev.git !== null && Dev.git.changed > 0
                            text: "●"
                            color: Theme.yellow
                            font.pixelSize: 9
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            visible: Dev.git !== null && (Dev.git.ahead > 0 || Dev.git.behind > 0)
                            text: (Dev.git && Dev.git.ahead > 0 ? "↑" + Dev.git.ahead : "") + (Dev.git && Dev.git.behind > 0 ? "↓" + Dev.git.behind : "")
                            color: Theme.sky
                            font.family: Theme.iconFont
                            font.pixelSize: 11
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    // running containers
                    Row {
                        visible: Dev.running > 0
                        spacing: 4
                        Text { text: "󰡨"; color: Theme.sky; font.family: Theme.iconFont; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: Dev.running; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    }
                    // your own listening ports (dev servers)
                    Row {
                        visible: devPill.myPorts > 0
                        spacing: 4
                        Text { text: "󰒋"; color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: devPill.myPorts === 1 ? ":" + Dev.ports.find(p => p.pid !== "-").port : devPill.myPorts
                            color: Theme.text
                            font.family: Theme.iconFont
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
                MouseArea {
                    id: devArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Panels.toggleDev()
                }
            }

            Well {
                implicitWidth: statusRow.implicitWidth + 24
                RowLayout {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 14

                    // night light: shown while the screen is warmed; click cycles off → on → auto
                    Icon {
                        visible: NightLight.active || NightLight.mode === "on"
                        text: "󰖔"
                        color: Theme.yellow
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NightLight.cycle()
                        }
                    }

                    // network: icon + live down/up speed · click opens nmtui · hover shows the network name
                    Item {
                        implicitWidth: netRow.implicitWidth
                        implicitHeight: 24
                        Row {
                            id: netRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 7
                            Icon {
                                text: bar.wiredUp ? "" : ""
                                color: (bar.wifiNetwork || bar.wiredUp) ? Theme.subtext : Theme.dim
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Kv { key: "↓"; value: Stats.rate(Stats.rxRate); valueColor: Stats.rxRate > 1048576 ? Theme.accent : Theme.text; anchors.verticalCenter: parent.verticalCenter }
                            Kv { key: "↑"; value: Stats.rate(Stats.txRate); valueColor: Stats.txRate > 1048576 ? Theme.violet : Theme.text; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea {
                            id: netArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bar.run(["kitty", "--class", "aurora-float", "-e", "nmtui"])
                        }
                        // tooltip: ssid · interface
                        Rectangle {
                            visible: netArea.containsMouse
                            anchors.top: parent.bottom
                            anchors.topMargin: 10
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: netTip.implicitWidth + 16; height: 24; radius: 8
                            color: Theme.surface
                            border.width: 1; border.color: Theme.line
                            Text {
                                id: netTip
                                anchors.centerIn: parent
                                text: (bar.wifiNetwork ? bar.wifiNetwork.name : bar.wiredUp ? "ethernet" : "offline") + "  ·  " + Stats.iface
                                color: Theme.text
                                font.family: Theme.mono
                                font.pixelSize: 11
                            }
                        }
                    }

                    // bluetooth: click toggles power, teal when a device is connected
                    Icon {
                        visible: bar.btAdapter !== null
                        text: ""
                        color: !bar.btOn ? Theme.dim : (bar.btConnected > 0 ? Theme.accent : Theme.subtext)
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (bar.btAdapter) bar.btAdapter.enabled = !bar.btAdapter.enabled
                        }
                    }

                    // volume: click mutes, scroll changes
                    Item {
                        implicitWidth: volRow.implicitWidth
                        implicitHeight: volRow.implicitHeight
                        RowLayout {
                            id: volRow
                            anchors.fill: parent
                            spacing: 5
                            Icon {
                                text: bar.muted ? "" : (bar.volume < 0.4 ? "" : "")
                                color: bar.muted ? Theme.red : Theme.subtext
                            }
                            Label {
                                text: bar.muted ? "muted" : Math.round(bar.volume * 100)
                                color: Theme.subtext
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (bar.sinkReady) bar.sink.audio.muted = !bar.sink.audio.muted
                            onWheel: wheel => {
                                if (!bar.sinkReady) return;
                                const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                                bar.sink.audio.volume = Math.max(0, Math.min(1, bar.sink.audio.volume + step));
                            }
                        }
                    }

                    // battery
                    RowLayout {
                        visible: bar.hasBattery
                        spacing: 5
                        Icon {
                            text: bar.charging ? ""
                                : bar.batteryPct > 85 ? ""
                                : bar.batteryPct > 60 ? ""
                                : bar.batteryPct > 35 ? ""
                                : bar.batteryPct > 12 ? "" : ""
                            color: bar.charging ? Theme.accent
                                 : bar.batteryPct <= 15 ? Theme.red : Theme.subtext
                        }
                        Label {
                            text: bar.batteryPct + "%"
                            color: bar.batteryPct <= 15 && !bar.charging ? Theme.red : Theme.subtext
                        }
                    }
                }
            }

            // notifications: left = open list (control centre) · right = do not disturb
            IconButton {
                icon: Notifs.dnd ? "" : ""
                iconColor: Notifs.dnd ? Theme.dim : Theme.subtext
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) Notifs.dnd = !Notifs.dnd;
                    else Panels.toggleCc();
                }
                // unread badge
                Rectangle {
                    visible: Notifs.history.length > 0 && !Notifs.dnd
                    anchors { top: parent.top; right: parent.right; topMargin: 4; rightMargin: 4 }
                    width: Math.max(14, badgeText.implicitWidth + 6)
                    height: 14
                    radius: 7
                    color: Theme.pink
                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: Notifs.history.length > 9 ? "9+" : Notifs.history.length
                        font.family: Theme.font
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: Theme.bg
                    }
                }
            }

            // control centre (also Super+A)
            IconButton {
                icon: ""
                highlighted: true
                color: Panels.ccOpen ? Theme.alpha(Theme.accent, 0.30) : Theme.accentSoft
                onClicked: Panels.toggleCc()
            }
        }
    }
}
