// Volume / brightness pop-up: a glass pill that slides up at the bottom of the
// screen when you press the keys, then fades away.
//   volume: shown automatically whenever the volume or mute changes
//   brightness: the Hyprland keybind calls  qs ipc call osd brightness

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire

PanelWindow {
    id: osd

    anchors { bottom: true }                  // bottom-anchored only = centred
    margins { bottom: 70 }
    exclusiveZone: 0
    implicitWidth: 300
    implicitHeight: 52
    color: "transparent"
    visible: false
    WlrLayershell.namespace: "aurora-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}                           // clicks pass straight through

    property string kind: "volume"            // "volume" | "brightness" | "night"
    property real value: 0
    property bool muted: false

    // ---------------------------------------------------------------- volume
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [osd.sink] }
    property bool armed: false                // ignore the initial values at startup
    Timer { running: true; interval: 2000; onTriggered: osd.armed = true }

    Connections {
        target: osd.sink ? osd.sink.audio : null
        function onVolumesChanged() { osd.showVolume() }
        function onMutedChanged() { osd.showVolume() }
    }
    function showVolume() {
        if (!armed || !sink || !sink.audio) return;
        kind = "volume";
        value = sink.audio.volume;
        muted = sink.audio.muted;
        pop();
    }

    // ---------------------------------------------------------------- brightness
    Process {
        id: brightnessGet
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(",");
                if (p.length < 5) return;
                osd.kind = "brightness";
                osd.value = parseInt(p[2]) / parseInt(p[4]);
                osd.muted = false;
                osd.pop();
            }
        }
    }
    // ---------------------------------------------------------------- night light
    property string label: ""
    Connections {
        target: NightLight
        function onModeChanged() { osd.showNight() }
        function onTempChanged() { osd.showNight() }
    }
    function showNight() {
        if (!armed) return;
        kind = "night";
        muted = NightLight.mode === "off";
        value = muted ? 0 : (NightLight.maxTemp - NightLight.temp) / (NightLight.maxTemp - NightLight.minTemp);
        label = NightLight.mode === "off" ? "off" : NightLight.mode === "auto" ? "auto" : NightLight.temp + "K";
        pop();
    }

    IpcHandler {
        target: "osd"
        function brightness(): void { brightnessGet.running = true }
        function volume(): void { osd.showVolume() }
    }

    // ---------------------------------------------------------------- show / hide
    function pop() {
        hideTimer.restart();
        if (!visible) {
            visible = true;
            hideAnim.stop();
            showAnim.restart();
        }
    }
    Timer { id: hideTimer; interval: 1400; onTriggered: hideAnim.restart() }

    ParallelAnimation {
        id: showAnim
        NumberAnimation { target: pill; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutQuad }
        NumberAnimation { target: rise; property: "y"; from: 14; to: 0; duration: 220; easing.type: Easing.OutQuint }
    }
    SequentialAnimation {
        id: hideAnim
        NumberAnimation { target: pill; property: "opacity"; to: 0; duration: 220; easing.type: Easing.InQuad }
        ScriptAction { script: osd.visible = false }
    }

    // ---------------------------------------------------------------- the pill
    Rectangle {
        id: pill
        anchors.fill: parent
        radius: height / 2
        color: Theme.alpha(Theme.surface, 0.92)
        border.color: Theme.alpha(Theme.text, 0.10)
        border.width: 1
        opacity: 0
        transform: Translate { id: rise; y: 0 }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 14

            Text {
                text: osd.kind === "night" ? "󰖔"
                    : osd.kind === "brightness" ? ""
                    : osd.muted ? ""
                    : osd.value < 0.4 ? "" : ""
                font.family: Theme.iconFont
                font.pixelSize: 17
                color: osd.kind === "night" ? (osd.muted ? Theme.dim : Theme.yellow) : osd.muted ? Theme.red : Theme.accent
                Layout.preferredWidth: 20
                horizontalAlignment: Text.AlignHCenter
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 6
                radius: 3
                color: Theme.card
                Rectangle {
                    height: parent.height
                    radius: 3
                    width: parent.width * Math.max(0, Math.min(1, osd.value))
                    color: osd.kind === "night" ? Theme.yellow : osd.muted ? Theme.dim : Theme.accent
                    Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                }
            }
            Text {
                text: osd.kind === "night" ? osd.label : osd.muted ? "muted" : Math.round(osd.value * 100)
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: Theme.text
                Layout.preferredWidth: 46
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
