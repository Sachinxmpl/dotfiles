// Aurora control centre: drops down under the bar on the right.
// Toggle: bar button, Super+A, or `qs ipc call cc toggle`. Esc / click outside closes.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Networking
import Quickshell.Bluetooth

PanelWindow {
    id: cc

    visible: Panels.ccOpen
    anchors { top: true; right: true }
    margins { top: 6; right: 6 }
    exclusiveZone: 0
    implicitWidth: 392
    implicitHeight: card.implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "aurora-cc"
    // Overlay sits above the click-catcher (Scrim.qml), which closes the panel
    WlrLayershell.layer: WlrLayer.Overlay
    // never grab the keyboard exclusively (that can lock you out);
    // click inside the panel once and Esc will close it
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // refresh slow-changing info each time it opens
    onVisibleChanged: if (visible) {
        card.forceActiveFocus();
        appear.restart();
        brightnessGet.running = true;
        profileGet.running = true;
        uptimeGet.running = true;
    }

    // ------------------------------------------------------------ reusable bits
    component Icon: Text {
        font.family: Theme.iconFont
        font.pixelSize: 15
        color: Theme.text
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }
    component Label: Text {
        font.family: Theme.font
        font.pixelSize: 13
        color: Theme.text
        elide: Text.ElideRight
    }
    component Caption: Text {
        font.family: Theme.font
        font.pixelSize: 11
        font.letterSpacing: 1
        color: Theme.muted
    }

    // big two-line toggle tile
    component Tile: Rectangle {
        id: tile
        property string title
        property string subtitle
        property string icon
        property bool on: false
        signal toggled()
        Layout.fillWidth: true
        implicitHeight: 58
        radius: 14
        color: on ? Theme.accent : (tileArea.containsMouse ? Theme.cardHover : Theme.card)
        Behavior on color { ColorAnimation { duration: 140 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 13
            anchors.rightMargin: 10
            spacing: 10
            Icon {
                text: tile.icon
                font.pixelSize: 16
                color: tile.on ? Theme.bg : Theme.subtext
                Layout.preferredWidth: 18
            }
            ColumnLayout {
                spacing: 1
                Layout.fillWidth: true
                Label {
                    text: tile.title
                    font.weight: Font.DemiBold
                    color: tile.on ? Theme.bg : Theme.text
                    Layout.fillWidth: true
                }
                Label {
                    text: tile.subtitle
                    font.pixelSize: 11
                    color: tile.on ? Theme.alpha(Theme.onAccent, 0.75) : Theme.muted
                    Layout.fillWidth: true
                    visible: text !== ""
                }
            }
        }
        MouseArea {
            id: tileArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.toggled()
        }
    }

    // horizontal slider row
    component SliderRow: RowLayout {
        id: srow
        property string icon
        property real value: 0          // 0..1
        property color fill: Theme.text
        signal moved(real v)
        spacing: 12
        Layout.fillWidth: true

        Icon { text: srow.icon; color: Theme.subtext; Layout.preferredWidth: 18 }
        Item {
            Layout.fillWidth: true
            implicitHeight: 22
            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 8
                radius: 4
                color: Theme.card
                Rectangle {
                    width: Math.max(8, track.width * Math.max(0, Math.min(1, srow.value)))
                    height: parent.height
                    radius: 4
                    color: srow.fill
                }
            }
            // knob
            Rectangle {
                width: 16; height: 16; radius: 8
                color: Theme.text
                border.color: Theme.bg
                border.width: 2
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(track.width - width, track.width * srow.value - width / 2))
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function set(mx) { srow.moved(Math.max(0, Math.min(1, mx / width))) }
                onPressed: mouse => set(mouse.x)
                onPositionChanged: mouse => { if (pressed) set(mouse.x) }
                onWheel: wheel => srow.moved(Math.max(0, Math.min(1, srow.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
            }
        }
        Label {
            text: Math.round(srow.value * 100)
            font.pixelSize: 12
            color: Theme.muted
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 26
        }
    }

    // round icon button
    component RoundButton: Rectangle {
        id: rb
        property string icon
        property color iconColor: Theme.subtext
        property color base: Theme.card
        signal clicked()
        implicitWidth: 40; implicitHeight: 40
        radius: 12
        color: rbArea.containsMouse ? Qt.lighter(base, 1.25) : base
        Behavior on color { ColorAnimation { duration: 120 } }
        Icon { anchors.centerIn: parent; text: rb.icon; color: rb.iconColor }
        MouseArea {
            id: rbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rb.clicked()
        }
    }

    function run(cmd) { Quickshell.execDetached(cmd) }
    function close() { Panels.ccOpen = false }

    // ------------------------------------------------------------ live data
    // audio
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [cc.sink, cc.source] }
    readonly property bool sinkReady: sink !== null && sink.audio !== null
    readonly property bool micMuted: source !== null && source.audio !== null && source.audio.muted

    // network + bluetooth
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wifiNetwork: wifiDevice ? (wifiDevice.networks.values.find(n => n.connected) ?? null) : null
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btDevice: Bluetooth.devices.values.find(d => d.connected) ?? null

    // media
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null

    // brightness (brightnessctl -m → "name,class,current,NN%,max")
    property real brightness: 0.5
    Process {
        id: brightnessGet
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(",");
                if (parts.length >= 5) cc.brightness = parseInt(parts[2]) / parseInt(parts[4]);
            }
        }
    }


    // power profile
    property string profile: "balanced"
    readonly property var profiles: ["power-saver", "balanced", "performance"]
    Process {
        id: profileGet
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector { onStreamFinished: cc.profile = text.trim() || "balanced" }
    }

    // night light lives in NightLight.qml (shared with the bar, OSD and Super+N)

    // uptime
    property string uptime: ""
    Process {
        id: uptimeGet
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = Math.floor(parseFloat(text.split(" ")[0]));
                const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
                cc.uptime = h > 0 ? `${h}h ${m}m` : `${m}m`;
            }
        }
    }

    // notifications: newest 5 from the shell's own notification history
    readonly property var notifications: Notifs.history.slice(0, 5)

    readonly property string userName: Quickshell.env("USER") || "you"
    property bool powerMenu: false

    // ------------------------------------------------------------ the card
    Rectangle {
        id: card
        width: parent.width
        implicitHeight: content.implicitHeight + 32
        radius: 20
        color: Theme.alpha(Theme.surface, 0.95)
        border.color: Theme.alpha(Theme.text, 0.10)
        border.width: 1

        // open animation: fade + slide down
        opacity: 0
        transform: Translate { id: slide; y: -10 }
        ParallelAnimation {
            id: appear
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 170; easing.type: Easing.OutCubic }
            NumberAnimation { target: slide; property: "y"; from: -10; to: 0; duration: 220; easing.type: Easing.OutCubic }
        }

        focus: true
        Keys.onEscapePressed: cc.close()

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 14

            // ---- header: user · lock · power
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    implicitWidth: 42; implicitHeight: 42; radius: 21
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.teal }
                        GradientStop { position: 1; color: Theme.violet }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: cc.userName.charAt(0).toUpperCase()
                        font.family: Theme.font
                        font.pixelSize: 17
                        font.weight: Font.Bold
                        color: Theme.bg
                    }
                }
                ColumnLayout {
                    spacing: 1
                    Layout.fillWidth: true
                    Label { text: cc.userName; font.weight: Font.DemiBold; font.pixelSize: 14 }
                    Label { text: "arch · up " + cc.uptime; font.pixelSize: 11; color: Theme.muted }
                }
                RoundButton {
                    icon: "󰸉"
                    onClicked: { Panels.closeAll(); Panels.wallsOpen = true }   // wallpaper picker (Super+W)
                }
                RoundButton {
                    icon: ""
                    onClicked: { cc.close(); cc.run(["loginctl", "lock-session"]) }
                }
                RoundButton {
                    icon: ""
                    iconColor: Theme.pink
                    base: cc.powerMenu ? Theme.alpha(Theme.red, 0.22) : Theme.card
                    onClicked: cc.powerMenu = !cc.powerMenu
                }
            }

            // ---- power menu (revealed by the power button)
            GridLayout {
                visible: cc.powerMenu
                Layout.fillWidth: true
                columns: 4
                columnSpacing: 8
                Repeater {
                    model: [
                        { icon: "", label: "Sleep",    color: Theme.violet, cmd: ["systemctl", "suspend"] },
                        { icon: "", label: "Log out",  color: Theme.sky,    cmd: [] },
                        { icon: "", label: "Restart",  color: Theme.yellow, cmd: ["systemctl", "reboot"] },
                        { icon: "", label: "Shut down", color: Theme.red,   cmd: ["systemctl", "poweroff"] }
                    ]
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4
                        RoundButton {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 56; implicitHeight: 48
                            icon: modelData.icon
                            iconColor: modelData.color
                            onClicked: {
                                cc.close();
                                if (modelData.cmd.length) cc.run(modelData.cmd);
                                else Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.exit()" : "exit");
                            }
                        }
                        Caption { text: modelData.label; Layout.alignment: Qt.AlignHCenter; font.letterSpacing: 0 }
                    }
                }
            }

            // ---- quick toggles
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 8
                columnSpacing: 8

                Tile {
                    icon: ""
                    title: "Wi-Fi"
                    on: Networking.wifiEnabled
                    subtitle: !Networking.wifiEnabled ? "Off" : (cc.wifiNetwork ? cc.wifiNetwork.name : "Not connected")
                    onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                }
                Tile {
                    icon: ""
                    title: "Bluetooth"
                    on: cc.btAdapter !== null && cc.btAdapter.enabled
                    subtitle: !on ? "Off" : (cc.btDevice ? cc.btDevice.name : "On")
                    onToggled: if (cc.btAdapter) cc.btAdapter.enabled = !cc.btAdapter.enabled
                }
                Tile {
                    icon: ""
                    title: "Do not disturb"
                    on: Notifs.dnd
                    subtitle: on ? "Pop-ups hidden" : "Off"
                    onToggled: Notifs.dnd = !Notifs.dnd
                }
                Tile {
                    icon: "󰖔"
                    title: "Night light"
                    on: NightLight.mode !== "off"
                    subtitle: NightLight.summary          // click cycles: off → on → auto
                    onToggled: NightLight.cycle()
                }
                Tile {
                    icon: ""
                    title: "Power"
                    on: cc.profile === "performance"
                    subtitle: cc.profile === "power-saver" ? "Power saver"
                            : cc.profile === "performance" ? "Performance" : "Balanced"
                    onToggled: {
                        const next = cc.profiles[(cc.profiles.indexOf(cc.profile) + 1) % cc.profiles.length];
                        cc.profile = next;
                        cc.run(["powerprofilesctl", "set", next]);
                    }
                }
                Tile {
                    icon: ""
                    title: "Microphone"
                    on: !cc.micMuted
                    subtitle: cc.micMuted ? "Muted" : "On"
                    onToggled: if (cc.source && cc.source.audio) cc.source.audio.muted = !cc.source.audio.muted
                }
            }

            // ---- sliders
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                SliderRow {
                    icon: ""
                    value: cc.brightness
                    onMoved: v => {
                        cc.brightness = Math.max(0.01, v);
                        cc.run(["brightnessctl", "-q", "set", Math.round(Math.max(1, v * 100)) + "%"]);
                    }
                }
                // warmth (only while night light is on or on auto): further right = warmer
                SliderRow {
                    visible: NightLight.mode !== "off"
                    icon: "󰖔"
                    fill: Theme.yellow
                    value: (NightLight.maxTemp - NightLight.temp) / (NightLight.maxTemp - NightLight.minTemp)
                    onMoved: v => NightLight.temp = Math.round((NightLight.maxTemp - v * (NightLight.maxTemp - NightLight.minTemp)) / 50) * 50
                }
                SliderRow {
                    icon: (cc.sinkReady && cc.sink.audio.muted) ? "" : ""
                    value: cc.sinkReady ? cc.sink.audio.volume : 0
                    fill: (cc.sinkReady && cc.sink.audio.muted) ? Theme.dim : Theme.text
                    onMoved: v => {
                        if (!cc.sinkReady) return;
                        cc.sink.audio.muted = false;
                        cc.sink.audio.volume = v;
                    }
                }
            }

            // ---- media
            Rectangle {
                visible: cc.player !== null
                Layout.fillWidth: true
                implicitHeight: 76
                radius: 16
                color: Theme.card

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Rectangle {
                        implicitWidth: 52; implicitHeight: 52
                        radius: 10
                        clip: true
                        gradient: Gradient {
                            GradientStop { position: 0; color: Theme.gradA }
                            GradientStop { position: 1; color: Theme.gradB }
                        }
                        Image {
                            anchors.fill: parent
                            source: cc.player ? cc.player.trackArtUrl : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label {
                            Layout.fillWidth: true
                            text: cc.player ? (cc.player.trackTitle || cc.player.identity) : ""
                            font.weight: Font.DemiBold
                        }
                        Label {
                            Layout.fillWidth: true
                            text: cc.player ? (cc.player.trackArtist || cc.player.identity) : ""
                            font.pixelSize: 11
                            color: Theme.muted
                        }
                    }
                    RowLayout {
                        spacing: 2
                        Repeater {
                            model: [
                                { icon: "", act: "prev" },
                                { icon: "play",   act: "toggle" },
                                { icon: "", act: "next" }
                            ]
                            Rectangle {
                                required property var modelData
                                readonly property bool main: modelData.act === "toggle"
                                implicitWidth: main ? 38 : 30
                                implicitHeight: main ? 38 : 30
                                radius: implicitWidth / 2
                                color: main ? Theme.accent : (mArea.containsMouse ? Theme.hover : "transparent")
                                Icon {
                                    anchors.centerIn: parent
                                    font.pixelSize: main ? 14 : 12
                                    color: main ? Theme.bg : Theme.subtext
                                    text: !main ? modelData.icon
                                        : (cc.player && cc.player.isPlaying ? "" : "")
                                }
                                MouseArea {
                                    id: mArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!cc.player) return;
                                        if (modelData.act === "prev") cc.player.previous();
                                        else if (modelData.act === "next") cc.player.next();
                                        else cc.player.togglePlaying();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---- notifications
            RowLayout {
                Layout.fillWidth: true
                Caption { text: "NOTIFICATIONS"; Layout.fillWidth: true }
                Caption {
                    text: "Clear all"
                    color: Theme.accent
                    font.letterSpacing: 0
                    visible: cc.notifications.length > 0
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notifs.clearAll()
                    }
                }
            }
            Label {
                visible: cc.notifications.length === 0
                text: "You're all caught up"
                font.pixelSize: 12
                color: Theme.dim
            }
            Repeater {
                model: cc.notifications
                Rectangle {
                    id: nItem
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: nCol.implicitHeight + 20
                    radius: 14
                    color: nArea.containsMouse ? Theme.cardHover : Theme.card
                    // click: open it (default action) and clear it
                    MouseArea {
                        id: nArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const a = nItem.modelData.actions.find(x => x.identifier === "default");
                            if (a) { a.invoke(); cc.close(); }
                            nItem.modelData.dismiss();
                        }
                    }
                    ColumnLayout {
                        id: nCol
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 13; rightMargin: 13 }
                        spacing: 2
                        Caption { Layout.fillWidth: true; text: nItem.modelData.appName; font.letterSpacing: 0; elide: Text.ElideRight }
                        Label { Layout.fillWidth: true; text: nItem.modelData.summary || nItem.modelData.appName; font.weight: Font.DemiBold }
                        Label {
                            Layout.fillWidth: true
                            text: nItem.modelData.body.replace(/<[^>]*>/g, "")
                            font.pixelSize: 12
                            color: Theme.muted
                            visible: text !== ""
                        }
                    }
                }
            }
        }
    }
}
