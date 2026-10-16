// Aurora wallpaper picker: a strip of thumbnails from ~/wallpapers.
//   Super+W toggles it (also the control centre's wallpaper button).
//   ←/→ or scroll to browse · Enter / click to apply · R random · Esc close
// Applying runs aurora-wall, which sets the wallpaper and (with "Match colours"
// on) recolours the shell, borders, kitty and starship to match it.

import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: picker

    // ---- knobs ----
    property real dim: 0.10            // light: you want to see the wallpaper
    property int  thumbW: 232
    property int  thumbH: 140
    property int  openMs: 200
    property int  closeMs: 130
    property bool matchColors: true

    readonly property string wallDir: Quickshell.env("HOME") + "/wallpapers"

    property bool shown: false
    visible: shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "walls"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle { id: backdrop; anchors.fill: parent; color: "black"; opacity: 0 }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: Panels.wallsOpen = false
    }

    // ------------------------------------------------------------ data
    FolderListModel {
        id: walls
        folder: "file://" + picker.wallDir
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.PNG", "*.JPG", "*.JPEG", "*.WEBP"]
        showDirs: false
        sortField: FolderListModel.Name
    }

    // which wallpaper is set right now (written by aurora-wall)
    FileView {
        id: currentFile
        path: Quickshell.env("HOME") + "/.cache/aurora/wallpaper.path"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property string current: (currentFile.text() || "").trim()

    function indexOfCurrent() {
        for (let i = 0; i < walls.count; i++)
            if (walls.get(i, "filePath") === current) return i;
        return 0;
    }

    property bool busy: false
    Process {
        id: applyProc
        onExited: picker.busy = false
    }
    function apply(path) {
        if (!path || busy) return;
        busy = true;
        const bin = Quickshell.env("HOME") + "/.local/bin/aurora-wall";
        applyProc.command = matchColors ? [bin, path] : [bin, path, "--keep"];
        applyProc.running = true;
    }
    function random() {
        if (busy || walls.count < 2) return;
        let i = strip.currentIndex;
        while (i === strip.currentIndex) i = Math.floor(Math.random() * walls.count);
        strip.currentIndex = i;
        apply(walls.get(i, "filePath"));
    }

    // ------------------------------------------------------------ open / close
    Connections {
        target: Panels
        function onWallsOpenChanged() {
            if (Panels.wallsOpen) {
                hide.stop();
                picker.shown = true;
                strip.currentIndex = picker.indexOfCurrent();
                strip.positionViewAtIndex(strip.currentIndex, ListView.Center);
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
        NumberAnimation { target: backdrop; property: "opacity"; to: picker.dim; duration: picker.openMs; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "opacity"; to: 1; duration: picker.openMs; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "anchors.bottomMargin"; from: 0; to: 36; duration: picker.openMs; easing.type: Easing.OutQuint }
    }
    ParallelAnimation {
        id: hide
        onFinished: picker.shown = false
        NumberAnimation { target: backdrop; property: "opacity"; to: 0; duration: picker.closeMs; easing.type: Easing.InQuad }
        NumberAnimation { target: card; property: "opacity"; to: 0; duration: picker.closeMs; easing.type: Easing.InQuad }
        NumberAnimation { target: card; property: "anchors.bottomMargin"; to: 12; duration: picker.closeMs; easing.type: Easing.InQuad }
    }

    // ------------------------------------------------------------ keys
    Item {
        id: keys
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) { Panels.wallsOpen = false; }
            else if (e.key === Qt.Key_Right || e.key === Qt.Key_L || e.key === Qt.Key_Tab) { strip.incrementCurrentIndex(); }
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_H || e.key === Qt.Key_Backtab) { strip.decrementCurrentIndex(); }
            else if (e.key === Qt.Key_Home) { strip.currentIndex = 0; }
            else if (e.key === Qt.Key_End) { strip.currentIndex = walls.count - 1; }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                if (strip.currentItem) picker.apply(strip.currentItem.path);
            }
            else if (e.key === Qt.Key_R) { picker.random(); }
            else if (e.key === Qt.Key_C) { picker.matchColors = !picker.matchColors; }
            else return;
            e.accepted = true;
        }
    }

    // ------------------------------------------------------------ the card
    Rectangle {
        id: card
        opacity: 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 36
        width: Math.min(parent.width - 96, 5 * (picker.thumbW + 14) + 48)
        height: col.implicitHeight + 32
        radius: Theme.radius + 4
        color: Theme.alpha(Theme.surface, 0.94)
        border.width: 1
        border.color: Theme.line
        Behavior on color { ColorAnimation { duration: 400 } }

        // swallow clicks so they don't close the picker
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 14

            // ---- header
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                spacing: 10

                Text {
                    text: "󰸉"
                    color: Theme.accent
                    font.family: Theme.iconFont
                    font.pixelSize: 18
                }
                Text {
                    text: "Wallpapers"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                Text {
                    text: walls.count + " in ~/wallpapers"
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: 12
                }
                Item { Layout.fillWidth: true }

                // busy hint while matugen runs
                Text {
                    visible: picker.busy
                    text: "applying…"
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: 12
                }

                Pill {
                    icon: "󰏘"
                    label: "Match colours"
                    on: picker.matchColors
                    onClicked: picker.matchColors = !picker.matchColors
                }
                Pill {
                    icon: "󰒝"
                    label: "Random"
                    onClicked: picker.random()
                }
                Pill {
                    icon: "󰉋"
                    label: "Folder"
                    onClicked: Quickshell.execDetached(["xdg-open", picker.wallDir])
                }
            }

            // ---- thumbnails
            ListView {
                id: strip
                Layout.fillWidth: true
                Layout.preferredHeight: picker.thumbH + 34
                orientation: ListView.Horizontal
                spacing: 14
                clip: true
                model: walls
                preferredHighlightBegin: width / 2 - picker.thumbW / 2
                preferredHighlightEnd: width / 2 + picker.thumbW / 2
                highlightRangeMode: ListView.ApplyRange
                boundsBehavior: Flickable.StopAtBounds

                // mouse wheel scrolls sideways
                WheelHandler {
                    onWheel: e => {
                        if (e.angleDelta.y < 0 || e.angleDelta.x < 0) strip.incrementCurrentIndex();
                        else strip.decrementCurrentIndex();
                    }
                }

                delegate: Item {
                    id: thumb
                    required property int index
                    required property string filePath
                    required property string fileName
                    required property url fileUrl
                    readonly property string path: filePath
                    readonly property bool selected: ListView.isCurrentItem
                    readonly property bool active: filePath === picker.current

                    width: picker.thumbW
                    height: strip.height

                    ClippingRectangle {
                        id: frame
                        width: parent.width
                        height: picker.thumbH
                        y: 4
                        radius: Theme.radiusSm + 2
                        color: Theme.card
                        scale: thumbArea.containsMouse || thumb.selected ? 1.0 : 0.95
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

                        Image {
                            anchors.fill: parent
                            source: thumb.fileUrl
                            sourceSize.width: picker.thumbW * 2
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            opacity: status === Image.Ready ? (thumb.selected || thumbArea.containsMouse ? 1 : 0.7) : 0
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                        }

                        // "current" badge
                        Rectangle {
                            visible: thumb.active
                            anchors { right: parent.right; top: parent.top; margins: 8 }
                            width: 24; height: 24; radius: 12
                            color: Theme.accent
                            Text {
                                anchors.centerIn: parent
                                text: "󰄬"
                                color: Theme.onAccent
                                font.family: Theme.iconFont
                                font.pixelSize: 14
                            }
                        }
                    }
                    // selection ring (drawn outside the clip)
                    Rectangle {
                        anchors.fill: frame
                        anchors.margins: -3
                        scale: frame.scale
                        radius: frame.radius + 3
                        color: "transparent"
                        border.width: 2
                        border.color: thumb.selected ? Theme.accent : "transparent"
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    Text {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 4 }
                        text: thumb.fileName.replace(/\.[^.]+$/, "")
                        elide: Text.ElideRight
                        color: thumb.selected ? Theme.text : Theme.muted
                        font.family: Theme.font
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: thumbArea
                        anchors.fill: frame
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            strip.currentIndex = thumb.index;
                            picker.apply(thumb.filePath);
                        }
                    }
                }

                // empty folder hint
                Text {
                    anchors.centerIn: parent
                    visible: walls.count === 0
                    text: "No images yet. Drop some .png / .jpg files into ~/wallpapers"
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: 13
                }
            }

            // ---- key hints
            Text {
                Layout.leftMargin: 4
                text: "←/→ browse   ·   Enter apply   ·   R random   ·   C toggle colours   ·   Esc close"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11
            }
        }
    }

    // small header button
    component Pill: Rectangle {
        id: pill
        property string icon
        property string label
        property bool on: false
        signal clicked()

        implicitWidth: pillRow.implicitWidth + 22
        implicitHeight: 30
        radius: 15
        color: on ? Theme.accent : (pillArea.containsMouse ? Theme.cardHover : Theme.card)
        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                text: pill.icon
                color: pill.on ? Theme.onAccent : Theme.subtext
                font.family: Theme.iconFont
                font.pixelSize: 13
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: pill.label
                color: pill.on ? Theme.onAccent : Theme.subtext
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: pillArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }
}
