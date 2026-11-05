// Aurora GPU panel: is the NVIDIA GPU awake, what's keeping it awake, and which GPU mode you boot into.
//   open:  click the GPU pill in the bar  ·  qs ipc call gpu toggle
//   keys:  j/k pick a program · x end it · 1/2/3 integrated / hybrid / nvidia mode · Esc close
//   mouse: move off the panel and it closes

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: gp

    property bool shown: false
    visible: shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "gpu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var procs: Gpu.procs.filter(p => p.name !== "nvidia-smi")
    property int sel: 0
    readonly property var modes: [
        { m: "integrated", t: "integrated", d: "Intel only · the NVIDIA GPU is switched off · best battery" },
        { m: "hybrid",     t: "hybrid",     d: "Intel drives the screen · NVIDIA wakes for apps that ask for it" },
        { m: "nvidia",     t: "nvidia",     d: "NVIDIA drives everything · fastest, worst battery" }
    ]
    // programs people usually don't expect on the dGPU, with a hint
    function why(name) {
        const n = name.toLowerCase();
        if (/^(hyprland|aquamarine)$/.test(n)) return "the compositor: an external screen on the NVIDIA port keeps it on";
        if (/brave|chrome|chromium|electron|code|discord|slack|spotify/.test(n)) return "browser/Electron app with GPU acceleration on the dGPU";
        if (/^(nvidia-powerd|nvidia-persiste)/.test(n)) return "NVIDIA daemon · persistence mode stops it from sleeping";
        if (/steam|wine|proton|\.exe$|game/.test(n)) return "game";
        if (/ollama|python|torch|blender|obs/.test(n)) return "compute / rendering";
        return "";
    }
    function fmt(v, unit, dec) { return v < 0 || v === undefined ? "–" : (dec ? v.toFixed(dec) : Math.round(v)) + unit }

    function close() { Panels.gpuOpen = false }
    property bool wasInside: false
    Timer { id: leaveTimer; interval: 350; onTriggered: if (!cardHover.hovered) gp.close() }
    Connections {
        target: Panels
        function onGpuOpenChanged() {
            if (Panels.gpuOpen) {
                hide.stop();
                gp.shown = true;
                gp.wasInside = false;
                gp.sel = 0;
                Gpu.watching = true;
                Gpu.refresh();
                Power.refresh();
                card.forceActiveFocus();
                appear.restart();
            } else {
                Gpu.watching = false;
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
        onFinished: gp.shown = false
        NumberAnimation { target: slide; property: "y"; to: -8; duration: 120; easing.type: Easing.InCubic }
        NumberAnimation { target: card; property: "opacity"; to: 0; duration: 110 }
    }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: gp.close() }

    component Mono: Text {
        font.family: Theme.mono
        font.pixelSize: 11
        color: Theme.muted
    }
    component Stat: Column {
        property string k: ""
        property string v: ""
        property color tint: Theme.text
        spacing: 2
        Mono { text: parent.k; font.pixelSize: 10; color: Theme.dim }
        Text { text: parent.v; font.family: Theme.mono; font.pixelSize: 15; font.weight: Font.DemiBold; color: parent.tint }
    }

    Rectangle {
        id: card
        objectName: "card"
        anchors { top: parent.top; right: parent.right; topMargin: Theme.barHeight + 8; rightMargin: 10 }
        width: 440
        height: col.implicitHeight + 2
        radius: Theme.radius
        color: Theme.bg
        border.width: 1
        border.color: Theme.alpha(Gpu.awake ? Theme.yellow : Theme.accent, 0.3)
        transform: Translate { id: slide; y: 0 }
        focus: true

        HoverHandler {
            id: cardHover
            onHoveredChanged: {
                if (hovered) { gp.wasInside = true; leaveTimer.stop(); }
                else if (gp.wasInside && Panels.gpuOpen) leaveTimer.restart();
            }
        }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: card.forceActiveFocus() }

        Keys.onPressed: e => {
            const k = e.key;
            if (k === Qt.Key_Escape || k === Qt.Key_Q) gp.close();
            else if (k === Qt.Key_J || k === Qt.Key_Down) gp.sel = Math.min(gp.procs.length - 1, gp.sel + 1);
            else if (k === Qt.Key_K || k === Qt.Key_Up) gp.sel = Math.max(0, gp.sel - 1);
            else if (k === Qt.Key_X || k === Qt.Key_Delete) { if (gp.procs[gp.sel]) Gpu.kill(gp.procs[gp.sel].pid); }
            else if (k >= Qt.Key_1 && k <= Qt.Key_3) Power.setGpu(gp.modes[k - Qt.Key_1].m);
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
                    Text { text: "gpu"; font.family: Theme.mono; font.pixelSize: 13; font.weight: Font.Bold; color: Theme.text }
                    Mono {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: Gpu.name || (Gpu.present ? "NVIDIA · " + Gpu.dev.split("/").pop() : "")
                        color: Theme.dim
                    }
                }
            }

            // ---------------------------------------------------- state
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.bottomMargin: 6
                spacing: 12
                Rectangle {
                    implicitWidth: 12; implicitHeight: 12; radius: 6
                    color: !Gpu.present ? Theme.dim : Gpu.awake ? Theme.yellow : "transparent"
                    border.width: 2
                    border.color: !Gpu.present ? Theme.dim : Gpu.awake ? Theme.yellow : Theme.muted
                    SequentialAnimation on opacity {
                        running: Gpu.awake; loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 900 }
                        NumberAnimation { to: 1; duration: 900 }
                    }
                }
                ColumnLayout {
                    spacing: 1
                    Text {
                        objectName: "stateText"
                        text: !Gpu.present ? (Power.gpu === "integrated" ? "switched off (integrated mode)" : "no NVIDIA GPU found")
                            : Gpu.awake ? "awake" : "asleep"
                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                        color: Gpu.awake ? Theme.yellow : Theme.text
                    }
                    Mono {
                        text: !Gpu.present ? "" : Gpu.awake ? "using power · " + Gpu.dstate : "≈ 0 W · " + (Gpu.dstate || Gpu.status)
                        color: Theme.dim
                    }
                }
            }

            // live numbers
            RowLayout {
                visible: Gpu.awake
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.bottomMargin: 8
                spacing: 22
                Stat { k: "temp"; v: gp.fmt(Gpu.info.temp, "°"); tint: Gpu.info.temp > 80 ? Theme.red : Gpu.info.temp > 65 ? Theme.yellow : Theme.text }
                Stat { k: "load"; v: gp.fmt(Gpu.info.util, "%") }
                Stat { k: "power"; v: gp.fmt(Gpu.info.power, " W", 1); tint: Gpu.info.power > 30 ? Theme.yellow : Theme.text }
                Stat { k: "vram"; v: Gpu.info.memUsed >= 0 && Gpu.info.memTotal > 0 ? Math.round(Gpu.info.memUsed) + "/" + Math.round(Gpu.info.memTotal) : "–" }
                Stat { k: "state"; v: Gpu.info.pstate || "–" }
            }

            // ---------------------------------------------------- who keeps it awake
            Mono {
                visible: Gpu.present
                Layout.leftMargin: 16
                Layout.topMargin: 4
                text: "# using it  " + gp.procs.length
                color: Theme.dim
            }
            Mono {
                visible: Gpu.present && gp.procs.length === 0
                Layout.leftMargin: 16
                Layout.topMargin: 4
                Layout.bottomMargin: 6
                text: Gpu.awake ? "nothing — it should fall asleep in a few seconds" : "nothing · run an app on it with:  prime-run <app>"
                color: Theme.muted
            }
            Repeater {
                model: gp.procs
                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool isSel: index === gp.sel
                    objectName: "proc:" + modelData.name
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    implicitHeight: gp.why(modelData.name) ? 42 : 30
                    radius: 7
                    color: isSel ? Theme.alpha(Theme.accent, 0.10) : procArea.containsMouse ? Theme.hover : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Row {
                                spacing: 8
                                Text { text: modelData.name; font.family: Theme.mono; font.pixelSize: 12; color: Theme.text }
                                Mono { text: modelData.pid; color: Theme.dim }
                            }
                            Mono {
                                visible: text !== ""
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: gp.why(modelData.name)
                                font.pixelSize: 10
                                color: Theme.dim
                            }
                        }
                        Rectangle {
                            visible: isSel || procArea.containsMouse
                            implicitWidth: endText.implicitWidth + 14; implicitHeight: 22; radius: 5
                            color: endArea.containsMouse ? Theme.alpha(Theme.red, 0.2) : "transparent"
                            border.width: 1; border.color: Theme.alpha(Theme.red, 0.5)
                            Mono { id: endText; anchors.centerIn: parent; text: "x end"; color: Theme.red }
                            MouseArea { id: endArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Gpu.kill(modelData.pid) }
                        }
                    }
                    MouseArea { id: procArea; anchors.fill: parent; hoverEnabled: true; z: -1; onEntered: gp.sel = index }
                }
            }

            // ---------------------------------------------------- boot mode (envycontrol)
            Mono {
                visible: Power.hasEnvy
                Layout.leftMargin: 16
                Layout.topMargin: 10
                text: "# mode  " + (Power.gpuPending ? "→ " + Power.gpu + " after reboot" : "")
                color: Power.gpuPending ? Theme.yellow : Theme.dim
            }
            Row {
                visible: Power.hasEnvy
                Layout.leftMargin: 14
                Layout.topMargin: 6
                spacing: 6
                Repeater {
                    model: gp.modes
                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool cur: Power.gpu === modelData.m
                        readonly property bool running: (Power.bootGpu || Power.gpu) === modelData.m
                        objectName: "mode:" + modelData.m
                        implicitWidth: modeRow.implicitWidth + 18
                        implicitHeight: 28
                        radius: 6
                        color: cur ? Theme.accentSoft : modeArea.containsMouse ? Theme.hover : "transparent"
                        border.width: 1
                        border.color: cur ? Theme.alpha(Theme.accent, 0.6) : Theme.cardHi
                        Row {
                            id: modeRow
                            anchors.centerIn: parent
                            spacing: 6
                            Mono { text: (index + 1); color: Theme.dim }
                            Mono { text: modelData.t; color: cur ? Theme.accent : Theme.muted }
                            Mono { visible: running && Power.gpuPending; text: "(now)"; color: Theme.dim }
                        }
                        MouseArea { id: modeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Power.setGpu(modelData.m) }
                    }
                }
            }
            Mono {
                visible: Power.hasEnvy
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 6
                wrapMode: Text.Wrap
                text: Power.gpuBusy ? "asking for your password…" : Power.gpuError !== "" ? Power.gpuError
                    : (gp.modes.find(x => x.m === Power.gpu) || { d: "" }).d
                color: Power.gpuError !== "" ? Theme.red : Theme.dim
            }
            Item { implicitHeight: 12 }

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
                        color: Gpu.awake ? Theme.yellow : Theme.dim
                        Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: parent.radius; color: parent.color }
                        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: parent.radius; color: parent.color }
                        Text {
                            id: modeText
                            anchors.centerIn: parent
                            text: Gpu.awake ? "AWAKE" : "ASLEEP"
                            font.family: Theme.mono; font.pixelSize: 11; font.weight: Font.Bold
                            color: Theme.onAccent
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Mono { text: "j/k · x end · 1/2/3 mode · esc"; font.pixelSize: 10; color: Theme.dim }
                }
            }
        }
    }
}
