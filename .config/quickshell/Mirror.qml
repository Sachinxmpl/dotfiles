// Aurora mirror: a webcam viewfinder. Check yourself before a call, take a photo, record a clip,
// or shrink it to a floating bubble that stays on screen (great for screen recordings).
//   open:  Super+Shift+C  ·  qs ipc call mirror toggle | bubble
//   keys:  Space photo · r record / stop · t timer (off/3 s/10 s) · m mic · f flip · g grid
//          p bubble · Tab next camera · o open the folder · Esc stop / close
//   bubble: drag to move · scroll to resize · right-click (or ⤢) back to the full view
// Photos → ~/Pictures/Webcam · clips → ~/Videos/Webcam
// Needs Qt Multimedia:  sudo pacman -S --needed qt6-multimedia qt6-multimedia-ffmpeg
// The camera (and its light) is only on while this is open: shell.qml unloads it on close.

import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: mr

    visible: Panels.mirrorOpen
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "mirror"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Panels.mirrorOpen && !bubble ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // in bubble mode only the bubble catches the mouse; everything else clicks through
    mask: Region { item: mr.bubble ? bubbleBox : everything }
    Item { id: everything; anchors.fill: parent }

    readonly property bool bubble: Panels.mirrorBubble

    // ------------------------------------------------------------ camera
    MediaDevices { id: devs }
    readonly property var cams: devs.videoInputs
    property int camIdx: 0
    readonly property var device: cams.length ? cams[camIdx % cams.length] : null

    // best format: smooth (24+ fps) first, then up to 1080p, then the most fps
    function bestFormat(d) {
        if (!d || !d.videoFormats || !d.videoFormats.length) return null;
        let best = null, score = -1;
        for (const f of d.videoFormats) {
            const h = f.resolution.height, fps = f.maxFrameRate;
            const s = (fps >= 24 ? 1e7 : 0) + Math.min(h, 1080) * 1000 + Math.min(fps, 60);
            if (s > score) { score = s; best = f; }
        }
        return best;
    }

    CaptureSession {
        id: session
        camera: Camera {
            id: cam
            cameraDevice: mr.device ?? devs.defaultVideoInput
            active: mr.device !== null
        }
        imageCapture: ImageCapture {
            id: shooter
            onImageSaved: (id, path) => {
                mr.lastShot = "file://" + path;
                mr.say("photo saved", path);
                Quickshell.execDetached(["notify-send", "-a", "Camera", "-i", path, "Photo saved", path.replace(mr.home, "~")]);
            }
            onErrorOccurred: (id, err, msg) => mr.say("photo failed", msg)
        }
        recorder: MediaRecorder {
            id: rec
            quality: MediaRecorder.HighQuality
            mediaFormat {
                fileFormat: MediaFormat.MPEG4
                videoCodec: MediaFormat.VideoCodec.H264
                audioCodec: MediaFormat.AudioCodec.AAC
            }
            onRecorderStateChanged: {
                Panels.mirrorRecording = recorderState === MediaRecorder.RecordingState;
                if (recorderState === MediaRecorder.StoppedState && mr.clipPath !== "") {
                    const p = String(actualLocation).replace("file://", "") || mr.clipPath;
                    mr.say("clip saved", p);
                    Quickshell.execDetached(["notify-send", "-a", "Camera", "-i", "camera-video", "Clip saved", p.replace(mr.home, "~")]);
                    mr.clipPath = "";
                }
            }
            onErrorOccurred: (err, msg) => { mr.say("recording failed", msg); mr.clipPath = ""; }
        }
        audioInput: mr.mic ? micIn : null
        videoOutput: view
    }
    AudioInput { id: micIn }
    // pick a good resolution/fps (the default is often 640×480)
    Binding {
        target: cam
        property: "cameraFormat"
        value: mr.bestFormat(mr.device)
        when: mr.bestFormat(mr.device) !== null && !mr.recording
    }

    // ------------------------------------------------------------ state
    readonly property string home: Quickshell.env("HOME")
    property bool flip: true              // mirror the preview like a real mirror (photos are saved unflipped)
    property bool grid: false
    property bool mic: true
    property int timer: 0                 // seconds before a photo: 0 · 3 · 10
    property int count: 0                 // countdown on screen
    property string lastShot: ""
    property string clipPath: ""
    property string toast: ""
    property string toastDetail: ""
    readonly property bool recording: rec.recorderState === MediaRecorder.RecordingState
    readonly property bool ready: cam.active && cam.error === Camera.NoError

    function stamp() { return Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss") }
    function say(t, d) { toast = t; toastDetail = d ? String(d).replace(home, "~") : ""; toastTimer.restart(); }
    Timer { id: toastTimer; interval: 2600; onTriggered: mr.toast = "" }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", home + "/Pictures/Webcam", home + "/Videos/Webcam"])

    function shoot() {
        if (!ready || count > 0) return;
        if (timer > 0) { count = timer; countdown.restart(); return; }
        snap();
    }
    function snap() {
        flash.restart();
        shooter.captureToFile(home + "/Pictures/Webcam/aurora-" + stamp() + ".jpg");
    }
    Timer {
        id: countdown
        interval: 1000; repeat: true
        onTriggered: { mr.count--; if (mr.count <= 0) { stop(); mr.snap(); } }
    }
    function toggleRecord() {
        if (recording) { rec.stop(); return; }
        if (!ready) return;
        clipPath = home + "/Videos/Webcam/aurora-" + stamp() + ".mp4";
        rec.outputLocation = "file://" + clipPath;
        rec.record();
    }
    function nextCam() { if (cams.length > 1 && !recording) camIdx = (camIdx + 1) % cams.length }
    function toggleMic() { if (!recording) mic = !mic }
    function cycleTimer() { timer = timer === 0 ? 3 : timer === 3 ? 10 : 0 }
    function setBubble(b) { Panels.mirrorBubble = b; if (!b) card.forceActiveFocus(); }
    function back() {
        if (count > 0) { countdown.stop(); count = 0; }
        else if (recording) rec.stop();
        else Panels.mirrorOpen = false;
    }

    // closed from outside (keybind, another panel) while recording: finish the file first.
    // shell.qml keeps this loaded until Panels.mirrorRecording goes false.
    Connections {
        target: Panels
        function onMirrorOpenChanged() {
            if (!Panels.mirrorOpen && mr.recording) rec.stop();
            if (Panels.mirrorOpen && !mr.bubble) card.forceActiveFocus();
        }
    }

    // ------------------------------------------------------------ the picture (shared by both modes)
    // one VideoOutput, re-parented into the card or the bubble (into a holder declared first,
    // so the HUD drawn after it stays on top)
    VideoOutput {
        id: view
        parent: mr.bubble ? bubbleVideo : screenVideo
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        transform: Scale { origin.x: view.width / 2; xScale: mr.flip ? -1 : 1 }
    }

    component Mono: Text {
        font.family: Theme.mono
        font.pixelSize: 11
        color: Theme.muted
    }
    component Chip: Rectangle {
        id: chip
        property string icon: ""
        property string label: ""
        property bool on: false
        property color tint: Theme.accent
        property bool dimmed: false
        signal clicked()
        implicitWidth: chipRow.implicitWidth + 18
        implicitHeight: 30
        radius: 7
        opacity: dimmed ? 0.4 : 1
        color: on ? Theme.alpha(tint, 0.16) : chipArea.containsMouse ? Theme.hover : "transparent"
        border.width: 1
        border.color: on ? Theme.alpha(tint, 0.6) : Theme.cardHi
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Text { anchors.verticalCenter: parent.verticalCenter; text: chip.icon; font.family: Theme.iconFont; font.pixelSize: 14; color: chip.on ? chip.tint : Theme.subtext }
            Mono { anchors.verticalCenter: parent.verticalCenter; text: chip.label; visible: text !== ""; color: chip.on ? chip.tint : Theme.muted }
        }
        MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }

    // ============================================================ full view
    Rectangle {
        anchors.fill: parent
        visible: !mr.bubble
        color: "black"
        opacity: 0.35
    }
    MouseArea {
        anchors.fill: parent
        visible: !mr.bubble
        acceptedButtons: Qt.AllButtons
        onClicked: if (!mr.recording) Panels.mirrorOpen = false
    }

    Rectangle {
        id: card
        objectName: "card"
        visible: !mr.bubble
        anchors.centerIn: parent
        width: 780
        height: col.implicitHeight + 2
        radius: Theme.radius
        color: Theme.bg
        border.width: 1
        border.color: mr.recording ? Theme.red : Theme.alpha(Theme.accent, 0.3)
        focus: true
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: card.forceActiveFocus() }

        Keys.onPressed: e => {
            const k = e.key;
            if (k === Qt.Key_Escape || k === Qt.Key_Q) mr.back();
            else if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) mr.shoot();
            else if (k === Qt.Key_R) mr.toggleRecord();
            else if (k === Qt.Key_T) mr.cycleTimer();
            else if (k === Qt.Key_M) mr.toggleMic();
            else if (k === Qt.Key_F) mr.flip = !mr.flip;
            else if (k === Qt.Key_G) mr.grid = !mr.grid;
            else if (k === Qt.Key_P) mr.setBubble(true);
            else if (k === Qt.Key_Tab) mr.nextCam();
            else if (k === Qt.Key_O) { Quickshell.execDetached(["xdg-open", mr.home + "/Pictures/Webcam"]); Panels.mirrorOpen = false; }
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
                    anchors.rightMargin: 10
                    spacing: 8
                    Text { text: "❯"; font.family: Theme.mono; font.pixelSize: 13; color: Theme.accent }
                    Text { text: "mirror"; font.family: Theme.mono; font.pixelSize: 13; font.weight: Font.Bold; color: Theme.text }
                    Mono {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: mr.device ? "/dev/video · " + mr.device.description + (mr.cams.length > 1 ? "   [tab " + (mr.camIdx + 1) + "/" + mr.cams.length + "]" : "") : ""
                        color: Theme.dim
                    }
                    Chip { icon: "󰊓"; label: "bubble"; onClicked: mr.setBubble(true) }
                }
            }

            // ---------------------------------------------------- viewfinder
            ClippingRectangle {
                id: screenClip
                objectName: "screen"
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.bottomMargin: 12
                implicitHeight: Math.round((card.width - 34) * 9 / 16)
                radius: Theme.radiusSm
                color: "#000000"
                Item { id: screenVideo; anchors.fill: parent }

                // no camera / error
                Column {
                    anchors.centerIn: parent
                    visible: !mr.ready
                    spacing: 8
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰗟"; font.family: Theme.iconFont; font.pixelSize: 44; color: Theme.dim }
                    Mono {
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.pixelSize: 13
                        text: mr.cams.length === 0 ? "# no camera found" : cam.errorString !== "" ? "# " + cam.errorString : "# starting camera…"
                        color: cam.errorString !== "" ? Theme.red : Theme.muted
                    }
                    Mono {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: mr.cams.length === 0 || cam.errorString !== ""
                        text: "is another app using it?  check:  fuser /dev/video*"
                        color: Theme.dim
                    }
                }

                // rule of thirds
                Repeater {
                    model: mr.grid ? 4 : 0
                    Rectangle {
                        required property int index
                        readonly property bool vertical: index < 2
                        x: vertical ? screenClip.width * (index + 1) / 3 : 0
                        y: vertical ? 0 : screenClip.height * (index - 1) / 3
                        width: vertical ? 1 : screenClip.width
                        height: vertical ? screenClip.height : 1
                        color: Qt.rgba(1, 1, 1, 0.28)
                    }
                }

                // viewfinder corners
                Repeater {
                    model: 4
                    Item {
                        required property int index
                        readonly property bool onRight: index % 2 === 1      // (right/bottom are taken by Item)
                        readonly property bool onBottom: index >= 2
                        width: 22; height: 22
                        x: onRight ? screenClip.width - width - 14 : 14
                        y: onBottom ? screenClip.height - height - 14 : 14
                        Rectangle { width: 22; height: 2; y: parent.onBottom ? 20 : 0; color: mr.recording ? Theme.red : Theme.accent; opacity: 0.85 }
                        Rectangle { width: 2; height: 22; x: parent.onRight ? 20 : 0; color: mr.recording ? Theme.red : Theme.accent; opacity: 0.85 }
                    }
                }

                // HUD: format top-right, rec top-left
                Rectangle {
                    visible: mr.ready
                    anchors { top: parent.top; right: parent.right; margins: 18 }
                    implicitWidth: fmtText.implicitWidth + 14; implicitHeight: 20; radius: 4
                    color: Qt.rgba(0, 0, 0, 0.5)
                    Mono {
                        id: fmtText
                        anchors.centerIn: parent
                        font.pixelSize: 10
                        color: "#e6edf7"
                        text: cam.cameraFormat.resolution.width + "×" + cam.cameraFormat.resolution.height
                              + " · " + Math.round(cam.cameraFormat.maxFrameRate) + "fps" + (mr.flip ? " · mirrored" : "")
                    }
                }
                Rectangle {
                    visible: mr.recording
                    anchors { top: parent.top; left: parent.left; margins: 18 }
                    implicitWidth: recRow.implicitWidth + 16; implicitHeight: 22; radius: 11
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Row {
                        id: recRow
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8; height: 8; radius: 4; color: Theme.red
                            SequentialAnimation on opacity {
                                running: mr.recording; loops: Animation.Infinite
                                NumberAnimation { to: 0.25; duration: 600 }
                                NumberAnimation { to: 1; duration: 600 }
                            }
                        }
                        Mono {
                            font.pixelSize: 11; font.weight: Font.Bold; color: "#ffffff"
                            text: "REC " + Qt.formatTime(new Date(0, 0, 0, 0, 0, Math.floor(rec.duration / 1000)), "mm:ss") + (mr.mic ? "" : "  · no mic")
                        }
                    }
                }

                // countdown
                Text {
                    anchors.centerIn: parent
                    visible: mr.count > 0
                    text: mr.count
                    font.family: Theme.mono
                    font.pixelSize: 120
                    font.weight: Font.Bold
                    color: "#ffffff"
                    style: Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.4)
                }

                // shutter flash
                Rectangle {
                    id: flashRect
                    anchors.fill: parent
                    color: "white"
                    opacity: 0
                    SequentialAnimation {
                        id: flash
                        NumberAnimation { target: flashRect; property: "opacity"; to: 0.85; duration: 40 }
                        NumberAnimation { target: flashRect; property: "opacity"; to: 0; duration: 380; easing.type: Easing.OutQuad }
                    }
                }

                // last photo
                ClippingRectangle {
                    visible: mr.lastShot !== ""
                    anchors { left: parent.left; bottom: parent.bottom; leftMargin: 46; bottomMargin: 20 }
                    width: 96; height: 54; radius: 6
                    border.width: 2; border.color: "#ffffff"
                    Image { anchors.fill: parent; source: mr.lastShot; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 192 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { Quickshell.execDetached(["xdg-open", mr.lastShot.replace("file://", "")]); Panels.mirrorOpen = false; } }
                }

                // toast
                Rectangle {
                    visible: mr.toast !== ""
                    anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; margins: 16 }
                    implicitWidth: toastCol.implicitWidth + 20; implicitHeight: toastCol.implicitHeight + 10; radius: 6
                    color: Qt.rgba(0, 0, 0, 0.6)
                    Column {
                        id: toastCol
                        anchors.centerIn: parent
                        Mono { anchors.horizontalCenter: parent.horizontalCenter; text: "✓ " + mr.toast; color: "#ffffff"; font.weight: Font.Bold }
                        Mono { anchors.horizontalCenter: parent.horizontalCenter; text: mr.toastDetail; visible: text !== ""; color: "#c9d3e3"; font.pixelSize: 10 }
                    }
                }
            }

            // ---------------------------------------------------- controls
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.bottomMargin: 14
                spacing: 8
                Chip { objectName: "timerChip"; icon: "󱎫"; label: mr.timer ? mr.timer + "s" : "off"; on: mr.timer > 0; tint: Theme.yellow; onClicked: mr.cycleTimer() }
                Chip { icon: "󰕰"; label: "grid"; on: mr.grid; onClicked: mr.grid = !mr.grid }
                Chip { icon: "󰯌"; label: "flip"; on: mr.flip; onClicked: mr.flip = !mr.flip }
                Item { Layout.fillWidth: true }
                // shutter
                Rectangle {
                    objectName: "shutter"
                    implicitWidth: 54; implicitHeight: 54; radius: 27
                    color: "transparent"
                    border.width: 3
                    border.color: Theme.text
                    opacity: mr.ready ? 1 : 0.4
                    Rectangle {
                        anchors.centerIn: parent
                        width: shutArea.pressed ? 36 : 42; height: width; radius: width / 2
                        color: shutArea.containsMouse ? Theme.accent : Theme.text
                        Behavior on width { NumberAnimation { duration: 80 } }
                    }
                    MouseArea { id: shutArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mr.shoot() }
                }
                // record
                Rectangle {
                    objectName: "recBtn"
                    implicitWidth: 42; implicitHeight: 42; radius: 21
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.red
                    opacity: mr.ready ? 1 : 0.4
                    Rectangle {
                        anchors.centerIn: parent
                        width: mr.recording ? 16 : 26; height: width; radius: mr.recording ? 4 : width / 2
                        color: Theme.red
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mr.toggleRecord() }
                }
                Item { Layout.fillWidth: true }
                Chip { icon: mr.mic ? "󰍬" : "󰍭"; label: "mic"; on: mr.mic; dimmed: mr.recording; onClicked: mr.toggleMic() }
                Chip { icon: "󰉋"; label: "folder"; onClicked: { Quickshell.execDetached(["xdg-open", mr.home + "/Pictures/Webcam"]); Panels.mirrorOpen = false; } }
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
                        color: mr.recording ? Theme.red : mr.count > 0 ? Theme.yellow : mr.ready ? Theme.accent : Theme.dim
                        Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: parent.radius; color: parent.color }
                        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: parent.radius; color: parent.color }
                        Text {
                            id: modeText
                            anchors.centerIn: parent
                            text: mr.recording ? "REC" : mr.count > 0 ? "TIMER" : mr.ready ? "MIRROR" : "NO CAM"
                            font.family: Theme.mono; font.pixelSize: 11; font.weight: Font.Bold
                            color: Theme.onAccent
                        }
                    }
                    Mono { text: "~/Pictures/Webcam"; color: Theme.dim }
                    Item { Layout.fillWidth: true }
                    Mono {
                        text: "␣ photo · r rec · t timer · m mic · f flip · g grid · p bubble · tab cam · o folder"
                        font.pixelSize: 10
                        color: Theme.dim
                    }
                }
            }
        }
    }

    // ============================================================ bubble
    Item {
        id: bubbleBox
        objectName: "bubble"
        visible: mr.bubble
        property int size: Panels.bubbleSize
        width: size; height: size
        x: Panels.bubbleX >= 0 ? Math.min(Panels.bubbleX, mr.width - width) : mr.width - width - 28
        y: Panels.bubbleY >= 0 ? Math.min(Panels.bubbleY, mr.height - height) : mr.height - height - 28

        // ring
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: width / 2
            color: "transparent"
            border.width: 3
            border.color: mr.recording ? Theme.red : Theme.accent
        }
        ClippingRectangle {
            id: bubbleClip
            anchors.fill: parent
            radius: width / 2
            color: "#000000"
            Item { id: bubbleVideo; anchors.fill: parent }
        }
        // hover controls
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            spacing: 6
            visible: bubbleHover.hovered || mr.recording
            Repeater {
                model: [
                    { icon: "󰊓", act: "full" },
                    { icon: mr.recording ? "󰙦" : "󰑊", act: "rec" },
                    { icon: "󰅖", act: "close" }
                ]
                Rectangle {
                    required property var modelData
                    objectName: "bubble:" + modelData.act
                    width: 26; height: 26; radius: 13
                    color: Qt.rgba(0, 0, 0, 0.6)
                    visible: modelData.act === "rec" || bubbleHover.hovered
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.icon
                        font.family: Theme.iconFont; font.pixelSize: 13
                        color: parent.modelData.act === "rec" ? Theme.red : "#ffffff"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const a = parent.modelData.act;
                            if (a === "full") mr.setBubble(false);
                            else if (a === "rec") mr.toggleRecord();
                            else mr.back();
                        }
                    }
                }
            }
        }
        HoverHandler { id: bubbleHover }
        DragHandler {
            id: drag
            target: null
            property real sx: 0
            property real sy: 0
            onActiveChanged: if (active) { sx = bubbleBox.x; sy = bubbleBox.y; }
            onTranslationChanged: {
                if (!active) return;
                Panels.bubbleX = Math.max(0, Math.min(mr.width - bubbleBox.width, sx + translation.x));
                Panels.bubbleY = Math.max(0, Math.min(mr.height - bubbleBox.height, sy + translation.y));
            }
        }
        WheelHandler {
            onWheel: w => Panels.bubbleSize = Math.max(140, Math.min(380, Panels.bubbleSize + (w.angleDelta.y > 0 ? 20 : -20)))
        }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: mr.setBubble(false) }
        TapHandler { onDoubleTapped: mr.setBubble(false) }
    }
}
