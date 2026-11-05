// Aurora waves: Wi-Fi and Bluetooth as a sea of waves + an nmcli-style table
//   open:  Super+I (wifi) · Super+Shift+I (bluetooth) · click the bar's wifi / bluetooth icons
//   every network / device is a wave: near you (bottom, big, bright) = strong signal,
//   out at the horizon (top, small, faint) = weak. bluetooth: connected · paired · nearby
//   click a wave or its buoy to select · double-click to connect
//   keys:  j/k move · Enter connect · d disconnect · f forget (twice) · t radio on/off · o (bluetooth) play sound here
//          r rescan · Tab / w / b switch wifi ↔ bluetooth · Esc close

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Networking
import Quickshell.Bluetooth

PanelWindow {
    id: rd

    property bool shown: false
    visible: shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "radar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property string mode: Panels.radarMode           // "wifi" | "bt"
    readonly property bool isWifi: mode === "wifi"

    // ------------------------------------------------------------ data
    readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property var nets: {
        if (!wifiDev || !wifiOn) return [];
        return wifiDev.networks.values
            .filter(n => n.name && n.name.length > 0)
            .sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength));
    }

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: adapter !== null && adapter.enabled
    function btRank(d) { return d.connected ? 2 : d.paired ? 1 : 0 }
    function btName(d) { return d.name || d.deviceName || d.address }
    readonly property var btDevs: {
        if (!btOn) return [];
        return Bluetooth.devices.values
            .filter(d => d.paired || d.connected || (d.deviceName && d.deviceName.length > 0))
            .sort((a, b) => (rd.btRank(b) - rd.btRank(a)) || rd.btName(a).localeCompare(rd.btName(b)));
    }

    readonly property var items: isWifi ? nets : btDevs
    function keyOf(x) { return isWifi ? x.name : x.address }
    function nameOf(x) { return isWifi ? x.name : btName(x) }
    function liveOf(x) { return x.connected }

    property string selKey: ""
    readonly property int selIndex: items ? items.findIndex(x => rd.keyOf(x) === rd.selKey) : -1
    readonly property var cur: !items ? null : selIndex >= 0 ? items[selIndex] : (items.length ? items[0] : null)
    onItemsChanged: if (items && selIndex < 0 && items.length) selKey = keyOf(items[0])
    onModeChanged: { selKey = items && items.length ? keyOf(items[0]) : ""; armed = ""; if (prompting) cancelPrompt(); paintRings() }
    function move(d) {
        if (!items.length) return;
        const i = Math.max(0, Math.min(items.length - 1, (selIndex < 0 ? 0 : selIndex) + d));
        selKey = keyOf(items[i]);
        armed = "";
    }

    // ------------------------------------------------------------ looks
    function hash(s) {
        let h = 2166136261;
        for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; }
        return h;
    }
    // 0 = far out at the horizon (weak), 1 = right in front of you (strong)
    function depthOf(x) {
        if (isWifi) return Math.max(0, Math.min(1, x.signalStrength));
        const base = x.connected ? 0.95 : x.paired ? 0.6 : 0.27;
        return base + ((hash(x.address || "") >>> 9) % 100 - 50) / 1500;    // small jitter so waves don't stack
    }
    function colorOf(x) {
        if (x.connected) return Theme.accent;
        if (isWifi) return x.known ? Theme.sky : (x.security === WifiSecurityType.Open || x.security === WifiSecurityType.Owe) ? Theme.yellow : Theme.violet;
        return x.paired ? Theme.sky : Theme.violet;
    }
    function secName(t) {
        switch (t) {
        case WifiSecurityType.Open: return "open";
        case WifiSecurityType.Owe: return "owe";
        case WifiSecurityType.Sae:
        case WifiSecurityType.Wpa3SuiteB192: return "wpa3";
        case WifiSecurityType.Wpa2Psk: return "wpa2";
        case WifiSecurityType.WpaPsk: return "wpa";
        case WifiSecurityType.Wpa2Eap:
        case WifiSecurityType.WpaEap: return "eap";
        case WifiSecurityType.StaticWep:
        case WifiSecurityType.DynamicWep: return "wep";
        default: return "?";
        }
    }
    function needsPsk(x) {
        return !x.known && [WifiSecurityType.Wpa2Psk, WifiSecurityType.WpaPsk, WifiSecurityType.Sae].indexOf(x.security) >= 0;
    }
    function btGlyph(icon) {
        const i = icon || "";
        if (i.indexOf("headset") >= 0 || i.indexOf("headphone") >= 0) return "";
        if (i.indexOf("audio") >= 0) return "";
        if (i.indexOf("mouse") >= 0) return "";
        if (i.indexOf("keyboard") >= 0) return "";
        if (i.indexOf("gaming") >= 0) return "";
        if (i.indexOf("phone") >= 0) return "";
        if (i.indexOf("computer") >= 0) return "";
        return "";
    }
    function bars(s) { const n = Math.max(1, Math.ceil(s * 4)); return ["▂▄▆█".slice(0, n), "▂▄▆█".slice(n)] }

    // ------------------------------------------------------------ log (bottom of the table)
    property var logLines: []
    function log(s, c) {
        const l = logLines.slice(-4);
        l.push({ t: Qt.formatTime(new Date(), "HH:mm:ss"), s: s, c: c || Theme.muted });
        logLines = l;
    }

    // ------------------------------------------------------------ actions
    property var pendingNet: null
    property var pendingDev: null
    property string armed: ""                 // key waiting for a second "f"
    property bool prompting: false
    property var promptNet: null

    function activate(x) {
        if (!x) return;
        if (isWifi) {
            if (x.connected) { log("already connected to " + x.name); return; }
            pendingNet = x;
            if (needsPsk(x)) { askPassword(x); return; }
            log("connecting → " + x.name + " …", Theme.sky);
            x.connect();
        } else {
            pendingDev = x;
            if (x.connected) { log("disconnecting " + btName(x) + " …"); x.disconnect(); }
            else if (!x.paired) { log("pairing with " + btName(x) + " … (confirm on the device if asked)", Theme.sky); x.pair(); }
            else { log("connecting → " + btName(x) + " …", Theme.sky); x.trusted = true; x.connect(); }
        }
    }
    // bluetooth audio: headphones/speakers show up as a sound output
    function isAudioDev(d) { return d && /^audio-|headset|headphone|speaker/.test(d.icon || "") }
    function sinkFor(d) {
        if (!d || !d.address) return null;
        const a = d.address.replace(/:/g, "_").toUpperCase();
        return Audio.allSinks.find(n => n.name.toUpperCase().indexOf(a) >= 0) ?? null;
    }
    function useForSound(d) {
        if (!d || !d.connected) { log("connect it first"); return; }
        const n = sinkFor(d);
        if (n) { Audio.use(n); log("sound → " + btName(d), Theme.teal); }
        else log("no sound output for " + btName(d) + " · needs bluetooth audio:  sudo pacman -S --needed pipewire-audio pipewire-pulse wireplumber", Theme.red);
    }
    // connected, then dropped within seconds = almost always missing bluetooth audio support
    property var connectedAt: ({})
    function noteConnected(d) {
        const t = Object.assign({}, connectedAt);
        if (d.connected) t[d.address] = Date.now();
        else if (t[d.address] && Date.now() - t[d.address] < 15000 && isAudioDev(d) && !sinkFor(d))
            log("dropped after " + Math.round((Date.now() - t[d.address]) / 1000) + " s · no audio profile: sudo pacman -S --needed pipewire-audio pipewire-pulse wireplumber", Theme.red);
        connectedAt = t;
    }
    function disconnectCur() {
        const x = cur;
        if (!x || !x.connected) return;
        log("disconnecting " + nameOf(x) + " …");
        x.disconnect();
    }
    function forgetCur() {
        const x = cur;
        if (!x) return;
        if (isWifi && !x.known) { log(x.name + " isn't saved"); return; }
        if (!isWifi && !x.paired) { log(btName(x) + " isn't paired"); return; }
        if (armed !== keyOf(x)) { armed = keyOf(x); armTimer.restart(); return; }
        armed = "";
        log("forgot " + nameOf(x), Theme.yellow);
        x.forget();
    }
    function toggleRadio() {
        if (isWifi) { Networking.wifiEnabled = !Networking.wifiEnabled; log("wifi radio " + (Networking.wifiEnabled ? "on" : "off")); }
        else if (adapter) { adapter.enabled = !adapter.enabled; log("bluetooth " + (adapter.enabled ? "on" : "off")); }
    }
    function rescan() { rescanPause = true; rescanTimer.restart(); log(isWifi ? "rescanning …" : "rediscovering …") }
    property bool rescanPause: false
    Timer { id: rescanTimer; interval: 400; onTriggered: rd.rescanPause = false }
    Timer { id: armTimer; interval: 3000; onTriggered: rd.armed = "" }

    function askPassword(x) {
        promptNet = x;
        prompting = true;
        pskInput.text = "";
        pskInput.forceActiveFocus();
    }
    function cancelPrompt() { prompting = false; promptNet = null; card.forceActiveFocus() }
    function submitPassword() {
        const x = promptNet, psk = pskInput.text;
        if (!x || psk.length < 8) { log("password must be at least 8 characters", Theme.red); return; }
        prompting = false;
        card.forceActiveFocus();
        pendingNet = x;
        log("connecting → " + x.name + " with password …", Theme.sky);
        x.connectWithPsk(psk);
        pskInput.text = "";
    }

    Connections {
        target: rd.pendingNet
        ignoreUnknownSignals: true
        function onConnectionFailed(reason) {
            const x = rd.pendingNet;
            rd.log("failed: " + ConnectionFailReason.toString(reason), Theme.red);
            if (x && reason === ConnectionFailReason.NoSecrets) rd.askPassword(x);
        }
        function onConnectedChanged() {
            if (rd.pendingNet && rd.pendingNet.connected) { rd.log("connected ✓ " + rd.pendingNet.name, Theme.teal); rd.pendingNet = null; }
        }
    }
    Connections {
        target: rd.pendingDev
        ignoreUnknownSignals: true
        function onPairedChanged() {
            const d = rd.pendingDev;
            if (d && d.paired) { rd.log("paired ✓ " + rd.btName(d), Theme.teal); d.trusted = true; d.connect(); }
        }
        function onConnectedChanged() {
            const d = rd.pendingDev;
            if (!d) return;
            rd.log((d.connected ? "connected ✓ " : "disconnected ") + rd.btName(d), d.connected ? Theme.teal : Theme.muted);
            rd.noteConnected(d);
            if (!d.connected) rd.pendingDev = null;     // keep watching a fresh connection for a quick drop
        }
    }

    // scan only while the radar is open
    Binding {
        when: rd.wifiDev !== null
        target: rd.wifiDev
        property: "scannerEnabled"
        value: rd.shown && rd.isWifi && rd.wifiOn && !rd.rescanPause
    }
    Binding {
        when: rd.adapter !== null
        target: rd.adapter
        property: "discovering"
        value: rd.shown && !rd.isWifi && rd.btOn && !rd.rescanPause
    }
    readonly property bool scanning: isWifi ? (wifiDev !== null && wifiDev.scannerEnabled) : (adapter !== null && adapter.discovering)

    // ------------------------------------------------------------ open / close
    function close() { Panels.radarOpen = false }
    Connections {
        target: Panels
        function onRadarOpenChanged() {
            if (Panels.radarOpen) {
                hide.stop();
                rd.shown = true;
                rd.armed = "";
                rd.prompting = false;
                if (!rd.items.length) rd.selKey = "";
                else if (rd.selIndex < 0) rd.selKey = rd.keyOf(rd.items[0]);
                card.forceActiveFocus();
                rd.paintRings();
                appear.restart();
            } else {
                appear.stop();
                hide.restart();
            }
        }
    }
    ParallelAnimation {
        id: appear
        NumberAnimation { target: backdrop; property: "opacity"; to: 0.5; duration: 180; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "scale"; from: 0.97; to: 1; duration: 220; easing.type: Easing.OutQuint }
    }
    ParallelAnimation {
        id: hide
        onFinished: rd.shown = false
        NumberAnimation { target: backdrop; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InQuad }
        NumberAnimation { target: card; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InQuad }
        NumberAnimation { target: card; property: "scale"; to: 0.98; duration: 120; easing.type: Easing.InQuad }
    }

    Rectangle { id: backdrop; anchors.fill: parent; color: "black"; opacity: 0 }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: rd.close() }

    // wave clock: 0 → 2π, loops seamlessly (wave speeds are whole multiples)
    property real waveT: 0
    NumberAnimation on waveT { from: 0; to: 2 * Math.PI; duration: 7000; loops: Animation.Infinite; running: rd.shown }

    // braille spinner for "scanning"
    property int spin: 0
    Timer { interval: 90; repeat: true; running: rd.shown && rd.scanning; onTriggered: rd.spin = (rd.spin + 1) % 10 }
    readonly property string spinner: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏".charAt(spin)

    function paintRings() { sea.requestPaint() }

    // ============================================================ the card
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(1080, rd.width - 80)
        height: Math.min(640, rd.height - 80)
        opacity: 0
        radius: Theme.radius
        color: Theme.bg
        border.width: 1
        border.color: Theme.alpha(Theme.accent, 0.3)
        focus: true

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: if (!rd.prompting) card.forceActiveFocus() }

        Keys.onPressed: e => {
            const k = e.key;
            if (k === Qt.Key_Escape) { if (rd.armed) rd.armed = ""; else rd.close(); }
            else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) Panels.radarMode = rd.isWifi ? "bt" : "wifi";
            else if (k === Qt.Key_W) Panels.radarMode = "wifi";
            else if (k === Qt.Key_B) Panels.radarMode = "bt";
            else if (k === Qt.Key_J || k === Qt.Key_Down) rd.move(1);
            else if (k === Qt.Key_K || k === Qt.Key_Up) rd.move(-1);
            else if (k === Qt.Key_G) rd.move((e.modifiers & Qt.ShiftModifier) ? 999 : -999);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) rd.activate(rd.cur);
            else if (k === Qt.Key_D) rd.disconnectCur();
            else if (k === Qt.Key_O && !rd.isWifi) rd.useForSound(rd.cur);
            else if (k === Qt.Key_F) rd.forgetCur();
            else if (k === Qt.Key_T) rd.toggleRadio();
            else if (k === Qt.Key_R) rd.rescan();
            else return;
            e.accepted = true;
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            // ---------------------------------------------------- tmux-style title bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Math.max(0, card.radius - 1)
                color: Theme.surface
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: parent.radius; color: parent.color }
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 8
                    spacing: 6
                    Text {
                        text: "\u2248 waves"
                        font.family: Theme.mono
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: Theme.accent
                        Layout.rightMargin: 14
                    }
                    Repeater {
                        model: [{ m: "wifi", t: "0:wifi", i: "" }, { m: "bt", t: "1:bluetooth", i: "" }]
                        Rectangle {
                            id: tab
                            required property var modelData
                            readonly property bool on: rd.mode === modelData.m
                            implicitWidth: tabRow.implicitWidth + 22
                            implicitHeight: 26
                            radius: 5
                            color: on ? Theme.alpha(Theme.accent, 0.16) : tabArea.containsMouse ? Theme.hover : "transparent"
                            Row {
                                id: tabRow
                                anchors.centerIn: parent
                                spacing: 7
                                Text { text: tab.modelData.i; font.family: Theme.mono; font.pixelSize: 12; color: tab.on ? Theme.accent : Theme.dim }
                                Text { text: tab.modelData.t + (tab.on ? "*" : "-"); font.family: Theme.mono; font.pixelSize: 12; font.weight: tab.on ? Font.Bold : Font.Normal; color: tab.on ? Theme.text : Theme.muted }
                            }
                            MouseArea { id: tabArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Panels.radarMode = tab.modelData.m }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: rd.isWifi
                            ? (rd.wifiDev ? rd.wifiDev.name + "  " + (rd.wifiDev.address || "").toLowerCase() : "no wifi device")
                            : (rd.adapter ? rd.adapter.name + "  " + rd.adapter.adapterId : "no bluetooth adapter")
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: Theme.dim
                        Layout.rightMargin: 10
                    }
                    Rectangle {
                        implicitWidth: 30; implicitHeight: 26
                        radius: 6
                        color: xArea.containsMouse ? Theme.alpha(Theme.red, 0.2) : "transparent"
                        Text { anchors.centerIn: parent; text: "✕"; font.family: Theme.mono; font.pixelSize: 13; color: xArea.containsMouse ? Theme.red : Theme.muted }
                        MouseArea { id: xArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rd.close() }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // ================================================ the sea
                // every network / device is a wave. close to you (bottom, big, bright) = strong;
                // out by the horizon (top, small, faint) = weak. near waves hide the ones behind.
                Item {
                    id: seaBox
                    clip: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: Math.round(card.width * 0.48)

                    readonly property real horizonY: height * 0.13
                    readonly property real shoreY: height - 44
                    // wave shape, shared by the canvas, the labels and click hit-testing
                    function baseY(d) { return horizonY + (shoreY - horizonY) * (0.06 + 0.86 * d) }
                    function amp(d) { return 3 + 22 * d }
                    function waveY(x, px, t) {
                        const d = rd.depthOf(x), ph = (rd.hash(rd.keyOf(x)) % 628) / 100;
                        const wl = 80 + 200 * d, sp = 1 + Math.round(2 * d);
                        const a = amp(d);
                        return baseY(d)
                            + a * Math.sin(px / wl * 2 * Math.PI + t * sp + ph)
                            + 0.35 * a * Math.sin(px / (wl * 0.43) * 2 * Math.PI - t * sp * 2 + ph * 2);
                    }
                    function labelX(x) { return 56 + ((rd.hash(rd.keyOf(x)) >>> 7) % 1000) / 1000 * Math.max(10, width - 240) }

                    Canvas {
                        id: sea
                        anchors.fill: parent
                        renderStrategy: Canvas.Cooperative
                        onPaint: {
                            const ctx = getContext("2d");
                            const W = width, H = height, t = rd.waveT;
                            ctx.reset();

                            // horizon
                            ctx.strokeStyle = Theme.alpha(Theme.accent, 0.25);
                            ctx.setLineDash([2, 6]);
                            ctx.beginPath(); ctx.moveTo(0, seaBox.horizonY); ctx.lineTo(W, seaBox.horizonY); ctx.stroke();
                            ctx.setLineDash([]);
                            // faint depth guides
                            const guides = rd.isWifi ? [0.25, 0.5, 0.75] : [0.27, 0.6, 0.95];
                            ctx.strokeStyle = Theme.alpha(Theme.text, 0.05);
                            for (let g = 0; g < guides.length; g++) {
                                const y = seaBox.baseY(guides[g]);
                                ctx.beginPath(); ctx.moveTo(44, y); ctx.lineTo(W, y); ctx.stroke();
                            }

                            // far → near so the near waves cover the far ones
                            const list = rd.items.slice().sort((a, b) => rd.depthOf(a) - rd.depthOf(b));
                            for (let i = 0; i < list.length; i++) {
                                const x = list[i], d = rd.depthOf(x), k = rd.keyOf(x);
                                const sel = k === rd.selKey, live = x.connected;
                                const c = rd.colorOf(x), b = seaBox.baseY(d), a = seaBox.amp(d);

                                ctx.beginPath();
                                ctx.moveTo(0, seaBox.waveY(x, 0, t));
                                for (let px = 4; px <= W + 4; px += 4) ctx.lineTo(px, seaBox.waveY(x, px, t));
                                // body: tinted at the crest, fading into the sea colour so it hides what's behind
                                ctx.lineTo(W + 4, H); ctx.lineTo(0, H); ctx.closePath();
                                const grad = ctx.createLinearGradient(0, b - a * 1.4, 0, b + 70 + 60 * d);
                                grad.addColorStop(0, Theme.alpha(c, sel ? 0.30 : live ? 0.22 : 0.10 + 0.08 * d));
                                grad.addColorStop(0.45, Theme.alpha(Theme.bg, 0.88));
                                grad.addColorStop(1, Theme.alpha(Theme.bg, 1));
                                ctx.fillStyle = grad;
                                ctx.fill();

                                // crest line
                                ctx.beginPath();
                                ctx.moveTo(0, seaBox.waveY(x, 0, t));
                                for (let px = 4; px <= W + 4; px += 4) ctx.lineTo(px, seaBox.waveY(x, px, t));
                                ctx.strokeStyle = Theme.alpha(c, sel ? 1 : live ? 0.9 : 0.30 + 0.45 * d);
                                ctx.lineWidth = sel ? 2.4 : live ? 1.8 : 1 + 0.6 * d;
                                ctx.stroke();
                            }
                        }
                    }
                    Connections {
                        target: rd
                        function onWaveTChanged() { if (rd.shown) sea.requestPaint() }
                        function onSelKeyChanged() { sea.requestPaint() }
                        function onItemsChanged() { sea.requestPaint() }
                    }

                    // depth scale on the left
                    Repeater {
                        model: rd.isWifi
                            ? [{ d: 0.25, t: "25%" }, { d: 0.5, t: "50%" }, { d: 0.75, t: "75%" }]
                            : [{ d: 0.27, t: "nearby" }, { d: 0.6, t: "paired" }, { d: 0.95, t: "linked" }]
                        Text {
                            required property var modelData
                            x: 8
                            y: seaBox.baseY(modelData.d) - height / 2
                            text: modelData.t
                            font.family: Theme.mono
                            font.pixelSize: 9
                            color: Theme.alpha(Theme.accent, 0.45)
                        }
                    }
                    Text {
                        x: 8
                        y: seaBox.horizonY - height - 4
                        text: "~ horizon · " + (rd.isWifi ? "weak" : "far")
                        font.family: Theme.mono
                        font.pixelSize: 9
                        color: Theme.dim
                    }

                    // radio off / empty
                    Text {
                        anchors.centerIn: parent
                        visible: (rd.isWifi ? !rd.wifiOn : !rd.btOn) || rd.items.length === 0
                        text: (rd.isWifi ? !rd.wifiOn : !rd.btOn) ? (rd.isWifi ? "wifi" : "bluetooth") + " radio is off · press t"
                            : "calm sea · " + rd.spinner + " listening"
                        font.family: Theme.mono
                        font.pixelSize: 12
                        color: Theme.muted
                    }

                    // a buoy on each wave with its name; it bobs with the water
                    Repeater {
                        model: rd.items
                        Item {
                            id: buoy
                            required property var modelData
                            readonly property string k: rd.keyOf(modelData)
                            readonly property bool selected: rd.selKey === k
                            readonly property bool live: modelData.connected
                            readonly property real d: rd.depthOf(modelData)
                            readonly property real lx: seaBox.labelX(modelData)
                            readonly property color c: rd.colorOf(modelData)
                            x: lx
                            y: seaBox.waveY(modelData, lx, rd.waveT)
                            z: selected ? 100 : Math.round(d * 50)
                            width: 1; height: 1

                            Rectangle {                              // the float
                                anchors.centerIn: parent
                                width: buoy.selected ? 10 : buoy.live ? 9 : 6; height: width; radius: width / 2
                                color: buoy.c
                                border.width: buoy.selected ? 2 : 0
                                border.color: Theme.text
                            }
                            Rectangle {                              // ripple from the connected one
                                visible: buoy.live
                                anchors.centerIn: parent
                                width: 10; height: 4; radius: 2
                                color: "transparent"
                                border.width: 1
                                border.color: buoy.c
                                SequentialAnimation on scale {
                                    running: buoy.live && rd.shown
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1; to: 5; duration: 1800; easing.type: Easing.OutCubic }
                                }
                                SequentialAnimation on opacity {
                                    running: buoy.live && rd.shown
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0.8; to: 0; duration: 1800; easing.type: Easing.OutCubic }
                                }
                            }
                            Rectangle {                              // flag
                                x: 9
                                y: -height - 6
                                width: tag.implicitWidth + 12
                                height: 18
                                radius: 4
                                color: buoy.selected ? Theme.alpha(buoy.c, 0.9) : Theme.alpha(Theme.surface, 0.85)
                                border.width: 1
                                border.color: Theme.alpha(buoy.c, buoy.selected ? 1 : 0.5)
                                opacity: buoy.selected || buoy.live || buoyArea.containsMouse ? 1 : 0.35 + 0.55 * buoy.d
                                Rectangle { x: -6; y: parent.height - 1; width: 1; height: 8; color: Theme.alpha(buoy.c, 0.7); rotation: -35; transformOrigin: Item.Top }
                                Text {
                                    id: tag
                                    anchors.centerIn: parent
                                    text: (rd.isWifi ? "" : rd.btGlyph(buoy.modelData.icon) + " ") + rd.nameOf(buoy.modelData)
                                        + (rd.isWifi ? "  " + Math.round(buoy.modelData.signalStrength * 100) + "%" : "")
                                    font.family: Theme.mono
                                    font.pixelSize: buoy.selected ? 11 : 10
                                    font.weight: buoy.selected ? Font.Bold : Font.Normal
                                    color: buoy.selected ? Theme.onAccent : buoy.c
                                }
                                MouseArea {
                                    id: buoyArea
                                    anchors.fill: parent
                                    anchors.margins: -3
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { rd.selKey = buoy.k; rd.armed = ""; }
                                    onDoubleClicked: rd.activate(buoy.modelData)
                                }
                            }
                        }
                    }

                    // click on the water picks the nearest wave crest under the pointer
                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        cursorShape: Qt.PointingHandCursor
                        function pick(mx, my) {
                            let best = null, bd = 1e9;
                            for (const x of rd.items) {
                                const dy = Math.abs(seaBox.waveY(x, mx, rd.waveT) - my);
                                if (dy < bd) { bd = dy; best = x; }
                            }
                            return bd < 28 ? best : null;
                        }
                        onClicked: m => { const x = pick(m.x, m.y); if (x) { rd.selKey = rd.keyOf(x); rd.armed = ""; } }
                        onDoubleClicked: m => { const x = pick(m.x, m.y); if (x) rd.activate(x); }
                    }

                    // legend
                    Row {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 12
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 14
                        z: 200
                        Repeater {
                            model: rd.isWifi
                                ? [{ c: Theme.accent, t: "connected" }, { c: Theme.sky, t: "saved" }, { c: Theme.violet, t: "locked" }, { c: Theme.yellow, t: "open" }]
                                : [{ c: Theme.accent, t: "connected" }, { c: Theme.sky, t: "paired" }, { c: Theme.violet, t: "new" }]
                            Row {
                                required property var modelData
                                spacing: 5
                                Rectangle { width: 10; height: 2; radius: 1; color: parent.modelData.c; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: parent.modelData.t; font.family: Theme.mono; font.pixelSize: 10; color: Theme.dim }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.border }

                // ================================================ the table
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 16
                    spacing: 8

                    // prompt
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: "$"; font.family: Theme.mono; font.pixelSize: 12; color: Theme.accent }
                        Text {
                            text: rd.isWifi ? "nmcli device wifi list" : "bluetoothctl devices"
                            font.family: Theme.mono
                            font.pixelSize: 12
                            color: Theme.text
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            visible: rd.scanning
                            text: rd.spinner + (rd.isWifi ? " scanning" : " discovering")
                            font.family: Theme.mono
                            font.pixelSize: 11
                            color: Theme.accent
                        }
                        // radio switch
                        Rectangle {
                            implicitWidth: radioRow.implicitWidth + 16
                            implicitHeight: 24
                            radius: 5
                            color: radioArea.containsMouse ? Theme.hover : "transparent"
                            border.width: 1
                            border.color: Theme.cardHi
                            readonly property bool on: rd.isWifi ? rd.wifiOn : rd.btOn
                            Row {
                                id: radioRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text { text: "radio"; font.family: Theme.mono; font.pixelSize: 11; color: Theme.dim }
                                Text { text: parent.parent.on ? "on" : "off"; font.family: Theme.mono; font.pixelSize: 11; font.weight: Font.Bold; color: parent.parent.on ? Theme.teal : Theme.red }
                            }
                            MouseArea { id: radioArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rd.toggleRadio() }
                        }
                    }

                    // column header
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        spacing: 10
                        Text { text: rd.isWifi ? "IN-USE" : "  "; font.family: Theme.mono; font.pixelSize: 10; color: Theme.dim; Layout.preferredWidth: rd.isWifi ? 44 : 18 }
                        Text { text: rd.isWifi ? "SSID" : "NAME"; font.family: Theme.mono; font.pixelSize: 10; color: Theme.dim; Layout.fillWidth: true }
                        Text { text: rd.isWifi ? "SIGNAL" : "STATE"; font.family: Theme.mono; font.pixelSize: 10; color: Theme.dim; Layout.preferredWidth: 92 }
                        Text { text: rd.isWifi ? "SECURITY" : "BATTERY"; font.family: Theme.mono; font.pixelSize: 10; color: Theme.dim; Layout.preferredWidth: 72 }
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }

                    // rows
                    ListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 1
                        model: rd.items
                        currentIndex: rd.selIndex
                        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Rectangle {
                            id: rowItem
                            required property var modelData
                            required property int index
                            readonly property bool on: rd.selKey === rd.keyOf(modelData)
                            readonly property bool armedRow: rd.armed !== "" && rd.armed === rd.keyOf(modelData)
                            width: list.width
                            height: 30
                            radius: 5
                            color: armedRow ? Theme.alpha(Theme.red, 0.18) : on ? Theme.alpha(Theme.accent, 0.12) : rowArea.containsMouse ? Theme.hover : "transparent"
                            Rectangle { visible: rowItem.on; width: 2; height: parent.height - 10; radius: 1; anchors.verticalCenter: parent.verticalCenter; color: rowItem.armedRow ? Theme.red : Theme.accent }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 10
                                Text {
                                    text: rd.isWifi ? (rowItem.modelData.connected ? "  *" : "   ") : rd.btGlyph(rowItem.modelData.icon)
                                    font.family: Theme.mono
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: rd.colorOf(rowItem.modelData)
                                    Layout.preferredWidth: rd.isWifi ? 44 : 18
                                }
                                Text {
                                    text: rd.nameOf(rowItem.modelData)
                                    font.family: Theme.mono
                                    font.pixelSize: 12
                                    font.weight: rowItem.on ? Font.Bold : Font.Normal
                                    color: rowItem.modelData.connected ? Theme.accent : rowItem.on ? Theme.text : Theme.subtext
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                // wifi: ▂▄▆█ 82%   ·   bt: connected / paired / new
                                Row {
                                    Layout.preferredWidth: 92
                                    spacing: 0
                                    visible: rd.isWifi
                                    Text { text: rd.isWifi ? rd.bars(rowItem.modelData.signalStrength)[0] : ""; font.family: Theme.mono; font.pixelSize: 12; color: rd.colorOf(rowItem.modelData) }
                                    Text { text: rd.isWifi ? rd.bars(rowItem.modelData.signalStrength)[1] : ""; font.family: Theme.mono; font.pixelSize: 12; color: Theme.cardHi }
                                    Text { text: rd.isWifi ? "  " + String(Math.round(rowItem.modelData.signalStrength * 100)).padStart(3, " ") + "%" : ""; font.family: Theme.mono; font.pixelSize: 11; color: Theme.muted }
                                }
                                Text {
                                    visible: !rd.isWifi
                                    text: rd.isWifi ? "" : rowItem.modelData.connected ? "connected" : rowItem.modelData.pairing ? "pairing…" : rowItem.modelData.paired ? "paired" : "new"
                                    font.family: Theme.mono
                                    font.pixelSize: 11
                                    color: rd.colorOf(rowItem.modelData)
                                    Layout.preferredWidth: 92
                                }
                                Text {
                                    text: rd.isWifi
                                        ? rd.secName(rowItem.modelData.security) + (rowItem.modelData.known ? " •" : "")
                                        : (rowItem.modelData.batteryAvailable ? Math.round(rowItem.modelData.battery * 100) + "%" : "—")
                                    font.family: Theme.mono
                                    font.pixelSize: 11
                                    color: Theme.muted
                                    Layout.preferredWidth: 72
                                }
                            }
                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { rd.selKey = rd.keyOf(rowItem.modelData); rd.armed = ""; }
                                onDoubleClicked: rd.activate(rowItem.modelData)
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: list.count === 0
                            text: (rd.isWifi ? !rd.wifiOn : !rd.btOn) ? "# radio is off · press t to turn it on"
                                : rd.scanning ? "# " + rd.spinner + " listening…" : "# nothing found · press r to rescan"
                            font.family: Theme.mono
                            font.pixelSize: 12
                            color: Theme.dim
                        }
                    }

                    // password prompt
                    Rectangle {
                        Layout.fillWidth: true
                        visible: rd.prompting
                        implicitHeight: 36
                        radius: 6
                        color: Theme.alpha(Theme.yellow, 0.08)
                        border.width: 1
                        border.color: Theme.alpha(Theme.yellow, 0.6)
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8
                            Text {
                                text: "password for " + (rd.promptNet ? rd.promptNet.name : "") + ":"
                                font.family: Theme.mono
                                font.pixelSize: 12
                                color: Theme.yellow
                            }
                            TextInput {
                                id: pskInput
                                Layout.fillWidth: true
                                echoMode: showPsk.on ? TextInput.Normal : TextInput.Password
                                passwordCharacter: "•"
                                font.family: Theme.mono
                                font.pixelSize: 12
                                color: Theme.text
                                selectionColor: Theme.accent
                                selectedTextColor: Theme.onAccent
                                clip: true
                                onAccepted: rd.submitPassword()
                                Keys.onEscapePressed: rd.cancelPrompt()
                                Keys.onPressed: e => {
                                    if (e.key === Qt.Key_H && (e.modifiers & Qt.ControlModifier)) { showPsk.on = !showPsk.on; e.accepted = true; }
                                }
                                Rectangle {                         // block cursor
                                    visible: pskInput.activeFocus
                                    x: pskInput.cursorRectangle.x
                                    y: pskInput.cursorRectangle.y
                                    width: 7
                                    height: pskInput.cursorRectangle.height
                                    color: Theme.yellow
                                    opacity: blink.on ? 0.9 : 0
                                }
                            }
                            Text {
                                id: showPsk
                                property bool on: false
                                text: (on ? "hide" : "show") + " ^h"
                                font.family: Theme.mono
                                font.pixelSize: 10
                                color: Theme.dim
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: showPsk.on = !showPsk.on }
                            }
                        }
                    }
                    Timer { id: blinkTimer; interval: 530; repeat: true; running: rd.prompting; onTriggered: blink.on = !blink.on }
                    QtObject { id: blink; property bool on: true }

                    // selected item: what you can do
                    Text {
                        Layout.fillWidth: true
                        visible: rd.cur !== null && !rd.prompting
                        text: {
                            const x = rd.cur;
                            if (!x) return "";
                            if (rd.armed) return "press f again to forget " + rd.nameOf(x);
                            const acts = [];
                            acts.push(x.connected ? (rd.isWifi ? "" : "enter disconnect") : (rd.isWifi ? "enter connect" : x.paired ? "enter connect" : "enter pair"));
                            if (x.connected) acts.push("d disconnect");
                            if (!rd.isWifi && x.connected && rd.isAudioDev(x)) acts.push(rd.sinkFor(x) && rd.sinkFor(x) === Audio.sink ? "♪ playing here" : "o use for sound");
                            if (rd.isWifi ? x.known : x.paired) acts.push("f forget");
                            return "# " + rd.nameOf(x) + " → " + acts.filter(a => a).join(" · ");
                        }
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: rd.armed ? Theme.red : Theme.dim
                        elide: Text.ElideRight
                    }

                    // log
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: logCol.implicitHeight + 14
                        radius: 6
                        color: Theme.alpha(Theme.surface, 0.7)
                        border.width: 1
                        border.color: Theme.border
                        Column {
                            id: logCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 7; leftMargin: 10 }
                            spacing: 2
                            Text {
                                visible: rd.logLines.length === 0
                                text: "# log · connections and errors show up here"
                                font.family: Theme.mono
                                font.pixelSize: 10
                                color: Theme.dim
                            }
                            Repeater {
                                model: rd.logLines
                                Row {
                                    required property var modelData
                                    spacing: 8
                                    Text { text: parent.modelData.t; font.family: Theme.mono; font.pixelSize: 10; color: Theme.dim }
                                    Text { text: parent.modelData.s; font.family: Theme.mono; font.pixelSize: 10; color: parent.modelData.c }
                                }
                            }
                        }
                    }
                }
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
                    anchors.rightMargin: 14
                    spacing: 12
                    Rectangle {
                        Layout.fillHeight: true
                        implicitWidth: modeText.implicitWidth + 22
                        radius: Math.max(0, card.radius - 1)
                        color: rd.prompting ? Theme.yellow : rd.armed ? Theme.red : Theme.accent
                        Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: parent.radius; color: parent.color }
                        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: parent.radius; color: parent.color }
                        Text {
                            id: modeText
                            anchors.centerIn: parent
                            text: rd.prompting ? "INSERT" : rd.armed ? "CONFIRM" : "NORMAL"
                            font.family: Theme.mono
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: Theme.onAccent
                        }
                    }
                    Text {
                        text: rd.items.length + (rd.isWifi ? " networks" : " devices") + (rd.isWifi && rd.nets.some(n => n.connected) ? " · on " + rd.nets.find(n => n.connected).name : "")
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: Theme.subtext
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: rd.prompting ? "enter connect · ^h show · esc cancel"
                            : "j/k move · enter connect · d disc · f forget · t radio · r rescan · tab switch · esc"
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: Theme.dim
                    }
                }
            }
        }
    }
}
