// Aurora notification centre: a drawer on the right, grouped by app, like `journalctl -f` for your desktop.
//   open:  Super+`  ·  click the bell in the bar  ·  qs ipc call notifs toggle
//   keys:  j/k move · Enter open (default action) · d / Delete dismiss · c fold the app group
//          x dismiss the whole app · / filter · n do-not-disturb · C clear all (twice) · Esc close
//   mouse: click a card to open it · × to dismiss · click a group header to fold it

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications

PanelWindow {
    id: nc

    property bool shown: false
    visible: shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "notifcenter"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ------------------------------------------------------------ data
    property string filter: ""
    property var collapsed: ({})                 // app → true
    property int tick: 0                         // bumps every 30 s so "5m ago" stays fresh
    Timer { interval: 30000; repeat: true; running: nc.shown; onTriggered: nc.tick++ }

    function matches(n) {
        if (!filter) return true;
        const q = filter.toLowerCase();
        return (n.summary || "").toLowerCase().indexOf(q) >= 0
            || (n.body || "").toLowerCase().indexOf(q) >= 0
            || Notifs.appOf(n).toLowerCase().indexOf(q) >= 0;
    }
    // [{ app, items: [n…], newest }] newest group first
    readonly property var groups: {
        const by = {};
        for (const n of Notifs.history) {
            if (!matches(n)) continue;
            const a = Notifs.appOf(n);
            (by[a] = by[a] || []).push(n);
        }
        return Object.keys(by)
            .map(a => ({ app: a, items: by[a], newest: Math.max.apply(null, by[a].map(n => Notifs.timeOf(n))) }))
            .sort((x, y) => y.newest - x.newest);
    }
    // what j/k walks through: visible cards in display order
    readonly property var flat: {
        const out = [];
        for (const g of groups) if (!collapsed[g.app]) for (const n of g.items) out.push(n);
        return out;
    }
    property int selId: -1
    readonly property var sel: flat.find(n => n.id === selId) ?? null
    onFlatChanged: if (!sel && flat.length) selId = flat[0].id

    function move(d) {
        if (!flat.length) return;
        let i = flat.findIndex(n => n.id === selId);
        i = Math.max(0, Math.min(flat.length - 1, (i < 0 ? 0 : i) + d));
        selId = flat[i].id;
        armed = false;
    }
    function toggleGroup(app) {
        const c = Object.assign({}, collapsed);
        c[app] = !c[app];
        collapsed = c;
    }
    function defaultAction(n) { return n ? (n.actions.find(a => a.identifier === "default") ?? null) : null }
    function activate(n) {
        if (!n) return;
        const a = defaultAction(n);
        if (a) { a.invoke(); if (!n.resident) n.dismiss(); close(); }
    }
    function dismiss(n) {
        if (!n) return;
        const i = flat.indexOf(n);
        const next = flat[i + 1] || flat[i - 1] || null;
        n.dismiss();
        selId = next ? next.id : -1;
    }
    property bool armed: false
    function clearAll() {
        if (!armed) { armed = true; armTimer.restart(); return; }
        armed = false;
        Notifs.clearAll();
    }
    Timer { id: armTimer; interval: 3000; onTriggered: nc.armed = false }

    function icon(n) {
        const e = DesktopEntries.heuristicLookup(n.desktopEntry || n.appName || "");
        const name = n.appIcon || (e ? e.icon : (n.appName || "").toLowerCase());
        return name.startsWith("/") || name.startsWith("file:") || name.startsWith("image:") ? name
             : Quickshell.iconPath(name, "dialog-information");
    }

    // ------------------------------------------------------------ open / close
    function close() { Panels.notifOpen = false }
    Connections {
        target: Panels
        function onNotifOpenChanged() {
            if (Panels.notifOpen) {
                hide.stop();
                nc.shown = true;
                nc.armed = false;
                nc.tick++;
                if (nc.flat.length) nc.selId = nc.flat[0].id;
                Notifs.popups = [];                      // the toasts are in here now
                drawer.forceActiveFocus();
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
        NumberAnimation { target: slide; property: "x"; from: 40; to: 0; duration: 240; easing.type: Easing.OutQuint }
        NumberAnimation { target: drawer; property: "opacity"; from: 0; to: 1; duration: 160 }
    }
    ParallelAnimation {
        id: hide
        onFinished: { nc.shown = false; nc.filter = ""; search.text = ""; }
        NumberAnimation { target: backdrop; property: "opacity"; to: 0; duration: 120 }
        NumberAnimation { target: slide; property: "x"; to: 30; duration: 140; easing.type: Easing.InCubic }
        NumberAnimation { target: drawer; property: "opacity"; to: 0; duration: 120 }
    }

    Rectangle { id: backdrop; anchors.fill: parent; color: "black"; opacity: 0 }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: nc.close() }

    // ============================================================ the drawer
    Rectangle {
        id: drawer
        objectName: "drawer"
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right; topMargin: Theme.barHeight + 8; bottomMargin: 10; rightMargin: 10 }
        width: 460
        radius: Theme.radius
        color: Theme.bg
        border.width: 1
        border.color: Theme.alpha(nc.armed ? Theme.red : Theme.accent, 0.3)
        transform: Translate { id: slide; x: 0 }
        focus: true
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: drawer.forceActiveFocus() }

        Keys.onPressed: e => {
            const k = e.key, shift = e.modifiers & Qt.ShiftModifier;
            if (k === Qt.Key_Escape) { if (nc.armed) nc.armed = false; else if (nc.filter) { nc.filter = ""; search.text = ""; } else nc.close(); }
            else if (k === Qt.Key_J || k === Qt.Key_Down) nc.move(1);
            else if (k === Qt.Key_K || k === Qt.Key_Up) nc.move(-1);
            else if (k === Qt.Key_G) nc.move(shift ? 9999 : -9999);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) nc.activate(nc.sel);
            else if (k === Qt.Key_D && !shift || k === Qt.Key_Delete) nc.dismiss(nc.sel);
            else if (k === Qt.Key_C && shift) nc.clearAll();
            else if (k === Qt.Key_C) { if (nc.sel) nc.toggleGroup(Notifs.appOf(nc.sel)); }
            else if (k === Qt.Key_X) { if (nc.sel) Notifs.dismissApp(Notifs.appOf(nc.sel)); }
            else if (k === Qt.Key_N) Notifs.dnd = !Notifs.dnd;
            else if (k === Qt.Key_Slash) { search.forceActiveFocus(); }
            else return;
            e.accepted = true;
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            // ---------------------------------------------------- header
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Math.max(0, drawer.radius - 1)
                color: Theme.surface
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: parent.radius; color: parent.color }
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 10
                    spacing: 8
                    Text { text: "❯"; font.family: Theme.mono; font.pixelSize: 13; color: Theme.accent }
                    Text { text: "notifications"; font.family: Theme.mono; font.pixelSize: 13; font.weight: Font.Bold; color: Theme.text }
                    Text { text: Notifs.history.length; font.family: Theme.mono; font.pixelSize: 11; color: Theme.dim }
                    Item { Layout.fillWidth: true }
                    // do not disturb
                    Rectangle {
                        objectName: "dndPill"
                        implicitWidth: dndRow.implicitWidth + 16; implicitHeight: 24; radius: 5
                        color: Notifs.quiet ? Theme.alpha(Theme.violet, 0.18) : dndArea.containsMouse ? Theme.hover : "transparent"
                        border.width: 1
                        border.color: Notifs.quiet ? Theme.alpha(Theme.violet, 0.6) : Theme.cardHi
                        Row {
                            id: dndRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: Notifs.quiet ? "" : ""; font.family: Theme.mono; font.pixelSize: 11; color: Notifs.quiet ? Theme.violet : Theme.muted }
                            Text {
                                text: Notifs.dnd ? "dnd" : Notifs.quiet ? "quiet → " + Settings.o.dndTo : Notifs.scheduled ? "dnd " + Settings.o.dndFrom : "dnd off"
                                font.family: Theme.mono; font.pixelSize: 11
                                color: Notifs.quiet ? Theme.violet : Theme.muted
                            }
                        }
                        MouseArea { id: dndArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.dnd = !Notifs.dnd }
                    }
                    // clear all
                    Rectangle {
                        objectName: "clearBtn"
                        visible: Notifs.history.length > 0
                        implicitWidth: clrText.implicitWidth + 16; implicitHeight: 24; radius: 5
                        color: nc.armed ? Theme.alpha(Theme.red, 0.2) : clrArea.containsMouse ? Theme.hover : "transparent"
                        border.width: 1
                        border.color: nc.armed ? Theme.red : Theme.cardHi
                        Text { id: clrText; anchors.centerIn: parent; text: nc.armed ? "again to clear" : "clear"; font.family: Theme.mono; font.pixelSize: 11; color: nc.armed ? Theme.red : Theme.muted }
                        MouseArea { id: clrArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: nc.clearAll() }
                    }
                }
            }

            // ---------------------------------------------------- filter
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 10
                Layout.bottomMargin: 4
                implicitHeight: 30
                radius: 6
                color: Theme.alpha(Theme.surface, 0.6)
                border.width: 1
                border.color: search.activeFocus ? Theme.accent : Theme.cardHi
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8
                    Text { text: "/"; font.family: Theme.mono; font.pixelSize: 13; color: search.activeFocus ? Theme.accent : Theme.dim }
                    TextInput {
                        id: search
                        objectName: "search"
                        Layout.fillWidth: true
                        font.family: Theme.mono
                        font.pixelSize: 12
                        color: Theme.text
                        clip: true
                        onTextChanged: nc.filter = text.trim()
                        Keys.onPressed: e => {
                            if (e.key === Qt.Key_Escape) { text = ""; drawer.forceActiveFocus(); }
                            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Down) drawer.forceActiveFocus();
                            else return;
                            e.accepted = true;
                        }
                        Text { visible: !search.text; text: "filter by app, title or text"; font: search.font; color: Theme.dim }
                    }
                    Text { visible: nc.filter !== ""; text: nc.flat.length + " match" + (nc.flat.length === 1 ? "" : "es"); font.family: Theme.mono; font.pixelSize: 10; color: Theme.muted }
                }
            }

            // ---------------------------------------------------- list
            Flickable {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: col.implicitHeight + 16
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                function reveal(item) {
                    const p = item.mapToItem(col, 0, 0);
                    if (p.y < contentY) contentY = Math.max(0, p.y - 8);
                    else if (p.y + item.height > contentY + height) contentY = p.y + item.height - height + 8;
                }

                Column {
                    id: col
                    x: 10
                    width: list.width - 20
                    spacing: 10

                    Repeater {
                        model: nc.groups
                        Column {
                            id: grp
                            required property var modelData
                            readonly property bool folded: nc.collapsed[modelData.app] === true
                            width: col.width
                            spacing: 4

                            // group header
                            Rectangle {
                                objectName: "group:" + grp.modelData.app
                                width: parent.width
                                height: 26
                                radius: 5
                                color: ghArea.containsMouse ? Theme.hover : "transparent"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 4
                                    spacing: 8
                                    Text { text: grp.folded ? "▸" : "▾"; font.family: Theme.mono; font.pixelSize: 11; color: Theme.dim }
                                    IconImage { implicitSize: 14; source: nc.icon(grp.modelData.items[0]) }
                                    Text { text: "[" + grp.modelData.app.toLowerCase() + "]"; font.family: Theme.mono; font.pixelSize: 12; font.weight: Font.Bold; color: Theme.violet }
                                    Text { text: grp.modelData.items.length; font.family: Theme.mono; font.pixelSize: 10; color: Theme.dim }
                                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
                                    Text {
                                        text: "✕"
                                        font.family: Theme.mono; font.pixelSize: 11
                                        color: gxArea.containsMouse ? Theme.red : Theme.dim
                                        MouseArea { id: gxArea; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.dismissApp(grp.modelData.app) }
                                    }
                                }
                                MouseArea { id: ghArea; anchors.fill: parent; anchors.rightMargin: 24; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: nc.toggleGroup(grp.modelData.app) }
                            }

                            // cards
                            Repeater {
                                model: grp.folded ? [] : grp.modelData.items
                                Rectangle {
                                    id: card
                                    required property var modelData
                                    readonly property var n: modelData
                                    readonly property bool on: nc.selId === n.id
                                    readonly property bool critical: n.urgency === NotificationUrgency.Critical
                                    readonly property var buttons: n.actions.filter(a => a.identifier !== "default")
                                    property bool expanded: false
                                    objectName: "card:" + n.id
                                    width: grp.width
                                    height: cardCol.implicitHeight + 18
                                    radius: 8
                                    color: on ? Theme.alpha(Theme.accent, 0.09) : cardArea.containsMouse ? Theme.alpha(Theme.surface, 0.9) : Theme.alpha(Theme.surface, 0.55)
                                    border.width: 1
                                    border.color: critical ? Theme.alpha(Theme.red, 0.6) : on ? Theme.alpha(Theme.accent, 0.5) : Theme.border
                                    onOnChanged: if (on) list.reveal(card)
                                    Rectangle { visible: card.on || card.critical; width: 2; height: parent.height - 14; radius: 1; anchors.verticalCenter: parent.verticalCenter; color: card.critical ? Theme.red : Theme.accent }

                                    MouseArea {
                                        id: cardArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: nc.defaultAction(card.n) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                        onEntered: nc.selId = card.n.id
                                        onClicked: m => {
                                            if (m.button === Qt.MiddleButton) { nc.dismiss(card.n); return; }
                                            if (nc.defaultAction(card.n)) nc.activate(card.n); else card.expanded = !card.expanded;
                                        }
                                    }

                                    ColumnLayout {
                                        id: cardCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 10; topMargin: 9 }
                                        spacing: 4
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text {
                                                Layout.fillWidth: true
                                                text: card.n.summary || card.n.appName
                                                elide: Text.ElideRight
                                                font.family: Theme.font
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                color: Theme.text
                                            }
                                            Text {
                                                text: (nc.tick, Notifs.ago(Notifs.timeOf(card.n)))
                                                font.family: Theme.mono; font.pixelSize: 10
                                                color: Theme.dim
                                            }
                                            Text {
                                                text: "✕"
                                                font.family: Theme.mono; font.pixelSize: 11
                                                opacity: cardArea.containsMouse || xArea.containsMouse || card.on ? 1 : 0
                                                color: xArea.containsMouse ? Theme.red : Theme.muted
                                                MouseArea { id: xArea; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: nc.dismiss(card.n) }
                                            }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 10
                                            visible: bodyText.text !== "" || card.n.image !== ""
                                            Text {
                                                id: bodyText
                                                Layout.fillWidth: true
                                                text: card.n.body || ""
                                                textFormat: Text.StyledText
                                                wrapMode: Text.Wrap
                                                maximumLineCount: card.expanded ? 40 : 3
                                                elide: Text.ElideRight
                                                font.family: Theme.font
                                                font.pixelSize: 12
                                                color: Theme.subtext
                                                linkColor: Theme.accent
                                                onLinkActivated: l => Qt.openUrlExternally(l)
                                            }
                                            ClippingRectangle {
                                                visible: card.n.image !== ""
                                                implicitWidth: 52; implicitHeight: 52; radius: 6
                                                color: Theme.surface
                                                Image { anchors.fill: parent; source: card.n.image; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                                            }
                                        }
                                        // action buttons
                                        Flow {
                                            Layout.fillWidth: true
                                            Layout.topMargin: 2
                                            visible: card.buttons.length > 0
                                            spacing: 6
                                            Repeater {
                                                model: card.buttons
                                                Rectangle {
                                                    required property var modelData
                                                    width: abText.implicitWidth + 18; height: 24; radius: 5
                                                    color: abArea.containsMouse ? Theme.alpha(Theme.accent, 0.2) : "transparent"
                                                    border.width: 1
                                                    border.color: Theme.alpha(Theme.accent, abArea.containsMouse ? 0.9 : 0.4)
                                                    Text { id: abText; anchors.centerIn: parent; text: "▸ " + parent.modelData.text.toLowerCase(); font.family: Theme.mono; font.pixelSize: 11; color: Theme.accent }
                                                    MouseArea {
                                                        id: abArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: { parent.modelData.invoke(); if (!card.n.resident) card.n.dismiss(); }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // inbox zero
                Column {
                    x: (list.width - width) / 2
                    y: (list.height - height) / 2 - 20
                    visible: nc.groups.length === 0
                    spacing: 6
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: nc.filter ? "" : ""; font.family: Theme.mono; font.pixelSize: 26; color: Theme.alpha(Theme.accent, 0.6) }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: nc.filter ? "# nothing matches “" + nc.filter + "”" : "# inbox zero"
                        font.family: Theme.mono; font.pixelSize: 12; color: Theme.muted
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !nc.filter && Notifs.quiet
                        text: "do not disturb is on · pop-ups are paused"
                        font.family: Theme.mono; font.pixelSize: 10; color: Theme.violet
                    }
                }
            }

            // ---------------------------------------------------- status line
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 26
                radius: Math.max(0, drawer.radius - 1)
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
                        radius: Math.max(0, drawer.radius - 1)
                        color: nc.armed ? Theme.red : search.activeFocus ? Theme.yellow : Notifs.quiet ? Theme.violet : Theme.accent
                        Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: parent.radius; color: parent.color }
                        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: parent.radius; color: parent.color }
                        Text {
                            id: modeText
                            anchors.centerIn: parent
                            text: nc.armed ? "CLEAR?" : search.activeFocus ? "FILTER" : Notifs.quiet ? "QUIET" : "NOTIFS"
                            font.family: Theme.mono; font.pixelSize: 11; font.weight: Font.Bold
                            color: Theme.onAccent
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "j/k · ↵ open · d dismiss · c fold · / filter · n dnd · C clear"
                        font.family: Theme.mono; font.pixelSize: 10
                        color: Theme.dim
                    }
                }
            }
        }
    }
}
