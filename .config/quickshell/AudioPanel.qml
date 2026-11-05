// Aurora audio picker: choose where sound goes (speakers, HDMI, Bluetooth, USB…) and which mic is used.
//   open:  click the volume in the bar  ·  › next to the volume slider in the control centre
//          Super+Shift+A  ·  qs ipc call audio toggle
//   keys:  j/k move · Enter use it · -/+ its volume · m mute it · Tab output ↔ input · Esc close
//   HDMI:  plugging in a monitor/TV opens this with the new output selected (Settings → Bar → audio)
//   mouse: click a row to use it · scroll on a row for its volume · move off the panel and it closes

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire

PanelWindow {
    id: ap

    property bool shown: false
    visible: shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "audio"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // keep every device bound while open so volumes are live
    PwObjectTracker { objects: ap.shown ? Audio.allSinks.concat(Audio.allSources) : [] }

    // ------------------------------------------------------------ rows
    // { type: "head" | "node" | "offer", … } in display order
    readonly property var rows: {
        const r = [{ type: "head", text: "output", n: Audio.sinks.length }];
        for (const n of Audio.sinks) r.push({ type: "node", node: n, key: n.name });
        for (const o of Audio.offers) r.push({ type: "offer", offer: o, key: o.key });
        r.push({ type: "head", text: "input", n: Audio.sources.length });
        for (const n of Audio.sources) r.push({ type: "node", node: n, key: n.name });
        return r;
    }
    readonly property var selectable: rows.filter(r => r.type !== "head")
    property string selKey: ""
    readonly property var sel: selectable.find(r => r.key === selKey) ?? null
    property string fresh: ""                       // HDMI output that just appeared (banner)

    function current(r) {
        return r.type === "node" && (r.node === Audio.sink || r.node === Audio.source);
    }
    function move(d) {
        if (!selectable.length) return;
        let i = selectable.findIndex(r => r.key === selKey);
        i = Math.max(0, Math.min(selectable.length - 1, (i < 0 ? 0 : i) + d));
        selKey = selectable[i].key;
    }
    function jumpSection() {
        const outs = selectable.filter(r => r.type === "offer" || r.node.isSink);
        const ins = selectable.filter(r => r.type === "node" && !r.node.isSink);
        const inOut = sel && (sel.type === "offer" || sel.node.isSink);
        const list = inOut ? ins : outs;
        if (list.length) selKey = (list.find(r => current(r)) || list[0]).key;
    }
    function activate(r) {
        if (!r) return;
        if (r.type === "offer") Audio.enable(r.offer);
        else Audio.use(r.node);
        fresh = "";
    }
    function volOf(r) { return r && r.type === "node" && r.node.audio ? r.node.audio.volume : 0 }
    function nudge(r, d) {
        if (!r || r.type !== "node" || !r.node.audio) return;
        r.node.audio.muted = false;
        r.node.audio.volume = Math.max(0, Math.min(1.5, Math.round((r.node.audio.volume + d) * 100) / 100));
    }
    function mute(r) { if (r && r.type === "node" && r.node.audio) r.node.audio.muted = !r.node.audio.muted }

    // ------------------------------------------------------------ HDMI plugged in
    Connections {
        target: Audio
        function onArrived(key) {
            const mode = Settings.o.audioHotplug || "ask";
            if (mode === "off") return;
            const r = ap.rows.find(x => x.key === key);
            if (!r || ap.current(r)) return;           // already in use (e.g. just enabled from here)
            if (mode === "switch") { ap.activate(r); return; }
            if (!Panels.audioOpen) { Panels.closeAll(); Panels.audioOpen = true; }
            ap.fresh = key;
            ap.selKey = key;
        }
    }

    // ------------------------------------------------------------ open / close
    function close() { Panels.audioOpen = false }
    property bool wasInside: false
    Timer { id: leaveTimer; interval: 350; onTriggered: if (!cardHover.hovered) ap.close() }
    Connections {
        target: Panels
        function onAudioOpenChanged() {
            if (Panels.audioOpen) {
                hide.stop();
                ap.shown = true;
                ap.wasInside = false;
                Audio.refresh();
                if (!ap.sel) { const c = ap.selectable.find(r => ap.current(r)); ap.selKey = c ? c.key : ""; }
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
        NumberAnimation { target: slide; property: "y"; from: -12; to: 0; duration: 220; easing.type: Easing.OutQuint }
        NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 140 }
    }
    ParallelAnimation {
        id: hide
        onFinished: { ap.shown = false; ap.fresh = ""; ap.selKey = ""; }
        NumberAnimation { target: slide; property: "y"; to: -8; duration: 120; easing.type: Easing.InCubic }
        NumberAnimation { target: card; property: "opacity"; to: 0; duration: 110 }
    }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: ap.close() }

    component Mono: Text {
        font.family: Theme.mono
        font.pixelSize: 11
        color: Theme.muted
    }

    // ============================================================ the card
    Rectangle {
        id: card
        objectName: "card"
        anchors { top: parent.top; right: parent.right; topMargin: Theme.barHeight + 8; rightMargin: 10 }
        width: 430
        height: col.implicitHeight + 2
        radius: Theme.radius
        color: Theme.bg
        border.width: 1
        border.color: Theme.alpha(Theme.accent, 0.3)
        transform: Translate { id: slide; y: 0 }
        focus: true

        HoverHandler {
            id: cardHover
            onHoveredChanged: {
                if (hovered) { ap.wasInside = true; leaveTimer.stop(); }
                else if (ap.wasInside && Panels.audioOpen) leaveTimer.restart();
            }
        }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: card.forceActiveFocus() }

        Keys.onPressed: e => {
            const k = e.key;
            if (k === Qt.Key_Escape || k === Qt.Key_Q) ap.close();
            else if (k === Qt.Key_J || k === Qt.Key_Down) ap.move(1);
            else if (k === Qt.Key_K || k === Qt.Key_Up) ap.move(-1);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) ap.activate(ap.sel);
            else if (k === Qt.Key_Minus || k === Qt.Key_H || k === Qt.Key_Left) ap.nudge(ap.sel, -0.05);
            else if (k === Qt.Key_Plus || k === Qt.Key_Equal || k === Qt.Key_L || k === Qt.Key_Right) ap.nudge(ap.sel, 0.05);
            else if (k === Qt.Key_M) ap.mute(ap.sel);
            else if (k === Qt.Key_Tab) ap.jumpSection();
            else return;
            e.accepted = true;
        }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
            spacing: 0

            // ---------------------------------------------------- header
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
                    anchors.rightMargin: 14
                    spacing: 8
                    Text { text: "❯"; font.family: Theme.mono; font.pixelSize: 13; color: Theme.accent }
                    Text { text: "audio"; font.family: Theme.mono; font.pixelSize: 13; font.weight: Font.Bold; color: Theme.text }
                    Item { Layout.fillWidth: true }
                    Mono { text: "→ " + Audio.label(Audio.sink); elide: Text.ElideRight; Layout.maximumWidth: 250; color: Theme.dim }
                }
            }

            // ---------------------------------------------------- hdmi banner
            Rectangle {
                objectName: "banner"
                visible: ap.fresh !== ""
                Layout.fillWidth: true
                Layout.margins: 10
                Layout.bottomMargin: 0
                implicitHeight: 34
                radius: 7
                color: Theme.alpha(Theme.violet, 0.14)
                border.width: 1
                border.color: Theme.alpha(Theme.violet, 0.5)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8
                    Text { text: /bluez/.test(ap.fresh) ? "󰂰" : "󰡁"; font.family: Theme.iconFont; font.pixelSize: 15; color: Theme.violet }
                    Mono {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: (/bluez/.test(ap.fresh) ? "bluetooth connected" : "hdmi connected") + (ap.sel && ap.sel.key === ap.fresh ? ": " + (ap.sel.type === "offer" ? ap.sel.offer.label : Audio.label(ap.sel.node)) : "")
                        color: Theme.text
                    }
                    Mono { text: "↵ switch · esc keep"; color: Theme.violet }
                }
            }

            // ---------------------------------------------------- rows
            Column {
                Layout.fillWidth: true
                Layout.topMargin: 6
                Layout.bottomMargin: 8
                Repeater {
                    model: ap.rows
                    Item {
                        id: row
                        required property var modelData
                        readonly property var r: modelData
                        readonly property bool isHead: r.type === "head"
                        readonly property bool isSel: !isHead && ap.selKey === r.key
                        readonly property bool isCur: !isHead && ap.current(r)
                        readonly property bool muted: r.type === "node" && r.node.audio && r.node.audio.muted
                        objectName: isHead ? "head:" + r.text : "row:" + r.key
                        width: col.width
                        height: isHead ? 30 : 44

                        // section header:  # output  2
                        Row {
                            visible: row.isHead
                            anchors { left: parent.left; leftMargin: 16; bottom: parent.bottom; bottomMargin: 4 }
                            spacing: 8
                            Mono { text: "# " + (row.isHead ? row.r.text : ""); color: Theme.dim }
                            Mono { text: row.isHead ? row.r.n : ""; color: Theme.dim; opacity: 0.6 }
                        }

                        Rectangle {
                            visible: !row.isHead
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            radius: 7
                            color: row.isSel ? Theme.alpha(Theme.accent, 0.10) : rowArea.containsMouse ? Theme.hover : "transparent"
                            border.width: row.isSel ? 1 : 0
                            border.color: Theme.alpha(Theme.accent, 0.35)

                            // in-use marker
                            Rectangle {
                                visible: row.isCur
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                width: 3; height: 22; radius: 2
                                color: Theme.accent
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 12
                                spacing: 10
                                Text {
                                    readonly property string k: row.r.type === "offer" ? row.r.offer.kind : row.isHead ? "" : Audio.kind(row.r.node)
                                    text: Audio.icon(k)
                                    font.family: Theme.iconFont
                                    font.pixelSize: 17
                                    color: row.isCur ? Theme.accent : row.r.type === "offer" ? Theme.violet : Theme.subtext
                                    Layout.preferredWidth: 20
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: row.isHead ? "" : row.r.type === "offer" ? row.r.offer.label : Audio.label(row.r.node)
                                        font.family: Theme.font
                                        font.pixelSize: 13
                                        font.weight: row.isCur ? Font.DemiBold : Font.Normal
                                        color: row.isCur ? Theme.text : Theme.subtext
                                    }
                                    Mono {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        font.pixelSize: 10
                                        color: Theme.dim
                                        text: row.isHead ? ""
                                            : row.r.type === "offer" ? row.r.offer.detail + " · switches the card profile"
                                            : (Audio.kind(row.r.node) + (Audio.label(row.r.node) !== row.r.node.description && row.r.node.description ? " · " + row.r.node.description : ""))
                                    }
                                }
                                // volume / tag
                                Mono {
                                    visible: row.r.type === "offer"
                                    text: "enable"
                                    color: Theme.violet
                                }
                                Item {
                                    visible: row.r.type === "node"
                                    implicitWidth: 92
                                    implicitHeight: 16
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 56; height: 4; radius: 2
                                        color: Theme.card
                                        Rectangle {
                                            width: parent.width * Math.min(1, ap.volOf(row.r))
                                            height: parent.height; radius: 2
                                            color: row.muted ? Theme.dim : row.isCur ? Theme.accent : Theme.muted
                                        }
                                    }
                                    Mono {
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        text: row.muted ? "mute" : Math.round(ap.volOf(row.r) * 100) + "%"
                                        font.features: { "tnum": 1 }
                                        color: row.muted ? Theme.red : Theme.dim
                                    }
                                }
                            }
                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onEntered: ap.selKey = row.r.key
                                onClicked: m => { if (m.button === Qt.MiddleButton) ap.mute(row.r); else ap.activate(row.r); }
                                onWheel: w => ap.nudge(row.r, w.angleDelta.y > 0 ? 0.05 : -0.05)
                            }
                        }
                    }
                }
                Mono {
                    visible: !Audio.hasPactl
                    x: 16
                    text: "# install libpulse (pactl) to hide unplugged outputs"
                    color: Theme.dim
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
                    anchors.rightMargin: 12
                    spacing: 10
                    Rectangle {
                        Layout.fillHeight: true
                        implicitWidth: modeText.implicitWidth + 20
                        radius: Math.max(0, card.radius - 1)
                        color: ap.fresh !== "" ? Theme.violet : Theme.accent
                        Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: parent.radius; color: parent.color }
                        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: parent.radius; color: parent.color }
                        Text {
                            id: modeText
                            anchors.centerIn: parent
                            text: ap.fresh === "" ? "AUDIO" : /bluez/.test(ap.fresh) ? "BT" : "HDMI"
                            font.family: Theme.mono; font.pixelSize: 11; font.weight: Font.Bold
                            color: Theme.onAccent
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Mono { text: "j/k · ↵ use · -/+ vol · m mute · tab in/out"; font.pixelSize: 10; color: Theme.dim }
                }
            }
        }
    }
}
