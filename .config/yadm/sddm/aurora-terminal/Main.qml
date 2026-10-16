// Aurora Terminal: SDDM login screen that matches the hyprlock "terminal session" lock.
//   Type your password, Enter to log in.
//   F1 suspend · F2 change session · F3 reboot · F4 shut down · ↑/↓ change user

import QtQuick

Rectangle {
    id: root
    color: "#07090c"

    // ---- palette (same as the lock screen)
    readonly property color dim:    "#4d5562"
    readonly property color text:   "#c9d1d9"
    readonly property color bright: "#e6edf3"
    readonly property color sub:    "#8b949e"
    readonly property color accent: config.accent || "#6ee7c8"
    readonly property color red:    "#ff7a90"
    readonly property string mono:  config.font || "JetBrainsMono Nerd Font"

    // ---- scale everything from a 1080p design
    readonly property real s: height / 1080
    readonly property real margin: 144 * s

    // ---- users / sessions (models → plain arrays so we can index them)
    property var users: []
    property var sessions: []
    property int userIndex: userModel ? Math.max(0, userModel.lastIndex) : 0
    property int sessionIndex: sessionModel ? Math.max(0, sessionModel.lastIndex) : 0
    readonly property string userName: users.length ? users[userIndex] : userModel.lastUser
    readonly property string sessionName: sessions.length ? sessions[sessionIndex] : "Hyprland"

    Repeater {
        model: userModel
        delegate: Item {
            required property int index
            required property string name
            Component.onCompleted: { const u = root.users.slice(); u[index] = name; root.users = u; }
        }
    }
    Repeater {
        model: sessionModel
        delegate: Item {
            required property int index
            required property string name
            Component.onCompleted: { const a = root.sessions.slice(); a[index] = name; root.sessions = a; }
        }
    }

    // ---- state
    property string status: ""          // "" · "auth" · "fail"
    property int attempts: 0

    function login() {
        if (pw.text === "" || status === "auth") return;
        status = "auth";
        sddm.login(userName, pw.text, sessionIndex);
    }
    Connections {
        target: sddm
        function onLoginFailed() {
            root.attempts++;
            root.status = "fail";
            pw.text = "";
            pw.forceActiveFocus();
            shake.restart();
        }
        function onLoginSucceeded() { root.status = "auth" }
    }

    // ---- clock
    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }

    // ---- background: near-black with a faint teal glow
    Image {
        anchors.fill: parent
        source: config.background || "background.png"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }

    // ================================================================ text column
    Column {
        id: col
        x: root.margin
        y: 225 * root.s
        spacing: 0

        Text { font.family: root.mono; font.pixelSize: Math.round(18 * root.s); textFormat: Text.StyledText; text: "Arch Linux · " + sddm.hostName + " (tty1)"; color: root.dim }
        Item { width: 1; height: 14 * root.s }
        Text { font.family: root.mono; font.pixelSize: Math.round(18 * root.s); textFormat: Text.StyledText; text: "Session: " + root.sessionName + "  <font color='" + root.dim + "'>(F2 to change)</font>"; color: root.dim }

        Item { width: 1; height: 36 * root.s }
        Text {
            text: Qt.formatTime(root.now, "HH:mm")
            font.family: root.mono
            font.pixelSize: Math.round(92 * root.s)
            font.bold: true
            color: root.bright
            x: -6 * root.s
        }
        Text {
            font.family: root.mono
            font.pixelSize: Math.round(18 * root.s)
            textFormat: Text.StyledText
            text: Qt.formatDate(root.now, "dddd, d MMMM").toLowerCase() + " — welcome back"
            color: root.sub
        }

        Item { width: 1; height: 72 * root.s }
        Text {
            font.family: root.mono
            font.pixelSize: Math.round(18 * root.s)
            textFormat: Text.StyledText
            color: root.text
            text: "<font color='" + root.accent + "'>" + sddm.hostName + "</font> <font color='" + root.dim + "'>login:</font> " + root.userName
                  + (root.users.length > 1 ? "  <font color='" + root.dim + "'>(↑/↓)</font>" : "")
        }
        Item { width: 1; height: 14 * root.s }

        // password:  ••••••█
        Item {
            id: pwRow
            width: 700 * root.s
            height: 30 * root.s
            transform: Translate { id: shakeX; x: 0 }
            Text { font.family: root.mono; font.pixelSize: Math.round(18 * root.s); textFormat: Text.StyledText; id: pwLabel; text: "password:"; color: root.dim; anchors.verticalCenter: parent.verticalCenter }
            TextInput {
                id: pw
                anchors.left: pwLabel.right
                anchors.leftMargin: 14 * root.s
                anchors.verticalCenter: parent.verticalCenter
                width: 520 * root.s
                focus: true
                echoMode: TextInput.Password
                passwordCharacter: "•"
                font.family: root.mono
                font.pixelSize: Math.round(18 * root.s)
                font.letterSpacing: 4 * root.s
                color: root.text
                selectionColor: root.accent
                enabled: root.status !== "auth"
                onTextEdited: if (root.status === "fail") root.status = ""
                cursorDelegate: Rectangle {
                    width: 10 * root.s
                    height: 20 * root.s
                    color: root.accent
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: pw.activeFocus
                        NumberAnimation { to: 1; duration: 0 }
                        PauseAnimation { duration: 550 }
                        NumberAnimation { to: 0.15; duration: 0 }
                        PauseAnimation { duration: 450 }
                    }
                }
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.login();
                    else if (e.key === Qt.Key_Up && root.users.length > 1) root.userIndex = (root.userIndex + root.users.length - 1) % root.users.length;
                    else if (e.key === Qt.Key_Down && root.users.length > 1) root.userIndex = (root.userIndex + 1) % root.users.length;
                    else if (e.key === Qt.Key_F1 && sddm.canSuspend) sddm.suspend();
                    else if (e.key === Qt.Key_F2 && root.sessions.length) root.sessionIndex = (root.sessionIndex + 1) % root.sessions.length;
                    else if (e.key === Qt.Key_F3 && sddm.canReboot) sddm.reboot();
                    else if (e.key === Qt.Key_F4 && sddm.canPowerOff) sddm.powerOff();
                    else if (e.key === Qt.Key_Escape) { pw.text = ""; root.status = ""; }
                    else return;
                    e.accepted = true;
                }
                Component.onCompleted: forceActiveFocus()
            }
        }
        Item { width: 1; height: 12 * root.s }
        Text {
            font.family: root.mono
            font.pixelSize: Math.round(18 * root.s)
            textFormat: Text.StyledText
            text: root.status === "auth" ? "authenticating…"
                : root.status === "fail" ? "Login incorrect (" + root.attempts + ")" : " "
            color: root.status === "fail" ? root.red : root.sub
        }
    }

    SequentialAnimation {
        id: shake
        NumberAnimation { target: shakeX; property: "x"; to: 10 * root.s; duration: 50 }
        NumberAnimation { target: shakeX; property: "x"; to: -8 * root.s; duration: 60 }
        NumberAnimation { target: shakeX; property: "x"; to: 5 * root.s; duration: 60 }
        NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 60 }
    }

    // ================================================================ bottom-right: keys
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 144 * root.s
        anchors.bottomMargin: 80 * root.s
        spacing: 26 * root.s

        Repeater {
            model: [
                { k: "F1", label: "suspend",  ok: sddm.canSuspend,  run: () => sddm.suspend() },
                { k: "F2", label: "session",  ok: root.sessions.length > 1, run: () => root.sessionIndex = (root.sessionIndex + 1) % root.sessions.length },
                { k: "F3", label: "reboot",   ok: sddm.canReboot,   run: () => sddm.reboot() },
                { k: "F4", label: "shutdown", ok: sddm.canPowerOff, run: () => sddm.powerOff() }
            ]
            delegate: Text {
                required property var modelData
                visible: modelData.ok
                text: "<font color='" + (keyArea.containsMouse ? root.accent : root.dim) + "'>" + modelData.k + "</font> " + modelData.label
                textFormat: Text.StyledText
                font.family: root.mono
                font.pixelSize: Math.round(13 * root.s)
                color: keyArea.containsMouse ? root.bright : root.text
                MouseArea {
                    id: keyArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: parent.modelData.run()
                }
            }
        }
    }

    // clicking anywhere puts focus back in the password field
    MouseArea { anchors.fill: parent; z: -1; onClicked: pw.forceActiveFocus() }
}
