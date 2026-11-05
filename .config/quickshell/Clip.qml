// Aurora clipboard: history with a live preview, pins that never expire, filter tabs.
//   open:  Super+V  ·  qs ipc call clip toggle
//   keys:  type to filter · ↑↓ (or Ctrl+J/K) move · Enter copy · Shift+Enter copy + paste
//          Ctrl+P pin / unpin · Ctrl+D forget · Tab next tab (all · pinned · text · links · images)
//          Ctrl+Shift+Delete wipe history (twice; pins stay) · Esc clear filter, then close
// History comes from cliphist (hyprland.lua starts `wl-paste --watch cliphist store`).
// Pins live in ~/.local/share/aurora/clip-pins.json (+ clip-pins/ for images).

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: cb

    property bool shown: false
    visible: shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "clip"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property string home: Quickshell.env("HOME")
    readonly property string runDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/aurora-clip"
    readonly property string pinDir: home + "/.local/share/aurora/clip-pins"

    // ------------------------------------------------------------ what a clip is
    function kindOf(t, binary) {
        if (binary) return "image";
        const s = t.trim();
        if (/^https?:\/\/\S+$/.test(s)) return "link";
        if (/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(s)) return "color";
        if (/^(~|\/)[^\s]*$/.test(s) && s.length > 1) return "path";
        if (/[{};]\s*$|=>|^\s*(def|func|fn|class|import|const|let|var|if|for|SELECT|#include)\b|\bfunction\b/m.test(t)) return "code";
        return "text";
    }
    function glyph(k) { return ({ image: "󰋩", link: "󰌹", color: "󰏘", path: "󰉋", code: "󰅩", text: "󰦨" })[k] || "󰦨" }

    // ------------------------------------------------------------ history (cliphist)
    property var items: []                  // [{ line, id, prev, kind, pin: false }]
    property bool missing: false
    property bool loaded: false
    Process {
        id: lister
        command: ["sh", "-c", "command -v cliphist >/dev/null || { echo __missing__; exit; }; cliphist list | head -500"]
        stdout: StdioCollector {
            onStreamFinished: {
                cb.missing = text.startsWith("__missing__");
                const out = [];
                if (!cb.missing) for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0) continue;
                    const prev = line.slice(tab + 1);
                    const bin = /^(\[\[ )?binary data/.test(prev);
                    out.push({ line: line, id: line.slice(0, tab), prev: prev, kind: cb.kindOf(prev, bin), pin: false });
                }
                cb.items = out;
                cb.loaded = true;
            }
        }
    }

    // ------------------------------------------------------------ pins
    property var pins: []                   // [{ uid, kind, text } | { uid, kind: "image", file }]
    FileView {
        id: pinFile
        path: cb.home + "/.local/share/aurora/clip-pins.json"
        printErrors: false
        onLoaded: { try { cb.pins = JSON.parse(text() || "[]"); } catch (e) { cb.pins = []; } }
    }
    function savePins(p) {
        pins = p;
        pinFile.setText(JSON.stringify(p, null, 1));
    }
    function pinRows() {
        return pins.map(p => ({ pin: true, uid: p.uid, kind: p.kind, file: p.file || "", full: p.text || "",
                                prev: p.kind === "image" ? "pinned image" : (p.text || "").replace(/\s+/g, " ").slice(0, 200) }));
    }
    function isPinnedText(t) { return pins.some(p => p.text !== undefined && p.text === t) }

    // ------------------------------------------------------------ view
    readonly property var tabs: ["all", "pinned", "text", "links", "images"]
    property int tab: 0
    property string filter: ""
    readonly property var rows: {
        const t = tabs[tab], q = filter.toLowerCase();
        let r = (t === "all" || t === "pinned") ? pinRows() : [];
        if (t !== "pinned") r = r.concat(items);
        return r.filter(x => {
            if (t === "text" && (x.kind === "image" || x.kind === "link")) return false;
            if (t === "links" && x.kind !== "link") return false;
            if (t === "images" && x.kind !== "image") return false;
            return !q || x.prev.toLowerCase().indexOf(q) >= 0 || (x.full || "").toLowerCase().indexOf(q) >= 0;
        });
    }
    property int sel: 0
    readonly property var cur: rows[Math.min(sel, rows.length - 1)] ?? null
    onRowsChanged: if (sel >= rows.length) sel = Math.max(0, rows.length - 1)
    function move(d) { sel = Math.max(0, Math.min(rows.length - 1, sel + d)); list.positionViewAtIndex(sel, ListView.Contain) }

    // ------------------------------------------------------------ preview of the selected clip
    property string full: ""                // decoded text
    property string img: ""                 // decoded image file
    property string shownKey: ""
    function keyOf(r) { return r ? (r.pin ? "pin:" + r.uid : "h:" + r.id) : "" }
    onCurChanged: previewTimer.restart()
    Timer {
        id: previewTimer
        interval: 60
        onTriggered: {
            const r = cb.cur, k = cb.keyOf(r);
            if (k === cb.shownKey) return;
            cb.shownKey = k; cb.full = ""; cb.img = "";
            if (!r) return;
            if (r.pin) { if (r.kind === "image") cb.img = "file://" + r.file; else cb.full = r.full; return; }
            if (r.kind === "image") {
                const f = cb.runDir + "/" + r.id + ".img";
                decoder.target = "img";
                decoder.command = ["sh", "-c", 'mkdir -p "$2"; [ -s "$3" ] || printf "%s" "$1" | cliphist decode > "$3"; echo "$3"', "_", r.line, cb.runDir, f];
            } else {
                decoder.target = "text";
                decoder.command = ["sh", "-c", 'printf "%s" "$1" | cliphist decode | head -c 200000', "_", r.line];
            }
            decoder.forKey = k;
            decoder.running = false;
            decoder.running = true;
        }
    }
    Process {
        id: decoder
        property string target: "text"
        property string forKey: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (decoder.forKey !== cb.shownKey) return;           // selection moved on
                if (decoder.target === "img") cb.img = "file://" + text.trim();
                else cb.full = text;
            }
        }
    }
    readonly property var stats: {
        const t = full;
        if (!t) return "";
        const lines = t.split("\n").length - (t.endsWith("\n") ? 1 : 0);
        const words = (t.match(/\S+/g) || []).length;
        return t.length + " chars · " + lines + (lines === 1 ? " line" : " lines") + " · " + words + " words";
    }

    // ------------------------------------------------------------ actions
    function run(cmd) { worker.command = cmd; worker.running = false; worker.running = true; }
    Process { id: worker; onExited: if (cb.reloadAfter) { cb.reloadAfter = false; lister.running = true; } }
    property bool reloadAfter: false

    function copy(r, paste) {
        if (!r) return;
        let cmd;
        if (r.pin && r.kind === "image") cmd = 'wl-copy < "$1"';
        else if (r.pin) cmd = 'printf "%s" "$1" | wl-copy';
        else cmd = 'printf "%s" "$1" | cliphist decode | wl-copy';
        if (paste) cmd += '; sleep 0.3; command -v wtype >/dev/null && wtype -M ctrl v -m ctrl';
        copier.command = ["sh", "-c", cmd, "_", r.pin ? (r.kind === "image" ? r.file : r.full) : r.line];
        copier.running = false;
        copier.running = true;
        flashed = keyOf(r);
        closeSoon.restart();
    }
    Process { id: copier }
    property string flashed: ""
    Timer { id: closeSoon; interval: 160; onTriggered: cb.close() }

    function forget(r) {
        if (!r) return;
        if (r.pin) { togglePin(r); return; }
        items = items.filter(x => x.id !== r.id);
        run(["sh", "-c", 'printf "%s" "$1" | cliphist delete', "_", r.line]);
    }
    function togglePin(r) {
        if (!r) return;
        if (r.pin) {
            savePins(pins.filter(p => p.uid !== r.uid));
            if (r.file) run(["rm", "-f", r.file]);
            return;
        }
        const uid = String(Date.now());
        if (r.kind === "image") {
            const f = pinDir + "/" + uid + ".img";
            savePins([{ uid: uid, kind: "image", file: f }].concat(pins));
            run(["sh", "-c", 'mkdir -p "$2"; printf "%s" "$1" | cliphist decode > "$3"', "_", r.line, pinDir, f]);
        } else {
            // the preview already holds the full text when it's the selected clip; otherwise decode it first
            if (keyOf(r) === shownKey && full) addTextPin(r.kind, full);
            else { pinner.kind = r.kind; pinner.command = ["sh", "-c", 'printf "%s" "$1" | cliphist decode', "_", r.line]; pinner.running = true; }
        }
    }
    function addTextPin(kind, t) {
        if (!t || isPinnedText(t)) return;
        savePins([{ uid: String(Date.now()), kind: kind, text: t }].concat(pins));
    }
    Process {
        id: pinner
        property string kind: "text"
        stdout: StdioCollector { onStreamFinished: cb.addTextPin(pinner.kind, text) }
    }
    property bool armed: false
    Timer { id: armTimer; interval: 3000; onTriggered: cb.armed = false }
    function wipe() {
        if (!armed) { armed = true; armTimer.restart(); return; }
        armed = false;
        items = [];
        reloadAfter = true;
        run(["sh", "-c", 'cliphist wipe; rm -rf "$1"', "_", runDir]);
    }

    // ------------------------------------------------------------ open / close
    function close() { Panels.clipOpen = false }
    Connections {
        target: Panels
        function onClipOpenChanged() {
            if (Panels.clipOpen) {
                hide.stop();
                cb.shown = true;
                cb.loaded = false;
                cb.sel = 0; cb.tab = 0; cb.filter = ""; search.text = "";
                cb.shownKey = ""; cb.flashed = ""; cb.armed = false;
                lister.running = true;
                pinFile.reload();
                search.forceActiveFocus();
                appear.restart();
            } else {
                appear.stop();
                hide.restart();
            }
        }
    }
    ParallelAnimation {
        id: appear
        NumberAnimation { target: backdrop; property: "opacity"; to: 0.3; duration: 150 }
        NumberAnimation { target: card; property: "scale"; from: 0.97; to: 1; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 150 }
    }
    ParallelAnimation {
        id: hide
        onFinished: cb.shown = false
        NumberAnimation { target: backdrop; property: "opacity"; to: 0; duration: 110 }
        NumberAnimation { target: card; property: "opacity"; to: 0; duration: 110 }
    }

    Rectangle { id: backdrop; anchors.fill: parent; color: "black"; opacity: 0 }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: cb.close() }

    component Mono: Text {
        font.family: Theme.mono
        font.pixelSize: 11
        color: Theme.muted
    }

    // ============================================================ the card
    Rectangle {
        id: card
        objectName: "card"
        anchors.centerIn: parent
        width: 940
        height: 580
        radius: Theme.radius
        color: Theme.bg
        border.width: 1
        border.color: Theme.alpha(cb.armed ? Theme.red : Theme.accent, 0.3)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: search.forceActiveFocus() }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            // ---------------------------------------------------- header: filter + tabs
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                radius: Math.max(0, card.radius - 1)
                color: Theme.surface
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: parent.radius; color: parent.color }
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    spacing: 10
                    Text { text: "❯"; font.family: Theme.mono; font.pixelSize: 14; color: Theme.accent }
                    Text { text: "clip"; font.family: Theme.mono; font.pixelSize: 13; font.weight: Font.Bold; color: Theme.text }
                    TextInput {
                        id: search
                        objectName: "search"
                        Layout.fillWidth: true
                        font.family: Theme.mono
                        font.pixelSize: 13
                        color: Theme.text
                        selectionColor: Theme.alpha(Theme.accent, 0.4)
                        clip: true
                        onTextChanged: { cb.filter = text; cb.sel = 0; }
                        Text {
                            visible: !search.text
                            text: "type to filter…"
                            font: search.font
                            color: Theme.dim
                        }
                        Keys.onPressed: e => {
                            const k = e.key, ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
                            if (k === Qt.Key_Escape) { if (search.text) search.text = ""; else if (cb.armed) cb.armed = false; else cb.close(); }
                            else if (k === Qt.Key_Down || (ctrl && k === Qt.Key_J)) cb.move(1);
                            else if (k === Qt.Key_Up || (ctrl && k === Qt.Key_K)) cb.move(-1);
                            else if (k === Qt.Key_PageDown) cb.move(8);
                            else if (k === Qt.Key_PageUp) cb.move(-8);
                            else if (k === Qt.Key_Return || k === Qt.Key_Enter) cb.copy(cb.cur, shift);
                            else if (ctrl && k === Qt.Key_P) cb.togglePin(cb.cur);
                            else if (ctrl && shift && (k === Qt.Key_Delete || k === Qt.Key_Backspace)) cb.wipe();
                            else if ((ctrl && k === Qt.Key_D) || (shift && k === Qt.Key_Delete)) cb.forget(cb.cur);
                            else if (k === Qt.Key_Tab) { cb.tab = (cb.tab + 1) % cb.tabs.length; cb.sel = 0; }
                            else if (k === Qt.Key_Backtab) { cb.tab = (cb.tab + cb.tabs.length - 1) % cb.tabs.length; cb.sel = 0; }
                            else return;
                            e.accepted = true;
                        }
                    }
                    Repeater {
                        model: cb.tabs
                        Rectangle {
                            required property string modelData
                            required property int index
                            objectName: "tab:" + modelData
                            implicitWidth: tabText.implicitWidth + 16
                            implicitHeight: 24
                            radius: 5
                            color: cb.tab === index ? Theme.accentSoft : tabArea.containsMouse ? Theme.hover : "transparent"
                            border.width: 1
                            border.color: cb.tab === index ? Theme.alpha(Theme.accent, 0.6) : Theme.cardHi
                            Mono { id: tabText; anchors.centerIn: parent; text: modelData + (modelData === "pinned" && cb.pins.length ? " " + cb.pins.length : ""); color: cb.tab === index ? Theme.accent : Theme.muted }
                            MouseArea { id: tabArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { cb.tab = index; cb.sel = 0; search.forceActiveFocus(); } }
                        }
                    }
                }
            }

            // ---------------------------------------------------- list | preview
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                ListView {
                    id: list
                    objectName: "list"
                    Layout.preferredWidth: 400
                    Layout.fillHeight: true
                    Layout.topMargin: 6
                    Layout.bottomMargin: 6
                    clip: true
                    model: cb.rows
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool isSel: index === cb.sel
                        width: list.width
                        height: 34
                        color: cb.flashed !== "" && cb.flashed === cb.keyOf(modelData) ? Theme.alpha(Theme.accent, 0.3)
                             : isSel ? Theme.alpha(Theme.accent, 0.10) : rowArea.containsMouse ? Theme.hover : "transparent"
                        Rectangle { visible: row.isSel; width: 3; height: 20; radius: 2; anchors.verticalCenter: parent.verticalCenter; x: 4; color: Theme.accent }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 12
                            spacing: 10
                            // colour clips show the colour itself
                            Rectangle {
                                visible: row.modelData.kind === "color"
                                implicitWidth: 14; implicitHeight: 14; radius: 4
                                color: row.modelData.kind === "color" ? row.modelData.prev.trim() : "transparent"
                                border.width: 1; border.color: Theme.cardHi
                            }
                            Text {
                                visible: row.modelData.kind !== "color"
                                text: cb.glyph(row.modelData.kind)
                                font.family: Theme.iconFont; font.pixelSize: 14
                                color: row.isSel ? Theme.accent : Theme.dim
                                Layout.preferredWidth: 14
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: row.modelData.kind === "image" && !row.modelData.pin ? row.modelData.prev.replace(/^\[\[ |\]\]$/g, "") : row.modelData.prev
                                textFormat: Text.PlainText
                                font.family: row.modelData.kind === "code" || row.modelData.kind === "path" ? Theme.mono : Theme.font
                                font.pixelSize: 12
                                color: row.isSel ? Theme.text : Theme.subtext
                            }
                            Text { visible: row.modelData.pin; text: "󰐃"; font.family: Theme.iconFont; font.pixelSize: 12; color: Theme.yellow }
                        }
                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: m => { cb.sel = row.index; if (m.button === Qt.MiddleButton) cb.togglePin(row.modelData); else cb.copy(row.modelData, false); }
                        }
                    }
                }
                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.border }

                // preview
                Item {
                    id: pane
                    objectName: "preview"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    readonly property string kind: cb.cur ? cb.cur.kind : ""

                    // empty / missing
                    Column {
                        anchors.centerIn: parent
                        visible: !cb.cur
                        spacing: 8
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰅌"; font.family: Theme.iconFont; font.pixelSize: 40; color: Theme.dim }
                        Mono {
                            anchors.horizontalCenter: parent.horizontalCenter
                            font.pixelSize: 13
                            text: cb.missing ? "# needs cliphist:  sudo pacman -S cliphist" : !cb.loaded ? "# loading…"
                                : cb.filter ? "# nothing matches “" + cb.filter + "”" : cb.tab === 1 ? "# no pins yet · Ctrl+P pins a clip" : "# nothing copied yet"
                        }
                    }

                    // image
                    Image {
                        visible: pane.kind === "image"
                        anchors.fill: parent
                        anchors.margins: 18
                        anchors.bottomMargin: 40
                        source: cb.img
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                    }

                    // colour
                    Column {
                        visible: pane.kind === "color"
                        anchors.centerIn: parent
                        spacing: 12
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 180; height: 120; radius: 14
                            color: pane.kind === "color" ? cb.cur.prev.trim() : "transparent"
                            border.width: 1; border.color: Theme.cardHi
                        }
                        Mono {
                            anchors.horizontalCenter: parent.horizontalCenter
                            font.pixelSize: 14
                            color: Theme.text
                            text: {
                                if (pane.kind !== "color") return "";
                                let h = cb.cur.prev.trim().slice(1);
                                if (h.length === 3) h = h.split("").map(x => x + x).join("");
                                const n = i => parseInt(h.substr(h.length === 8 ? i + 2 : i, 2), 16);   // #aarrggbb → skip alpha
                                return "#" + h + "   rgb(" + n(0) + ", " + n(2) + ", " + n(4) + ")";
                            }
                        }
                    }

                    // link
                    Column {
                        visible: pane.kind === "link"
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
                        spacing: 8
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: pane.kind === "link" ? (cb.cur.prev.match(/^https?:\/\/([^\/?#]+)/) || ["", ""])[1] : ""
                            font.family: Theme.font; font.pixelSize: 22; font.weight: Font.DemiBold
                            color: Theme.text
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WrapAnywhere
                            text: pane.kind === "link" ? (cb.full || cb.cur.prev) : ""
                            textFormat: Text.PlainText
                            font.family: Theme.mono; font.pixelSize: 12
                            color: Theme.sky
                        }
                    }

                    // text / code / path: with line numbers
                    Flickable {
                        id: textView
                        visible: cb.cur !== null && ["text", "code", "path"].indexOf(pane.kind) >= 0
                        anchors.fill: parent
                        anchors.margins: 14
                        anchors.bottomMargin: 34
                        clip: true
                        contentWidth: textRow.implicitWidth
                        contentHeight: textRow.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        readonly property var lines: (cb.full || (cb.cur ? cb.cur.prev : "")).replace(/\n$/, "").split("\n").slice(0, 400)
                        Row {
                            id: textRow
                            spacing: 12
                            Text {
                                text: textView.lines.map((_, i) => i + 1).join("\n")
                                font.family: Theme.mono; font.pixelSize: 12
                                color: Theme.dim
                                horizontalAlignment: Text.AlignRight
                                width: Math.max(18, String(textView.lines.length).length * 8)
                            }
                            Text {
                                objectName: "previewText"
                                text: textView.lines.join("\n").replace(/\t/g, "    ")
                                textFormat: Text.PlainText
                                font.family: Theme.mono; font.pixelSize: 12
                                color: pane.kind === "path" ? Theme.sky : Theme.text
                            }
                        }
                    }

                    // footer
                    Mono {
                        visible: cb.cur !== null
                        anchors { left: parent.left; bottom: parent.bottom; margins: 14 }
                        text: !cb.cur ? "" : (cb.cur.pin ? "pinned · " : "#" + cb.cur.id + " · ") + cb.cur.kind + (cb.stats ? " · " + cb.stats : "")
                        color: Theme.dim
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
                    anchors.rightMargin: 12
                    spacing: 10
                    Rectangle {
                        Layout.fillHeight: true
                        implicitWidth: modeText.implicitWidth + 20
                        radius: Math.max(0, card.radius - 1)
                        color: cb.armed ? Theme.red : cb.filter ? Theme.yellow : Theme.accent
                        Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: parent.radius; color: parent.color }
                        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: parent.radius; color: parent.color }
                        Text {
                            id: modeText
                            anchors.centerIn: parent
                            text: cb.armed ? "WIPE?" : cb.filter ? "FILTER" : "CLIP"
                            font.family: Theme.mono; font.pixelSize: 11; font.weight: Font.Bold
                            color: Theme.onAccent
                        }
                    }
                    Mono { text: cb.rows.length + "/" + (cb.items.length + cb.pins.length); color: Theme.dim }
                    Item { Layout.fillWidth: true }
                    Mono {
                        text: cb.armed ? "Ctrl+Shift+Del again wipes the history · pins stay"
                            : "↵ copy · ⇧↵ paste · ^P pin · ^D forget · tab filter · ^⇧Del wipe"
                        font.pixelSize: 10
                        color: cb.armed ? Theme.red : Theme.dim
                    }
                }
            }
        }
    }
}
