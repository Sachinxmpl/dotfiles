// Aurora media panel: now playing + a live spectrum (cava), drops down from the bar.
//   open:  Super+Shift+M  ·  click the now-playing pill  ·  qs ipc call media toggle
//   keys:  Space play/pause · h/l seek 5 s (H/L 30 s) · 0–9 jump to 0–90 % · n next · p previous
//          s shuffle · r loop · -/+ volume · Tab next player · v bars/wave · o open the app · Esc close
//   mouse: click/drag the progress bar to seek · click the volume meter · scroll anywhere for volume
//          move the cursor off the panel and it closes (once the cursor has been on it)

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

PanelWindow {
    id: md

    property bool shown: false
    visible: shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "media"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ------------------------------------------------------------ which player
    readonly property var players: Mpris.players.values
    property string chosen: ""                         // dbusName picked with Tab / the tabs
    readonly property var player: players.find(p => p.dbusName === chosen)
                                  ?? players.find(p => p.isPlaying) ?? players[0] ?? null
    function cyclePlayer(d) {
        if (players.length < 2) return;
        const i = Math.max(0, players.indexOf(player));
        chosen = players[(i + d + players.length) % players.length].dbusName;
    }
    function nameOf(p) { return p ? (p.identity || p.desktopEntry || "player").toLowerCase() : "" }

    // ------------------------------------------------------------ time
    property real pos: 0                               // seconds, refreshed below
    Timer {
        interval: 250; repeat: true; triggeredOnStart: true
        running: md.shown && md.player !== null
        onTriggered: { md.player.positionChanged(); md.pos = md.player.position; }
    }
    readonly property real len: player && player.length > 0 ? player.length : 0
    readonly property bool canSeek: player !== null && player.canSeek && len > 0
    function fmt(s) {
        s = Math.max(0, Math.floor(s || 0));
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, x = String(s % 60).padStart(2, "0");
        return h > 0 ? h + ":" + String(m).padStart(2, "0") + ":" + x : m + ":" + x;
    }
    function seekTo(sec) {
        if (!canSeek) return;
        sec = Math.max(0, Math.min(len - 1, sec));
        player.position = sec;
        pos = sec;
    }
    function seekBy(d) { if (canSeek) seekTo(pos + d) }

    // ------------------------------------------------------------ volume (the player's own, else the system's)
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [md.sink] }
    readonly property bool ownVolume: player !== null && player.volumeSupported && player.canControl
    readonly property real vol: ownVolume ? player.volume : (sink && sink.audio ? sink.audio.volume : 0)
    function setVol(v) {
        v = Math.max(0, Math.min(1, Math.round(v * 100) / 100));
        if (ownVolume) player.volume = v;
        else if (sink && sink.audio) sink.audio.volume = v;
    }

    // ------------------------------------------------------------ toggles
    function toggleShuffle() { if (player && player.shuffleSupported) player.shuffle = !player.shuffle }
    function cycleLoop() {
        if (!player || !player.loopSupported) return;
        const s = player.loopState;
        player.loopState = s === MprisLoopState.None ? MprisLoopState.Playlist
                         : s === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None;
    }
    readonly property string loopName: !player || !player.loopSupported ? "—"
        : player.loopState === MprisLoopState.Track ? "track" : player.loopState === MprisLoopState.Playlist ? "list" : "off"
    readonly property string style: Settings.o.vizStyle === "wave" ? "wave" : "bars"
    function toggleStyle() { Settings.o.vizStyle = style === "bars" ? "wave" : "bars" }

    // ------------------------------------------------------------ open / close
    function close() { Panels.mediaOpen = false }

    // close when the cursor leaves the panel. Only after it has been on it, so opening
    // with Super+Shift+M while the mouse is elsewhere doesn't close it straight away.
    property bool wasInside: false
    Timer {
        id: leaveTimer
        interval: 350                           // short grace period for a wobbly hand
        onTriggered: if (!cardHover.hovered) md.close()
    }
    Connections {
        target: Panels
        function onMediaOpenChanged() {
            if (Panels.mediaOpen) {
                hide.stop();
                md.shown = true;
                md.wasInside = false;
                leaveTimer.stop();
                if (md.player) md.pos = md.player.position;
                Cava.retry();
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
        NumberAnimation { target: backdrop; property: "opacity"; to: 0.25; duration: 160 }
        NumberAnimation { target: slide; property: "y"; from: -16; to: 0; duration: 240; easing.type: Easing.OutQuint }
        NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 160 }
    }
    ParallelAnimation {
        id: hide
        onFinished: md.shown = false
        NumberAnimation { target: backdrop; property: "opacity"; to: 0; duration: 120 }
        NumberAnimation { target: slide; property: "y"; to: -10; duration: 140; easing.type: Easing.InCubic }
        NumberAnimation { target: card; property: "opacity"; to: 0; duration: 120 }
    }

    Rectangle { id: backdrop; anchors.fill: parent; color: "black"; opacity: 0 }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: md.close() }

    // ------------------------------------------------------------ small parts
    component Mono: Text {
        font.family: Theme.mono
        font.pixelSize: 11
        color: Theme.muted
    }
    component Btn: Rectangle {
        id: b
        property string icon: ""
        property bool big: false
        property bool on: false
        property bool enabledish: true
        signal clicked()
        implicitWidth: big ? 46 : 34
        implicitHeight: implicitWidth
        radius: big ? implicitWidth / 2 : 8
        color: big ? Theme.accent : on ? Theme.accentSoft : bArea.containsMouse ? Theme.hover : "transparent"
        opacity: enabledish ? 1 : 0.35
        scale: bArea.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Text {
            anchors.centerIn: parent
            text: b.icon
            font.family: Theme.iconFont
            font.pixelSize: b.big ? 20 : 16
            color: b.big ? Theme.onAccent : b.on ? Theme.accent : Theme.subtext
        }
        MouseArea { id: bArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (b.enabledish) b.clicked() }
    }

    // ============================================================ the card
    Rectangle {
        id: card
        objectName: "card"
        anchors.top: parent.top
        anchors.topMargin: Theme.barHeight + 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: 640
        height: col.implicitHeight + 2
        radius: Theme.radius
        color: Theme.bg
        border.width: 1
        border.color: Theme.alpha(Theme.accent, 0.3)
        clip: true
        transform: Translate { id: slide; y: 0 }
        focus: true

        HoverHandler {
            id: cardHover
            onHoveredChanged: {
                if (hovered) { md.wasInside = true; leaveTimer.stop(); }
                else if (md.wasInside && Panels.mediaOpen) leaveTimer.restart();
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: card.forceActiveFocus()
            onWheel: w => md.setVol(md.vol + (w.angleDelta.y > 0 ? 0.05 : -0.05))
        }

        Keys.onPressed: e => {
            const k = e.key, shift = e.modifiers & Qt.ShiftModifier, p = md.player;
            if (k === Qt.Key_Escape || k === Qt.Key_Q) md.close();
            else if (!p) return;
            else if (k === Qt.Key_Space || k === Qt.Key_K) p.togglePlaying();
            else if (k === Qt.Key_H || k === Qt.Key_Left) md.seekBy(shift ? -30 : -5);
            else if (k === Qt.Key_L || k === Qt.Key_Right) md.seekBy(shift ? 30 : 5);
            else if (k >= Qt.Key_0 && k <= Qt.Key_9) md.seekTo(md.len * (k - Qt.Key_0) / 10);
            else if (k === Qt.Key_N || k === Qt.Key_J || k === Qt.Key_Down) { if (p.canGoNext) p.next(); }
            else if (k === Qt.Key_P || k === Qt.Key_Up) { if (p.canGoPrevious) p.previous(); }
            else if (k === Qt.Key_S) md.toggleShuffle();
            else if (k === Qt.Key_R) md.cycleLoop();
            else if (k === Qt.Key_Minus || k === Qt.Key_Underscore) md.setVol(md.vol - 0.05);
            else if (k === Qt.Key_Plus || k === Qt.Key_Equal) md.setVol(md.vol + 0.05);
            else if (k === Qt.Key_Tab) md.cyclePlayer(1);
            else if (k === Qt.Key_Backtab) md.cyclePlayer(-1);
            else if (k === Qt.Key_V) md.toggleStyle();
            else if (k === Qt.Key_O) { if (p.canRaise) { p.raise(); md.close(); } }
            else return;
            e.accepted = true;
        }

        // album art, blown up and faded, as the card's backdrop
        Image {
            anchors.fill: parent
            source: md.player ? md.player.trackArtUrl : ""
            fillMode: Image.PreserveAspectCrop
            opacity: status === Image.Ready ? 0.10 : 0
            asynchronous: true
            sourceSize.width: 64                 // tiny on purpose: upscaled it reads as a blur
            smooth: true
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
            spacing: 0

            // ---------------------------------------------------- header: player tabs
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                color: Theme.alpha(Theme.surface, 0.85)
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 10
                    spacing: 8
                    Text { text: "❯"; font.family: Theme.mono; font.pixelSize: 13; color: Theme.accent }
                    Text { text: "media"; font.family: Theme.mono; font.pixelSize: 13; font.weight: Font.Bold; color: Theme.text }
                    Item { implicitWidth: 6 }
                    Repeater {
                        model: md.players
                        Rectangle {
                            required property var modelData
                            readonly property bool cur: modelData === md.player
                            objectName: "tab:" + md.nameOf(modelData)
                            implicitWidth: tabRow.implicitWidth + 16
                            implicitHeight: 24
                            radius: 5
                            color: cur ? Theme.accentSoft : tabArea.containsMouse ? Theme.hover : "transparent"
                            border.width: 1
                            border.color: cur ? Theme.alpha(Theme.accent, 0.6) : Theme.cardHi
                            Row {
                                id: tabRow
                                anchors.centerIn: parent
                                spacing: 6
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 6; height: 6; radius: 3
                                    color: modelData.isPlaying ? Theme.accent : Theme.dim
                                }
                                Mono { text: md.nameOf(modelData); color: cur ? Theme.accent : Theme.muted }
                            }
                            MouseArea { id: tabArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: md.chosen = modelData.dbusName }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Btn {
                        icon: "󰏌"
                        implicitWidth: 28
                        visible: md.player !== null && md.player.canRaise
                        onClicked: { md.player.raise(); md.close(); }
                    }
                }
            }

            // ---------------------------------------------------- nothing playing
            Item {
                visible: md.player === null
                Layout.fillWidth: true
                implicitHeight: 190
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰝛"; font.family: Theme.iconFont; font.pixelSize: 40; color: Theme.dim }
                    Mono { anchors.horizontalCenter: parent.horizontalCenter; text: "# no players"; font.pixelSize: 13; color: Theme.muted }
                    Mono { anchors.horizontalCenter: parent.horizontalCenter; text: "start spotify, a video or anything that plays sound"; color: Theme.dim }
                }
            }

            // ---------------------------------------------------- now playing
            RowLayout {
                visible: md.player !== null
                Layout.fillWidth: true
                Layout.margins: 18
                Layout.bottomMargin: 10
                spacing: 18

                ClippingRectangle {
                    implicitWidth: 132
                    implicitHeight: 132
                    radius: Theme.radiusSm
                    color: Theme.card
                    Text {
                        anchors.centerIn: parent
                        visible: art.status !== Image.Ready
                        text: "󰝚"
                        font.family: Theme.iconFont
                        font.pixelSize: 46
                        color: Theme.dim
                    }
                    Image {
                        id: art
                        anchors.fill: parent
                        source: md.player ? md.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 264
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Text {
                        Layout.fillWidth: true
                        text: md.player ? (md.player.trackTitle || "Unknown track") : ""
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                        color: Theme.text
                    }
                    Text {
                        Layout.fillWidth: true
                        text: md.player ? (md.player.trackArtist || md.player.identity) : ""
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 13
                        color: Theme.subtext
                    }
                    Mono {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: md.player && md.player.trackAlbum ? "from " + md.player.trackAlbum : ""
                        elide: Text.ElideRight
                        color: Theme.dim
                    }
                    Item { Layout.fillHeight: true; implicitHeight: 8 }

                    // controls
                    RowLayout {
                        spacing: 6
                        Btn {
                            objectName: "shuffleBtn"
                            icon: "󰒟"
                            on: md.player !== null && md.player.shuffle
                            enabledish: md.player !== null && md.player.shuffleSupported
                            onClicked: md.toggleShuffle()
                        }
                        Btn { icon: "󰒮"; enabledish: md.player !== null && md.player.canGoPrevious; onClicked: md.player.previous() }
                        Btn {
                            objectName: "playBtn"
                            big: true
                            icon: md.player && md.player.isPlaying ? "󰏤" : "󰐊"
                            onClicked: md.player.togglePlaying()
                        }
                        Btn { icon: "󰒭"; enabledish: md.player !== null && md.player.canGoNext; onClicked: md.player.next() }
                        Btn {
                            objectName: "loopBtn"
                            icon: md.loopName === "track" ? "󰑘" : "󰑖"
                            on: md.loopName === "track" || md.loopName === "list"
                            enabledish: md.player !== null && md.player.loopSupported
                            onClicked: md.cycleLoop()
                        }
                    }
                }
            }

            // ---------------------------------------------------- spectrum
            Item {
                id: viz
                objectName: "viz"
                visible: md.player !== null
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                implicitHeight: 96
                readonly property real mid: height * 0.72          // baseline; below it is the reflection

                // scope grid
                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        y: Math.round(viz.mid * index / 3)
                        width: viz.width; height: 1
                        color: Theme.alpha(Theme.text, index === 3 ? 0.12 : 0.04)
                    }
                }
                Mono { anchors { left: parent.left; bottom: parent.bottom } text: "40 Hz"; font.pixelSize: 9; color: Theme.dim; opacity: 0.7 }
                Mono { anchors { right: parent.right; bottom: parent.bottom } text: "16 kHz"; font.pixelSize: 9; color: Theme.dim; opacity: 0.7 }

                // bars (mirrored, fading into the reflection)
                Row {
                    visible: md.style === "bars"
                    anchors.fill: parent
                    spacing: 3
                    Repeater {
                        model: Cava.bars
                        Item {
                            required property int index
                            readonly property real v: Cava.values[index] || 0
                            width: (viz.width - (Cava.bars - 1) * 3) / Cava.bars
                            height: viz.height
                            readonly property color tint: Qt.tint(Theme.accent, Theme.alpha(Theme.violet, index / Cava.bars))
                            Rectangle {
                                width: parent.width
                                height: Math.max(2, parent.v * (viz.mid - 4))
                                y: viz.mid - height
                                radius: Math.min(2, width / 2)
                                color: parent.tint
                                Behavior on height { NumberAnimation { duration: 60 } }
                            }
                            Rectangle {
                                width: parent.width
                                height: Math.max(1, parent.v * (viz.height - viz.mid - 2))
                                y: viz.mid + 2
                                radius: Math.min(2, width / 2)
                                color: parent.tint
                                opacity: 0.22
                                Behavior on height { NumberAnimation { duration: 60 } }
                            }
                        }
                    }
                }

                // wave
                Canvas {
                    id: wave
                    visible: md.style === "wave"
                    anchors.fill: parent
                    renderStrategy: Canvas.Cooperative
                    property var vals: Cava.values
                    onValsChanged: if (visible) requestPaint()
                    onVisibleChanged: if (visible) requestPaint()
                    onPaint: {
                        const c = getContext("2d"), w = width, mid = viz.mid, v = vals, n = Cava.bars;
                        c.reset();
                        const pts = [];
                        for (let i = 0; i < n; i++) pts.push([w * i / (n - 1), mid - 2 - (v[i] || 0) * (mid - 6)]);
                        const path = (yf) => {
                            c.beginPath();
                            c.moveTo(0, mid);
                            c.lineTo(pts[0][0], yf(pts[0][1]));
                            for (let i = 1; i < n; i++) {
                                const xc = (pts[i - 1][0] + pts[i][0]) / 2;
                                c.quadraticCurveTo(pts[i - 1][0], yf(pts[i - 1][1]), xc, yf((pts[i - 1][1] + pts[i][1]) / 2));
                            }
                            c.lineTo(w, yf(pts[n - 1][1]));
                            c.lineTo(w, mid);
                            c.closePath();
                        };
                        const g = c.createLinearGradient(0, 0, w, 0);
                        g.addColorStop(0, Theme.accent);
                        g.addColorStop(1, Theme.violet);
                        // reflection
                        c.globalAlpha = 0.14;
                        c.fillStyle = g;
                        path(y => mid + (mid - y) * (viz.height - mid) / mid);
                        c.fill();
                        // body + outline
                        c.globalAlpha = 0.28;
                        path(y => y);
                        c.fill();
                        c.globalAlpha = 1;
                        c.strokeStyle = g;
                        c.lineWidth = 2;
                        c.stroke();
                    }
                }

                // why there is no spectrum
                Rectangle {
                    visible: !Cava.live
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -10
                    implicitWidth: why.implicitWidth + 20
                    implicitHeight: 24
                    radius: 5
                    color: Theme.alpha(Theme.bg, 0.85)
                    border.width: 1
                    border.color: Theme.cardHi
                    Mono {
                        id: why
                        anchors.centerIn: parent
                        text: !Cava.available ? "# sudo pacman -S cava   → live spectrum"
                            : Cava.error !== "" ? "# cava: " + Cava.error
                            : !Cava.wanted ? "# visualizer off  (settings → bar)"
                            : "# paused"
                        color: Cava.error !== "" ? Theme.red : Theme.muted
                    }
                }
            }

            // ---------------------------------------------------- progress
            RowLayout {
                visible: md.player !== null
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 10
                spacing: 12
                Mono { text: md.fmt(md.pos); font.features: { "tnum": 1 }; color: Theme.subtext }
                Item {
                    id: track
                    objectName: "track"
                    Layout.fillWidth: true
                    implicitHeight: 18
                    readonly property real frac: md.len > 0 ? Math.min(1, md.pos / md.len) : 0
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: 4; radius: 2
                        color: Theme.card
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * (seekArea.pressed ? seekArea.preview : track.frac); height: 4; radius: 2
                        color: Theme.accent
                    }
                    Rectangle {
                        visible: md.canSeek
                        x: parent.width * (seekArea.pressed ? seekArea.preview : track.frac) - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: seekArea.containsMouse || seekArea.pressed ? 14 : 10; height: width; radius: width / 2
                        color: Theme.text
                        border.width: 3
                        border.color: Theme.accent
                        Behavior on width { NumberAnimation { duration: 90 } }
                    }
                    // hover time
                    Rectangle {
                        visible: md.canSeek && (seekArea.containsMouse || seekArea.pressed)
                        x: Math.max(0, Math.min(parent.width - width, seekArea.hoverX - width / 2))
                        y: -22
                        implicitWidth: hoverT.implicitWidth + 10; implicitHeight: 18; radius: 4
                        color: Theme.surface
                        border.width: 1; border.color: Theme.cardHi
                        Mono { id: hoverT; anchors.centerIn: parent; font.pixelSize: 10; text: md.fmt(md.len * seekArea.hoverX / track.width); color: Theme.text }
                    }
                    MouseArea {
                        id: seekArea
                        anchors.fill: parent
                        anchors.topMargin: -6
                        anchors.bottomMargin: -6
                        enabled: md.canSeek
                        hoverEnabled: true
                        cursorShape: md.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
                        property real hoverX: 0
                        property real preview: 0
                        onPositionChanged: m => { hoverX = Math.max(0, Math.min(width, m.x)); preview = hoverX / width; }
                        onPressed: m => { hoverX = Math.max(0, Math.min(width, m.x)); preview = hoverX / width; }
                        onReleased: md.seekTo(md.len * preview)
                    }
                }
                Mono { text: md.len > 0 ? md.fmt(md.len) : "live"; font.features: { "tnum": 1 }; color: Theme.dim }
            }

            // ---------------------------------------------------- volume
            RowLayout {
                visible: md.player !== null
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 8
                Layout.bottomMargin: 14
                spacing: 10
                Mono { text: md.vol <= 0 ? "󰝟" : md.vol < 0.4 ? "󰕿" : md.vol < 0.75 ? "󰖀" : "󰕾"; font.pixelSize: 14; color: Theme.subtext }
                Item {
                    id: meter
                    objectName: "meter"
                    readonly property int cells: 24
                    implicitWidth: cellRow.implicitWidth
                    implicitHeight: 16
                    Row {
                    id: cellRow
                    anchors.bottom: parent.bottom
                    spacing: 2
                    Repeater {
                        model: meter.cells
                        Rectangle {
                            required property int index
                            readonly property bool lit: (index + 0.5) / meter.cells <= md.vol
                            width: 9; height: 4 + index * 0.5
                            anchors.bottom: parent.bottom
                            radius: 1
                            color: lit ? Qt.tint(Theme.accent, Theme.alpha(Theme.violet, index / meter.cells)) : Theme.card
                        }
                    }
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onPressed: m => md.setVol((m.x - 4 + 2) / meter.width)
                        onPositionChanged: m => { if (pressed) md.setVol((m.x - 4 + 2) / meter.width) }
                    }
                }
                Mono { text: Math.round(md.vol * 100) + "%"; font.features: { "tnum": 1 }; color: Theme.subtext }
                Mono { text: md.ownVolume ? "(" + md.nameOf(md.player) + ")" : "(system)"; color: Theme.dim }
                Item { Layout.fillWidth: true }
                Mono { text: "shuffle " + (md.player && md.player.shuffleSupported ? (md.player.shuffle ? "on" : "off") : "—") + "  ·  loop " + md.loopName; color: Theme.dim }
            }

            // ---------------------------------------------------- status line
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 26
                radius: Math.max(0, card.radius - 1)
                color: Theme.surface
                Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: parent.radius; color: parent.color }
                Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.border }
                RowLayout {
                    anchors.fill: parent
                    anchors.rightMargin: 12
                    spacing: 10
                    Rectangle {
                        Layout.fillHeight: true
                        implicitWidth: modeText.implicitWidth + 20
                        radius: Math.max(0, card.radius - 1)
                        color: !md.player ? Theme.dim : md.player.isPlaying ? Theme.accent : Theme.yellow
                        Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: parent.radius; color: parent.color }
                        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: parent.radius; color: parent.color }
                        Text {
                            id: modeText
                            anchors.centerIn: parent
                            text: !md.player ? "IDLE" : md.player.isPlaying ? "PLAYING" : "PAUSED"
                            font.family: Theme.mono; font.pixelSize: 11; font.weight: Font.Bold
                            color: Theme.onAccent
                        }
                    }
                    Mono { text: md.style; color: Theme.dim }
                    Item { Layout.fillWidth: true }
                    Mono {
                        text: "␣ play · h/l seek · 0-9 jump · n/p track · s r · -/+ vol · tab player · v viz"
                        font.pixelSize: 10
                        color: Theme.dim
                    }
                }
            }
        }
    }
}
