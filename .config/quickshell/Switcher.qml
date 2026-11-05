// Aurora window switcher: Alt+Tab with live previews, most-recently-used order.
//   quick tap Alt+Tab   → straight back to the previous window (no panel flash)
//   hold Alt, tap Tab   → step right · Alt+Shift+Tab steps left · release Alt → switch
//   while open: ←/→ or h/l move · 1-9 pick · Enter switch · Q / Delete close that window
//               Esc cancel · hover + click works too
//   qs ipc call switcher next | prev | commit | cancel

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: sw

    property int showDelay: 140              // ms before the panel appears (a quick tap never shows it)

    property bool active: false              // Alt+Tab in progress
    property bool shown: false
    visible: shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property var wins: []                    // [{ t: toplevel, ipc: client json }] in focus-history order
    property int sel: 0
    property int pendingStep: 0              // steps requested before the window list arrived
    readonly property var cur: wins.length ? wins[Math.max(0, Math.min(sel, wins.length - 1))] : null

    // ------------------------------------------------------------ public
    function step(d) {
        if (!active) {
            active = true;
            sel = 0;
            pendingStep = d;
            wins = [];
            clients.running = false; clients.running = true;
            delay.restart();
            return;
        }
        if (!wins.length) { pendingStep += d; return; }
        sel = (sel + d + wins.length) % wins.length;
    }
    function commit() {
        if (!active) return;
        if (!wins.length) { commitWhenReady = true; return; }
        const w = cur;
        finish();
        if (w) Hyprland.dispatch('hl.dsp.focus({ window = "address:' + w.ipc.address + '" })');
    }
    function cancel() { finish(); }
    function finish() {
        active = false;
        commitWhenReady = false;
        delay.stop();
        if (shown) hide.restart();
    }
    property bool commitWhenReady: false
    function showNow() {
        if (!active || wins.length < 2 || shown) return;
        shown = true;
        hide.stop();
        card.forceActiveFocus();
        appear.restart();
    }

    function closeSelected() {
        const w = cur;
        if (!w) return;
        Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + w.ipc.address + '" })');
        const l = wins.slice();
        l.splice(sel, 1);
        wins = l;
        if (!wins.length) { finish(); return; }
        sel = Math.min(sel, wins.length - 1);
    }

    Timer {
        id: delay
        interval: sw.showDelay
        onTriggered: sw.showNow()
    }

    // focus history straight from Hyprland (focusHistoryID 0 = the focused window)
    Process {
        id: clients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try { list = JSON.parse(text); } catch (e) { list = []; }
                const tops = Hyprland.toplevels.values;
                const out = list
                    .filter(c => c.mapped !== false && c.hidden !== true && c.workspace && c.workspace.id !== -1 && c.focusHistoryID >= 0)
                    .sort((a, b) => a.focusHistoryID - b.focusHistoryID)
                    .map(c => ({ ipc: c, t: tops.find(t => "0x" + t.address === c.address) ?? null }));
                sw.wins = out;
                if (!out.length) { sw.finish(); return; }
                sw.sel = ((sw.pendingStep % out.length) + out.length) % out.length;
                sw.pendingStep = 0;
                if (sw.commitWhenReady) sw.commit();
                else if (!delay.running) sw.showNow();   // list arrived after the delay
            }
        }
    }

    // ------------------------------------------------------------ show / hide
    ParallelAnimation {
        id: appear
        NumberAnimation { target: backdrop; property: "opacity"; to: 0.35; duration: 140; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 140; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "scale"; from: 0.97; to: 1; duration: 180; easing.type: Easing.OutQuint }
    }
    ParallelAnimation {
        id: hide
        onFinished: sw.shown = false
        NumberAnimation { target: backdrop; property: "opacity"; to: 0; duration: 100 }
        NumberAnimation { target: card; property: "opacity"; to: 0; duration: 100 }
    }

    Rectangle { id: backdrop; anchors.fill: parent; color: "black"; opacity: 0 }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: sw.cancel() }

    // ============================================================ the strip
    readonly property int cardW: 300
    readonly property int cardH: 230
    readonly property int perRow: Math.max(1, Math.min(wins.length, Math.floor((width - 120) / (cardW + 14))))

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(sw.width - 80, sw.perRow * (sw.cardW + 14) + 26)
        height: col.implicitHeight + 2
        opacity: 0
        radius: Theme.radius
        color: Theme.bg
        border.width: 1
        border.color: Theme.alpha(Theme.accent, 0.3)
        focus: true
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Keys.onPressed: e => {
            const k = e.key;
            if (k === Qt.Key_Escape) sw.cancel();
            else if (k === Qt.Key_Tab || k === Qt.Key_Right || k === Qt.Key_L) sw.step(1);
            else if (k === Qt.Key_Backtab || k === Qt.Key_Left || k === Qt.Key_H) sw.step(-1);
            else if (k === Qt.Key_Down || k === Qt.Key_J) sw.step(sw.perRow);
            else if (k === Qt.Key_Up || k === Qt.Key_K) sw.step(-sw.perRow);
            else if (k >= Qt.Key_1 && k <= Qt.Key_9) { const i = k - Qt.Key_1; if (i < sw.wins.length) sw.sel = i; }
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) sw.commit();
            else if (k === Qt.Key_Q || k === Qt.Key_Delete) sw.closeSelected();
            else return;
            e.accepted = true;
        }
        Keys.onReleased: e => {
            if (e.key === Qt.Key_Alt) { sw.commit(); e.accepted = true; }   // letting go of Alt switches
        }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
            spacing: 0

            // header
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: Math.max(0, card.radius - 1)
                color: Theme.surface
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: parent.radius; color: parent.color }
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 10
                    Text { text: "❯"; font.family: Theme.mono; font.pixelSize: 13; color: Theme.accent }
                    Text { text: "switch"; font.family: Theme.mono; font.pixelSize: 13; font.weight: Font.Bold; color: Theme.text }
                    Text { text: sw.wins.length + " windows"; font.family: Theme.mono; font.pixelSize: 11; color: Theme.dim }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: sw.cur ? (sw.cur.ipc.class || "") + "  ·  ws " + (sw.cur.ipc.workspace ? sw.cur.ipc.workspace.name : "?") : ""
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: Theme.muted
                    }
                }
            }

            // cards
            Flickable {
                id: grid
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(rows.implicitHeight, (sw.cardH + 14) * 2 + 4) + 28
                contentHeight: rows.implicitHeight + 28
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                Flow {
                    id: rows
                    x: 13; y: 14
                    width: grid.width - 26
                    spacing: 14
                    Repeater {
                        model: sw.wins
                        Rectangle {
                            id: tile
                            required property var modelData
                            required property int index
                            readonly property bool on: sw.sel === index
                            readonly property var ipc: modelData.ipc
                            readonly property string cls: ipc.class || ""
                            width: sw.cardW
                            height: sw.cardH
                            radius: 10
                            color: on ? Theme.alpha(Theme.accent, 0.10) : tileArea.containsMouse ? Theme.hover : Theme.alpha(Theme.surface, 0.6)
                            border.width: on ? 2 : 1
                            border.color: on ? Theme.accent : Theme.border
                            onOnChanged: if (on) {
                                const y = tile.y;
                                if (y < grid.contentY) grid.contentY = y;
                                else if (y + height + 28 > grid.contentY + grid.height) grid.contentY = y + height + 28 - grid.height;
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8
                                // live preview (or the app icon while it loads)
                                ClippingRectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 6
                                    color: Theme.surface
                                    ScreencopyView {
                                        id: shot
                                        anchors.fill: parent
                                        captureSource: sw.shown && tile.modelData.t && tile.modelData.t.wayland ? tile.modelData.t.wayland : null
                                        live: tile.on
                                    }
                                    IconImage {
                                        visible: !shot.hasContent
                                        anchors.centerIn: parent
                                        implicitSize: 48
                                        source: {
                                            const e = DesktopEntries.heuristicLookup(tile.cls);
                                            return Quickshell.iconPath(e ? e.icon : tile.cls.toLowerCase(), "application-x-executable");
                                        }
                                    }
                                    // number badge
                                    Rectangle {
                                        visible: tile.index < 9
                                        anchors { left: parent.left; top: parent.top; margins: 6 }
                                        width: 18; height: 18; radius: 4
                                        color: tile.on ? Theme.accent : Theme.alpha(Theme.bg, 0.8)
                                        Text { anchors.centerIn: parent; text: tile.index + 1; font.family: Theme.mono; font.pixelSize: 10; font.weight: Font.Bold; color: tile.on ? Theme.onAccent : Theme.muted }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    IconImage {
                                        implicitSize: 18
                                        source: {
                                            const e = DesktopEntries.heuristicLookup(tile.cls);
                                            return Quickshell.iconPath(e ? e.icon : tile.cls.toLowerCase(), "application-x-executable");
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text {
                                            Layout.fillWidth: true
                                            text: tile.ipc.title || tile.cls
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: 12
                                            font.weight: tile.on ? Font.DemiBold : Font.Normal
                                            color: tile.on ? Theme.text : Theme.subtext
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: tile.cls.toLowerCase() + (tile.ipc.floating ? " · float" : "") + (tile.ipc.fullscreen ? " · full" : "")
                                            elide: Text.ElideRight
                                            font.family: Theme.mono
                                            font.pixelSize: 10
                                            color: Theme.dim
                                        }
                                    }
                                    Rectangle {
                                        implicitWidth: wsText.implicitWidth + 12; implicitHeight: 18; radius: 4
                                        color: Theme.alpha(Theme.violet, 0.15)
                                        Text { id: wsText; anchors.centerIn: parent; text: tile.ipc.workspace ? tile.ipc.workspace.name : "?"; font.family: Theme.mono; font.pixelSize: 10; color: Theme.violet }
                                    }
                                }
                            }
                            MouseArea {
                                id: tileArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onEntered: sw.sel = tile.index
                                onClicked: m => { sw.sel = tile.index; if (m.button === Qt.MiddleButton) sw.closeSelected(); else sw.commit(); }
                            }
                        }
                    }
                }
            }

            // status line
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
                        color: Theme.accent
                        Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: parent.radius; color: parent.color }
                        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: parent.radius; color: parent.color }
                        Text { id: modeText; anchors.centerIn: parent; text: "ALT"; font.family: Theme.mono; font.pixelSize: 11; font.weight: Font.Bold; color: Theme.onAccent }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: sw.cur ? (sw.cur.ipc.title || "") : ""
                        elide: Text.ElideRight
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: Theme.subtext
                    }
                    Text {
                        text: "tab / shift+tab · release alt to switch · q close window · esc cancel"
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: Theme.dim
                    }
                }
            }
        }
    }
}
