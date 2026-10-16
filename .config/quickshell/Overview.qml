// Aurora overview: every workspace at a glance with live window previews.
//   Super+Tab toggles it.
//   click a window → focus it · click a workspace → go there
//   drag a window onto another workspace → move it there
//   ←/→ pick a workspace · 1-9 jump · Enter go · Esc close
//   middle-click a window → close it

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: ov

    // ---- knobs --------------------------------------------------------------
    property int  minWorkspaces: 5      // always show 1..5, more if windows live higher
    property real tileScale: 0.16       // size of each workspace vs the real screen
    property bool livePreviews: true    // false = one still frame per window (lighter)
    property real dim: 0.45
    property int  openMs: 200
    property int  closeMs: 130

    property bool shown: false
    visible: shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // ------------------------------------------------------------ geometry
    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property var monObj: monitor ? monitor.lastIpcObject : ({})
    readonly property real monX: monObj.x ?? 0
    readonly property real monY: monObj.y ?? 0
    readonly property real monW: monObj.width ? monObj.width / (monObj.scale || 1) : (screen ? screen.width : 1920)
    readonly property real monH: monObj.height ? monObj.height / (monObj.scale || 1) : (screen ? screen.height : 1080)
    readonly property real tileW: Math.round(monW * tileScale)
    readonly property real tileH: Math.round(monH * tileScale)

    readonly property int activeWs: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    readonly property int wsCount: {
        let n = minWorkspaces;
        for (const t of Hyprland.toplevels.values)
            if (t.workspace && t.workspace.id > n && t.workspace.id < 100) n = t.workspace.id;
        return Math.min(n, 10);
    }
    property int selected: 1

    function windowsOn(id) {
        return Hyprland.toplevels.values.filter(t => t.workspace && t.workspace.id === id);
    }

    // ------------------------------------------------------------ actions (Lua dispatchers)
    function focusWindow(t) {
        Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + t.address + '" })');
        Panels.overviewOpen = false;
    }
    function goTo(id) {
        Hyprland.dispatch('hl.dsp.focus({ workspace = "' + id + '" })');
        Panels.overviewOpen = false;
    }
    function moveWindow(t, id) {
        Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + id + '", follow = false, window = "address:0x' + t.address + '" })');
        refreshSoon.restart();
    }
    function closeWindow(t) {
        Hyprland.dispatch('hl.dsp.window.close({ window = "address:0x' + t.address + '" })');
        refreshSoon.restart();
    }
    Timer { id: refreshSoon; interval: 120; onTriggered: Hyprland.refreshToplevels() }

    // wallpaper for the tiles
    FileView {
        id: wallFile
        path: Quickshell.env("HOME") + "/.cache/aurora/wallpaper.path"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property string wallpaper: (wallFile.text() || "").trim()

    // ------------------------------------------------------------ open / close
    Connections {
        target: Panels
        function onOverviewOpenChanged() {
            if (Panels.overviewOpen) {
                hide.stop();
                Hyprland.refreshToplevels();
                Hyprland.refreshMonitors();
                ov.selected = ov.activeWs;
                ov.shown = true;
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
        NumberAnimation { target: backdrop; property: "opacity"; to: ov.dim; duration: ov.openMs; easing.type: Easing.OutQuad }
        NumberAnimation { target: content; property: "opacity"; to: 1; duration: ov.openMs; easing.type: Easing.OutQuad }
        NumberAnimation { target: content; property: "scale"; from: 0.94; to: 1; duration: ov.openMs + 60; easing.type: Easing.OutQuint }
    }
    ParallelAnimation {
        id: hide
        onFinished: ov.shown = false
        NumberAnimation { target: backdrop; property: "opacity"; to: 0; duration: ov.closeMs; easing.type: Easing.InQuad }
        NumberAnimation { target: content; property: "opacity"; to: 0; duration: ov.closeMs; easing.type: Easing.InQuad }
        NumberAnimation { target: content; property: "scale"; to: 0.97; duration: ov.closeMs; easing.type: Easing.InQuad }
    }

    Rectangle { id: backdrop; anchors.fill: parent; color: "black"; opacity: 0 }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: Panels.overviewOpen = false
    }

    Item {
        id: keys
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) Panels.overviewOpen = false;
            else if (e.key === Qt.Key_Left) ov.selected = Math.max(1, ov.selected - 1);
            else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab) ov.selected = ov.selected >= ov.wsCount ? 1 : ov.selected + 1;
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) ov.goTo(ov.selected);
            else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) ov.goTo(e.key - Qt.Key_0);
            else return;
            e.accepted = true;
        }
    }

    // ------------------------------------------------------------ drag state
    property var dragWin: null          // HyprlandToplevel being dragged
    property int dropWs: -1             // workspace under the cursor while dragging

    function wsAt(gx, gy) {
        for (let i = 0; i < tiles.count; i++) {
            const it = tiles.itemAt(i);
            if (!it) continue;
            const p = it.mapFromItem(null, gx, gy);
            if (p.x >= 0 && p.y >= 0 && p.x <= it.width && p.y <= it.height) return i + 1;
        }
        return -1;
    }

    // ============================================================ content
    Item {
        id: content
        anchors.fill: parent
        opacity: 0

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 18

            // header
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10
                Text {
                    text: "󰕰"
                    color: Theme.accent
                    font.family: Theme.iconFont
                    font.pixelSize: 18
                }
                Text {
                    text: "Workspaces"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
                Text {
                    text: Hyprland.toplevels.values.length + " windows"
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }

            // the workspaces
            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 18

                Repeater {
                    id: tiles
                    model: ov.wsCount

                    Item {
                        id: tile
                        required property int index
                        readonly property int wsId: index + 1
                        readonly property bool isActive: wsId === ov.activeWs
                        readonly property bool isSelected: wsId === ov.selected
                        readonly property bool isDrop: ov.dragWin !== null && ov.dropWs === wsId
                        readonly property var wins: ov.windowsOn(wsId)

                        width: ov.tileW
                        height: ov.tileH + 30

                        // workspace "screen"
                        ClippingRectangle {
                            id: screenRect
                            width: ov.tileW
                            height: ov.tileH
                            radius: Theme.radiusSm + 2
                            color: Theme.bg
                            border.width: 2
                            border.color: tile.isDrop ? Theme.violet
                                        : tile.isActive ? Theme.accent
                                        : tile.isSelected || tileArea.containsMouse ? Theme.alpha(Theme.text, 0.35)
                                        : Theme.alpha(Theme.text, 0.08)
                            scale: tile.isDrop ? 1.04 : 1
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
                            Behavior on border.color { ColorAnimation { duration: 140 } }

                            Image {
                                anchors.fill: parent
                                source: ov.wallpaper ? "file://" + ov.wallpaper : ""
                                sourceSize.width: ov.tileW * 2
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                opacity: 0.85
                            }

                            // clicking empty space → go to this workspace
                            MouseArea {
                                id: tileArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: ov.goTo(tile.wsId)
                            }

                            // windows, placed where they really are (scaled down)
                            Repeater {
                                model: tile.wins
                                Item {
                                    id: win
                                    required property var modelData
                                    readonly property var ipc: modelData.lastIpcObject || {}
                                    readonly property var at: ipc.at || [ov.monX, ov.monY]
                                    readonly property var sz: ipc.size || [ov.monW / 2, ov.monH / 2]
                                    readonly property bool focused: Hyprland.activeToplevel === modelData
                                    readonly property string cls: ipc.class || ""
                                    readonly property bool dragging: ov.dragWin === modelData

                                    x: (at[0] - ov.monX) * ov.tileScale
                                    y: (at[1] - ov.monY) * ov.tileScale
                                    width: Math.max(18, sz[0] * ov.tileScale)
                                    height: Math.max(14, sz[1] * ov.tileScale)
                                    z: ipc.floating ? 2 : 1
                                    opacity: dragging ? 0.35 : 1

                                    ClippingRectangle {
                                        anchors.fill: parent
                                        radius: 5
                                        color: Theme.surface
                                        border.width: 1
                                        border.color: winArea.containsMouse ? Theme.accent
                                                    : win.focused ? Theme.alpha(Theme.accent, 0.6)
                                                    : Theme.alpha(Theme.text, 0.15)

                                        ScreencopyView {
                                            id: shot
                                            anchors.fill: parent
                                            captureSource: ov.shown && win.modelData.wayland ? win.modelData.wayland : null
                                            live: ov.livePreviews
                                        }
                                        // icon fallback until (or unless) a frame arrives
                                        IconImage {
                                            visible: !shot.hasContent || win.width > 70
                                            anchors.centerIn: !shot.hasContent ? parent : undefined
                                            anchors.right: shot.hasContent ? parent.right : undefined
                                            anchors.bottom: shot.hasContent ? parent.bottom : undefined
                                            anchors.margins: 4
                                            implicitSize: shot.hasContent ? 16 : Math.min(28, win.height * 0.5)
                                            source: {
                                                const e = DesktopEntries.heuristicLookup(win.cls);
                                                return Quickshell.iconPath(e ? e.icon : win.cls.toLowerCase(), "application-x-executable");
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: winArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                        cursorShape: ov.dragWin ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                        property point pressAt
                                        property bool moved: false

                                        onPressed: m => { pressAt = Qt.point(m.x, m.y); moved = false; }
                                        onPositionChanged: m => {
                                            if (!pressed) return;
                                            if (!moved && Math.hypot(m.x - pressAt.x, m.y - pressAt.y) > 6) {
                                                moved = true;
                                                ov.dragWin = win.modelData;
                                                ghost.w = win.width; ghost.h = win.height;
                                                ghost.cls = win.cls;
                                            }
                                            if (moved) {
                                                const g = mapToItem(null, m.x, m.y);
                                                ghost.x = g.x - ghost.w / 2;
                                                ghost.y = g.y - ghost.h / 2;
                                                ov.dropWs = ov.wsAt(g.x, g.y);
                                            }
                                        }
                                        onReleased: m => {
                                            if (moved) {
                                                if (ov.dropWs > 0 && ov.dropWs !== tile.wsId) ov.moveWindow(win.modelData, ov.dropWs);
                                                ov.dragWin = null;
                                                ov.dropWs = -1;
                                            }
                                        }
                                        onClicked: m => {
                                            if (moved) return;
                                            if (m.button === Qt.MiddleButton) ov.closeWindow(win.modelData);
                                            else ov.focusWindow(win.modelData);
                                        }
                                    }

                                    // title tooltip on hover
                                    Rectangle {
                                        visible: winArea.containsMouse && !ov.dragWin
                                        z: 10
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.bottom
                                        anchors.topMargin: 4
                                        width: Math.min(260, tip.implicitWidth + 16)
                                        height: 22
                                        radius: 11
                                        color: Theme.surface
                                        border.width: 1
                                        border.color: Theme.line
                                        Text {
                                            id: tip
                                            anchors.centerIn: parent
                                            width: parent.width - 16
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                            text: win.modelData.title
                                            color: Theme.text
                                            font.family: Theme.font
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }

                        // label under the tile
                        Row {
                            anchors.top: screenRect.bottom
                            anchors.topMargin: 8
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 6
                            Rectangle {
                                width: 18; height: 18; radius: 6
                                color: tile.isActive ? Theme.accent : Theme.card
                                Text {
                                    anchors.centerIn: parent
                                    text: tile.wsId
                                    color: tile.isActive ? Theme.onAccent : Theme.subtext
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: tile.wins.length === 0 ? "empty"
                                    : tile.wins.length === 1 ? (tile.wins[0].lastIpcObject?.class || "1 window")
                                    : tile.wins.length + " windows"
                                color: tile.isSelected ? Theme.text : Theme.muted
                                font.family: Theme.font
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "click to focus  ·  drag to move  ·  middle-click to close  ·  1-9 jump  ·  Esc"
                color: Theme.alpha(Theme.text, 0.45)
                font.family: Theme.font
                font.pixelSize: 11
            }
        }

        // the window being dragged
        Rectangle {
            id: ghost
            property real w: 60
            property real h: 40
            property string cls: ""
            visible: ov.dragWin !== null
            width: w; height: h
            z: 100
            radius: 6
            color: Theme.alpha(Theme.accent, 0.25)
            border.width: 2
            border.color: Theme.accent
            IconImage {
                anchors.centerIn: parent
                implicitSize: Math.min(28, parent.height * 0.6)
                source: {
                    const e = DesktopEntries.heuristicLookup(ghost.cls);
                    return Quickshell.iconPath(e ? e.icon : ghost.cls.toLowerCase(), "application-x-executable");
                }
            }
        }
    }
}
