// Aurora Settings: a code-editor style overlay
//   open:  Super+,  ·  gear in the control centre  ·  Settings in the launcher
//   keys:  Esc / click outside → close · 1–0 → jump to a file · Tab / Shift+Tab → next / previous
//          j / k → scroll · Enter in a field → save it
// Everything saves instantly to ~/.config/aurora/settings.json and applies live.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: win

    property bool shown: false
    visible: shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var o: Settings.o
    property int page: 0
    property bool justSaved: false
    readonly property var pages: [
        { icon: "", file: "appearance.toml", c: Theme.pink },
        { icon: "", file: "bar.toml",        c: Theme.sky },
        { icon: "", file: "windows.toml",    c: Theme.violet },
        { icon: "", file: "input.toml",      c: Theme.yellow },
        { icon: "", file: "display.toml",    c: Theme.teal },
        { icon: "", file: "power.toml",      c: Theme.yellow },
        { icon: "", file: "location.toml",   c: Theme.red },
        { icon: "", file: "apps.toml",       c: Theme.sky },
        { icon: "", file: "keybinds.md",     c: Theme.violet },
        { icon: "", file: "about.md",        c: Theme.muted }
    ]
    onPageChanged: flick.contentY = 0

    function close() { card.forceActiveFocus(); Settings.windowOpen = false }

    // ------------------------------------------------------------ open / close
    Connections {
        target: Settings
        function onWindowOpenChanged() {
            if (Settings.windowOpen) {
                hide.stop();
                win.shown = true;
                card.forceActiveFocus();
                appear.restart();
            } else {
                Settings.editing = false;
                appear.stop();
                hide.restart();
            }
        }
        function onWritesChanged() { win.justSaved = true; savedTimer.restart() }
    }
    Connections {                       // another panel opening closes this one
        target: Panels
        function onAnyOpenChanged() { if (Panels.anyOpen) Settings.windowOpen = false }
    }
    Timer { id: savedTimer; interval: 1400; onTriggered: win.justSaved = false }

    ParallelAnimation {
        id: appear
        NumberAnimation { target: backdrop; property: "opacity"; to: 0.45; duration: 180; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "scale"; from: 0.97; to: 1; duration: 220; easing.type: Easing.OutQuint }
    }
    ParallelAnimation {
        id: hide
        onFinished: win.shown = false
        NumberAnimation { target: backdrop; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InQuad }
        NumberAnimation { target: card; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InQuad }
        NumberAnimation { target: card; property: "scale"; to: 0.98; duration: 120; easing.type: Easing.InQuad }
    }

    // click anywhere outside the card → close
    Rectangle { id: backdrop; anchors.fill: parent; color: "black"; opacity: 0 }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: win.close()
    }

    // controls live in Set*.qml next to this file

    // time choices for idle timeouts (seconds)
    readonly property var idleChoices: [
        { v: 0, t: "never" }, { v: 60, t: "1m" }, { v: 150, t: "2.5m" }, { v: 300, t: "5m" },
        { v: 600, t: "10m" }, { v: 900, t: "15m" }, { v: 1800, t: "30m" }
    ]

    // ============================================================ the card
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(1120, win.width - 80)
        height: Math.min(740, win.height - 80)
        opacity: 0
        radius: Theme.radius
        color: Theme.bg
        border.width: 1
        border.color: Theme.alpha(Theme.accent, 0.28)
        focus: true

        // swallow clicks inside the card (and drop focus from text fields)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: card.forceActiveFocus() }

        Keys.onPressed: e => {
            const k = e.key;
            if (k === Qt.Key_Escape) {
                if (Settings.editing) card.forceActiveFocus();   // first Esc leaves the text field
                else win.close();
            } else if (k === Qt.Key_Tab) win.page = (win.page + 1) % win.pages.length;
            else if (k === Qt.Key_Backtab) win.page = (win.page + win.pages.length - 1) % win.pages.length;
            else if (k >= Qt.Key_1 && k <= Qt.Key_9) win.page = k - Qt.Key_1;
            else if (k === Qt.Key_0) win.page = 9;
            else if (k === Qt.Key_J || k === Qt.Key_Down) flick.scrollBy(70);
            else if (k === Qt.Key_K || k === Qt.Key_Up) flick.scrollBy(-70);
            else if (k === Qt.Key_G) flick.contentY = (e.modifiers & Qt.ShiftModifier) ? flick.maxY : 0;
            else return;
            e.accepted = true;
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            // ---------------------------------------------------- title bar + tab
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
                    anchors.rightMargin: 8
                    spacing: 0

                    Text {
                        text: "  aurora"
                        font.family: Theme.mono
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: Theme.accent
                        Layout.preferredWidth: 205
                    }
                    // the open tab
                    Rectangle {
                        Layout.fillHeight: true
                        Layout.topMargin: 6
                        implicitWidth: tabRow.implicitWidth + 32
                        radius: 6
                        color: Theme.bg
                        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 8; color: parent.color }
                        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 2; radius: 1; color: win.pages[win.page].c }
                        Row {
                            id: tabRow
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 1
                            spacing: 8
                            Text { text: win.pages[win.page].icon; font.family: Theme.mono; font.pixelSize: 12; color: win.pages[win.page].c }
                            Text { text: win.pages[win.page].file; font.family: Theme.mono; font.pixelSize: 12; color: Theme.text }
                            Text { text: win.justSaved ? "●" : "×"; font.family: Theme.mono; font.pixelSize: 12; color: win.justSaved ? Theme.yellow : Theme.dim }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "~/.config/aurora/settings.json"
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: Theme.dim
                        Layout.rightMargin: 12
                    }
                    Rectangle {
                        implicitWidth: 30; implicitHeight: 26
                        radius: 6
                        color: xArea.containsMouse ? Theme.alpha(Theme.red, 0.2) : "transparent"
                        Text { anchors.centerIn: parent; text: "✕"; font.family: Theme.mono; font.pixelSize: 13; color: xArea.containsMouse ? Theme.red : Theme.muted }
                        MouseArea { id: xArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.close() }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // ------------------------------------------------ explorer
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 220
                    color: Theme.alpha(Theme.surface, 0.55)
                    Rectangle { anchors { top: parent.top; bottom: parent.bottom; right: parent.right } width: 1; color: Theme.border }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        anchors.topMargin: 14
                        spacing: 1

                        Text {
                            text: "EXPLORER"
                            font.family: Theme.mono
                            font.pixelSize: 10
                            font.letterSpacing: 1.6
                            color: Theme.dim
                            Layout.leftMargin: 8
                            Layout.bottomMargin: 8
                        }
                        Text {
                            text: "▾   aurora"
                            font.family: Theme.mono
                            font.pixelSize: 12
                            color: Theme.subtext
                            Layout.leftMargin: 8
                            Layout.bottomMargin: 4
                        }

                        Repeater {
                            model: win.pages
                            Rectangle {
                                id: navItem
                                required property var modelData
                                required property int index
                                readonly property bool on: win.page === index
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: 5
                                color: on ? Theme.alpha(Theme.accent, 0.13) : (navArea.containsMouse ? Theme.hover : "transparent")
                                Behavior on color { ColorAnimation { duration: 110 } }
                                Rectangle { visible: navItem.on; width: 2; height: parent.height - 8; radius: 1; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
                                Rectangle { x: 14; width: 1; height: parent.height; color: Theme.border }   // tree guide
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 24
                                    anchors.rightMargin: 8
                                    spacing: 8
                                    Text {
                                        text: navItem.modelData.icon
                                        font.family: Theme.mono
                                        font.pixelSize: 12
                                        color: navItem.modelData.c
                                        Layout.preferredWidth: 14
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    Text {
                                        text: navItem.modelData.file
                                        font.family: Theme.mono
                                        font.pixelSize: 12
                                        color: navItem.on ? Theme.text : Theme.muted
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: String((navItem.index + 1) % 10)
                                        font.family: Theme.mono
                                        font.pixelSize: 10
                                        color: navItem.on ? Theme.accent : Theme.dim
                                        opacity: navItem.on || navArea.containsMouse ? 1 : 0.6
                                    }
                                }
                                MouseArea { id: navArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.page = navItem.index }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        Text {
                            text: "▸   .config/hypr\n    aurora-settings.lua\n    hypridle.conf"
                            font.family: Theme.mono
                            font.pixelSize: 10
                            lineHeight: 1.3
                            color: Theme.dim
                            Layout.leftMargin: 8
                            Layout.bottomMargin: 4
                        }
                        Text {
                            text: "generated → applied live"
                            font.family: Theme.mono
                            font.pixelSize: 10
                            color: Theme.alpha(Theme.dim, 0.7)
                            Layout.leftMargin: 8
                        }
                    }
                }

                // ------------------------------------------------ editor
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // breadcrumb
                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 24
                        Layout.topMargin: 12
                        Layout.bottomMargin: 2
                        text: "aurora › " + win.pages[win.page].file
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: Theme.dim
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Flickable {
                            id: flick
                            anchors.fill: parent
                            anchors.rightMargin: 8
                            contentWidth: width
                            contentHeight: pageLoader.implicitHeight + 40
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            readonly property real maxY: Math.max(0, contentHeight - height)
                            function scrollBy(d) { contentY = Math.max(0, Math.min(maxY, contentY + d)) }
                            Behavior on contentY { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Loader {
                                id: pageLoader
                                x: 10
                                y: 4
                                width: flick.width - 24
                                sourceComponent: [appearance, bar, windows, input, display, power, location, apps, keybinds, about][win.page]
                            }
                        }
                        // scroll position (like an editor's minimap edge)
                        Rectangle {
                            visible: flick.contentHeight > flick.height
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            width: 3
                            radius: 2
                            color: Theme.alpha(Theme.accent, 0.45)
                            height: Math.max(24, flick.height * flick.height / flick.contentHeight)
                            y: flick.maxY > 0 ? (flick.height - height) * flick.contentY / flick.maxY : 0
                        }
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
                    anchors.rightMargin: 14
                    spacing: 14

                    Rectangle {                                     // mode
                        Layout.fillHeight: true
                        implicitWidth: modeText.implicitWidth + 22
                        color: Settings.editing ? Theme.yellow : Theme.accent
                        radius: Math.max(0, card.radius - 1)
                        Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: parent.radius; color: parent.color }
                        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: parent.radius; color: parent.color }
                        Text {
                            id: modeText
                            anchors.centerIn: parent
                            text: Settings.editing ? "INSERT" : "NORMAL"
                            font.family: Theme.mono
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: Theme.onAccent
                        }
                    }
                    Text {
                        text: " aurora/" + win.pages[win.page].file
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: Theme.subtext
                    }
                    Text {
                        text: "✓ written"
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: Theme.teal
                        opacity: win.justSaved ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "1-0 file  ·  tab next  ·  j/k scroll  ·  esc close"
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: Theme.dim
                    }
                    Text {
                        text: (win.page + 1) + "/" + win.pages.length
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: Theme.muted
                    }
                }
            }
        }
    }

    // ============================================================ pages
    Component {
        id: appearance
        ColumnLayout {
            spacing: 2
            SetComment { text: "// colours, fonts and shape of the shell" }
            SetGroup {
                title: "colours"
                SetChoice {
                    key: "colorSource"; label: "colour source"
                    desc: "follow the wallpaper, or keep the original aurora teal/violet"
                    options: [{ v: "wallpaper", t: "wallpaper" }, { v: "static", t: "aurora" }]
                    current: win.o.colorSource
                    onChosen: v => win.o.colorSource = v
                }
                SetChoice {
                    key: "scheme"; label: "wallpaper colour style"
                    desc: "how colours are pulled from the wallpaper"
                    options: [{ v: "scheme-vibrant", t: "vibrant" }, { v: "scheme-content", t: "faithful" },
                              { v: "scheme-tonal-spot", t: "calm" }, { v: "scheme-expressive", t: "playful" }, { v: "scheme-monochrome", t: "mono" }]
                    current: win.o.scheme
                    onChosen: v => win.o.scheme = v
                }
                SetAction { key: "wallpaper.pick()"; label: "choose from ~/wallpapers (Super+W)"; button: "choose"; onClicked: { Settings.windowOpen = false; Panels.toggleWalls(); } }
                SetAction { key: "wallpaper.random()"; label: "random wallpaper (Super+Shift+W)"; button: "shuffle"; onClicked: Quickshell.execDetached([Settings.home + "/.local/bin/aurora-wall", "--random"]) }
            }
            SetGroup {
                title: "text"
                SetField { key: "uiFont"; label: "interface font"; text: win.o.uiFont; placeholder: "Inter"; onEdited: v => win.o.uiFont = v }
                SetField { key: "monoFont"; label: "monospace font"; desc: "bar, numbers, this window (needs nerd font icons)"; text: win.o.monoFont; placeholder: "JetBrainsMono Nerd Font"; onEdited: v => win.o.monoFont = v }
                SetSlide { key: "fontScale"; label: "text size"; value: win.o.fontScale; from: 0.8; to: 1.4; step: 0.05; decimals: 2; suffix: "x"; onMoved: v => win.o.fontScale = v }
            }
            SetGroup {
                title: "shape"
                SetSlide { key: "barHeight"; label: "bar height"; value: win.o.barHeight; from: 32; to: 60; step: 1; suffix: "px"; onMoved: v => win.o.barHeight = v }
                SetSlide { key: "barOpacity"; label: "bar opacity"; desc: "1 = solid"; value: win.o.barOpacity; from: 0.3; to: 1; step: 0.02; decimals: 2; onMoved: v => win.o.barOpacity = v }
                SetSlide { key: "radius"; label: "panel corner radius"; value: win.o.radius; from: 0; to: 24; step: 1; suffix: "px"; onMoved: v => win.o.radius = v }
            }
        }
    }

    Component {
        id: bar
        ColumnLayout {
            spacing: 2
            SetComment { text: "// what the status line at the top shows" }
            SetGroup {
                title: "workspaces"
                SetSlide { key: "workspaces"; label: "always shown, even when empty"; value: win.o.workspaces; from: 1; to: 10; step: 1; onMoved: v => win.o.workspaces = v }
                SetToggle { key: "barTitle"; label: "focused window title"; checked: win.o.barTitle; onToggled: v => win.o.barTitle = v }
            }
            SetGroup {
                title: "modules"
                SetToggle { key: "barMedia"; label: "now playing"; checked: win.o.barMedia; onToggled: v => win.o.barMedia = v }
                SetToggle { key: "visualizer"; label: "live audio spectrum"; desc: "needs cava · only runs while something plays"; checked: win.o.visualizer; onToggled: v => win.o.visualizer = v }
                SetChoice {
                    key: "vizStyle"; label: "spectrum style"
                    options: [{ v: "bars", t: "bars" }, { v: "wave", t: "wave" }]
                    current: win.o.vizStyle
                    onChosen: v => win.o.vizStyle = v
                }
            }
            SetGroup {
                title: "focus"
                SetToggle { key: "barFocus"; label: "focus timer in the bar"; desc: "Super+T start/pause · Super+Shift+T details"; checked: win.o.barFocus; onToggled: v => win.o.barFocus = v }
                SetSlide { key: "focusGoal"; label: "daily goal"; value: win.o.focusGoal; from: 1; to: 12; step: 0.5; decimals: 1; suffix: "h"; onMoved: v => win.o.focusGoal = v }
                SetSlide { key: "focusIdle"; label: "away after"; desc: "no keyboard/mouse this long: that time is taken off and counting waits for you"; value: win.o.focusIdle; from: 1; to: 20; step: 1; suffix: "m"; onMoved: v => win.o.focusIdle = v }
                SetField { key: "focusTags"; label: "what you track (comma-separated)"; desc: "keys 1–9 in the panel"; text: win.o.focusTags; placeholder: "code,study,read,other"; onEdited: v => { const t = v.split(",").map(s => s.trim()).filter(s => s); if (t.length) win.o.focusTags = t.join(","); } }
                SetField { key: "focusDistract"; label: "distractions"; desc: "site names (in a browser title) or app names"; text: win.o.focusDistract; placeholder: "YouTube,Reddit,Discord"; onEdited: v => win.o.focusDistract = v.split(",").map(s => s.trim()).filter(s => s).join(",") }
                SetToggle { key: "focusAuto"; label: "start by itself"; desc: "after 2 minutes in an editor or a project terminal (not for 30 min after you pause)"; checked: win.o.focusAuto; onToggled: v => win.o.focusAuto = v }
                SetToggle { key: "focusGoalNotify"; label: "tell me when the goal is reached"; desc: "one quiet notification"; checked: win.o.focusGoalNotify; onToggled: v => win.o.focusGoalNotify = v }
                SetSlide { key: "focusBreak"; label: "break reminder"; desc: "0 = never"; value: win.o.focusBreak; from: 0; to: 120; step: 5; suffix: "m"; onMoved: v => win.o.focusBreak = v }
            }
            SetGroup {
                title: "audio"
                SetChoice {
                    key: "audioHotplug"; label: "when HDMI audio appears"
                    desc: "ask: open the audio picker with it selected · switch: use it straight away"
                    options: [{ v: "ask", t: "ask" }, { v: "switch", t: "switch" }, { v: "off", t: "off" }]
                    current: win.o.audioHotplug
                    onChosen: v => win.o.audioHotplug = v
                }
                SetToggle { key: "barStats"; label: "cpu · mem · temp"; checked: win.o.barStats; onToggled: v => win.o.barStats = v }
                SetToggle { key: "barNet"; label: "network speed ↓ ↑"; checked: win.o.barNet; onToggled: v => win.o.barNet = v }
                SetToggle { key: "barDev"; label: "dev pill: git branch · docker · ports"; checked: win.o.barDev; onToggled: v => win.o.barDev = v }
                SetToggle { key: "barBattery"; label: "battery"; checked: win.o.barBattery; onToggled: v => win.o.barBattery = v }
                SetChoice {
                    key: "barGpu"; label: "nvidia gpu pill"
                    desc: "auto: only while the GPU is awake (using battery) · click it to see what woke it"
                    options: [{ v: "auto", t: "auto" }, { v: "always", t: "always" }, { v: "off", t: "off" }]
                    current: win.o.barGpu
                    onChosen: v => win.o.barGpu = v
                }
            }
            SetGroup {
                title: "notifications"
                SetToggle { key: "dndSchedule"; label: "do not disturb on a schedule"; desc: "pop-ups pause between the times below (history is kept)"; checked: win.o.dndSchedule; onToggled: v => win.o.dndSchedule = v }
                SetField { key: "dndFrom"; label: "quiet from (HH:MM)"; text: win.o.dndFrom; placeholder: "22:00"; fieldWidth: 120; onEdited: v => { if (/^\d{1,2}:\d{2}$/.test(v.trim())) win.o.dndFrom = v.trim(); } }
                SetField { key: "dndTo"; label: "quiet until (HH:MM)"; text: win.o.dndTo; placeholder: "07:00"; fieldWidth: 120; onEdited: v => { if (/^\d{1,2}:\d{2}$/.test(v.trim())) win.o.dndTo = v.trim(); } }
            }
            SetGroup {
                title: "clock"
                SetToggle { key: "clock24h"; label: "24-hour time"; checked: win.o.clock24h; onToggled: v => win.o.clock24h = v }
                SetToggle { key: "clockSeconds"; label: "show seconds"; checked: win.o.clockSeconds; onToggled: v => win.o.clockSeconds = v }
            }
        }
    }

    Component {
        id: windows
        ColumnLayout {
            spacing: 2
            SetComment { text: "// hyprland: written to ~/.config/hypr/aurora-settings.lua, reloads by itself" }
            SetGroup {
                title: "layout"
                SetChoice {
                    key: "layout"; label: "tiling layout"
                    desc: "dwindle = spiral · master = one big window · scrolling = side-by-side strip"
                    options: [{ v: "dwindle", t: "dwindle" }, { v: "master", t: "master" }, { v: "scrolling", t: "scrolling" }]
                    current: win.o.layout
                    onChosen: v => win.o.layout = v
                }
                SetSlide { key: "gapsIn"; label: "gaps between windows"; value: win.o.gapsIn; from: 0; to: 20; step: 1; suffix: "px"; onMoved: v => win.o.gapsIn = v }
                SetSlide { key: "gapsOut"; label: "gaps to screen edge"; value: win.o.gapsOut; from: 0; to: 30; step: 1; suffix: "px"; onMoved: v => win.o.gapsOut = v }
            }
            SetGroup {
                title: "look"
                SetSlide { key: "borderSize"; label: "border width"; value: win.o.borderSize; from: 0; to: 6; step: 1; suffix: "px"; onMoved: v => win.o.borderSize = v }
                SetSlide { key: "rounding"; label: "corner rounding"; value: win.o.rounding; from: 0; to: 20; step: 1; suffix: "px"; onMoved: v => win.o.rounding = v }
                SetSlide { key: "inactiveOpacity"; label: "unfocused window opacity"; value: win.o.inactiveOpacity; from: 0.6; to: 1; step: 0.01; decimals: 2; onMoved: v => win.o.inactiveOpacity = v }
                SetToggle { key: "dimInactive"; label: "dim unfocused windows"; checked: win.o.dimInactive; onToggled: v => win.o.dimInactive = v }
                SetToggle { key: "shadow"; label: "shadows"; checked: win.o.shadow; onToggled: v => win.o.shadow = v }
            }
            SetGroup {
                title: "blur"
                SetToggle { key: "blur"; label: "blur behind transparent windows"; desc: "off saves battery"; checked: win.o.blur; onToggled: v => win.o.blur = v }
                SetSlide { key: "blurSize"; label: "blur size"; value: win.o.blurSize; from: 1; to: 12; step: 1; onMoved: v => win.o.blurSize = v }
                SetSlide { key: "blurPasses"; label: "blur passes"; desc: "more = smoother, heavier"; value: win.o.blurPasses; from: 1; to: 4; step: 1; onMoved: v => win.o.blurPasses = v }
            }
            SetGroup {
                title: "animations"
                SetToggle { key: "animations"; label: "animations"; checked: win.o.animations; onToggled: v => win.o.animations = v }
                SetSlide { key: "animSpeed"; label: "animation length"; desc: "0.5 = twice as fast · 2 = twice as slow"; value: win.o.animSpeed; from: 0.3; to: 2; step: 0.05; decimals: 2; suffix: "x"; onMoved: v => win.o.animSpeed = v }
            }
        }
    }

    Component {
        id: input
        ColumnLayout {
            spacing: 2
            SetComment { text: "// keyboard, mouse and touchpad" }
            SetGroup {
                title: "keyboard"
                SetField { key: "kbLayout"; label: "layouts, comma-separated"; desc: "e.g. us,np"; text: win.o.kbLayout; placeholder: "us"; onEdited: v => win.o.kbLayout = v.replace(/\s/g, "") }
                SetField { key: "kbOptions"; label: "xkb options"; desc: "e.g. grp:alt_shift_toggle,caps:escape"; text: win.o.kbOptions; placeholder: "grp:alt_shift_toggle"; onEdited: v => win.o.kbOptions = v.replace(/\s/g, "") }
                SetSlide { key: "repeatRate"; label: "repeat rate"; desc: "characters per second while holding a key"; value: win.o.repeatRate; from: 10; to: 60; step: 1; suffix: "/s"; onMoved: v => win.o.repeatRate = v }
                SetSlide { key: "repeatDelay"; label: "repeat delay"; value: win.o.repeatDelay; from: 150; to: 1000; step: 25; suffix: "ms"; onMoved: v => win.o.repeatDelay = v }
            }
            SetGroup {
                title: "pointer"
                SetSlide { key: "sensitivity"; label: "pointer speed"; value: win.o.sensitivity; from: -1; to: 1; step: 0.05; decimals: 2; onMoved: v => win.o.sensitivity = v }
                SetToggle { key: "flatAccel"; label: "flat acceleration"; desc: "same speed however fast you move"; checked: win.o.flatAccel; onToggled: v => win.o.flatAccel = v }
            }
            SetGroup {
                title: "touchpad"
                SetToggle { key: "naturalScroll"; label: "natural scrolling"; checked: win.o.naturalScroll; onToggled: v => win.o.naturalScroll = v }
                SetToggle { key: "tapToClick"; label: "tap to click"; checked: win.o.tapToClick; onToggled: v => win.o.tapToClick = v }
                SetToggle { key: "disableWhileTyping"; label: "ignore touchpad while typing"; checked: win.o.disableWhileTyping; onToggled: v => win.o.disableWhileTyping = v }
                SetSlide { key: "scrollFactor"; label: "scroll speed"; value: win.o.scrollFactor; from: 0.2; to: 2; step: 0.05; decimals: 2; suffix: "x"; onMoved: v => win.o.scrollFactor = v }
                SetToggle { key: "swipe"; label: "3-finger swipe between workspaces"; checked: win.o.swipe; onToggled: v => win.o.swipe = v }
                SetToggle { key: "clickFinger"; label: "two-finger click = right click"; desc: "press anywhere with two fingers, like Windows · off: bottom-right corner"; checked: win.o.clickFinger; onToggled: v => win.o.clickFinger = v }
                SetAction {
                    key: "touchpad.windowsLike()"
                    label: "windows-like preset"
                    desc: "speed 0.25 · adaptive accel · scroll 0.45x · natural scroll · tap · two-finger right click"
                    button: "apply"
                    onClicked: {
                        win.o.sensitivity = 0.25; win.o.flatAccel = false;
                        win.o.naturalScroll = true; win.o.tapToClick = true; win.o.disableWhileTyping = true;
                        win.o.scrollFactor = 0.45; win.o.clickFinger = true;
                    }
                }
            }
        }
    }

    Component {
        id: display
        ColumnLayout {
            spacing: 2
            SetComment { text: "// laptop screen (eDP-1) and night light" }
            SetGroup {
                title: "monitor"
                SetChoice {
                    key: "refreshRate"; label: "refresh rate"; desc: "60 Hz saves battery"
                    options: [{ v: 60, t: "60hz" }, { v: 144, t: "144hz" }]
                    current: win.o.refreshRate
                    onChosen: v => win.o.refreshRate = v
                }
                SetChoice {
                    key: "scale"; label: "scale"; desc: "make everything bigger"
                    options: [{ v: 1, t: "1.0" }, { v: 1.25, t: "1.25" }, { v: 1.5, t: "1.5" }]
                    current: win.o.scale
                    onChosen: v => win.o.scale = v
                }
                SetChoice {
                    key: "vrr"; label: "variable refresh rate"
                    options: [{ v: 0, t: "off" }, { v: 1, t: "on" }, { v: 2, t: "fullscreen" }]
                    current: win.o.vrr
                    onChosen: v => win.o.vrr = v
                }
            }
            SetGroup {
                title: "night_light"
                SetChoice {
                    key: "night.mode"; label: NightLight.summary.toLowerCase()
                    options: [{ v: "off", t: "off" }, { v: "on", t: "on" }, { v: "auto", t: "sunset→sunrise" }]
                    current: NightLight.mode
                    onChosen: v => NightLight.setMode(v)
                }
                SetSlide { key: "night.temp"; label: "warmth"; desc: "lower = warmer"; value: NightLight.temp; from: 2500; to: 6000; step: 50; suffix: "K"; onMoved: v => NightLight.temp = v }
            }
        }
    }

    Component {
        id: power
        ColumnLayout {
            spacing: 2
            SetComment { text: "// hypridle: regenerated ~/.config/hypr/hypridle.conf · a playing video pauses all of this" }
            SetGroup {
                title: "idle"
                SetChoice { key: "dimAfter"; label: "dim the screen after"; options: win.idleChoices; current: win.o.dimAfter; onChosen: v => win.o.dimAfter = v }
                SetChoice { key: "lockAfter"; label: "lock after"; options: win.idleChoices; current: win.o.lockAfter; onChosen: v => win.o.lockAfter = v }
                SetChoice { key: "screenOffAfter"; label: "screen off after"; options: win.idleChoices; current: win.o.screenOffAfter; onChosen: v => win.o.screenOffAfter = v }
                SetChoice { key: "suspendAfter"; label: "sleep after"; options: win.idleChoices; current: win.o.suspendAfter; onChosen: v => win.o.suspendAfter = v }
                SetToggle { key: "suspendOnAC"; label: "also sleep when plugged in"; desc: "false = battery only"; checked: win.o.suspendOnAC; onToggled: v => win.o.suspendOnAC = v }
            }
            SetGroup {
                title: "profile"
                SetChoice {
                    key: "power.profile"; label: Power.hasProfiles ? "power-profiles-daemon · right-click the bar's power button to cycle" : "power-profiles-daemon isn't running"
                    options: [{ v: "power-saver", t: "power-saver" }, { v: "balanced", t: "balanced" }, { v: "performance", t: "performance" }]
                    current: Power.profile
                    onChosen: v => Power.setProfile(v)
                }
            }
            SetGroup {
                title: "now"
                SetAction { key: "power.menu()"; label: "lock · suspend · logout · reboot · gpu mode (Super+Esc)"; button: "open"; onClicked: { Settings.windowOpen = false; Panels.togglePower(); } }
                SetAction { key: "session.lock()"; button: "lock"; onClicked: { win.close(); Quickshell.execDetached(["loginctl", "lock-session"]) } }
                SetAction { key: "system.suspend()"; button: "sleep"; onClicked: { win.close(); Quickshell.execDetached(["systemctl", "suspend"]) } }
            }
        }
    }

    Component {
        id: location
        ColumnLayout {
            spacing: 2
            SetComment { text: "// used by the dashboard weather and night light sunset / sunrise" }
            SetGroup {
                title: "quick_pick"
                SetChoice {
                    key: "place"
                    options: [{ v: "Kathmandu", t: "kathmandu" }, { v: "Pokhara", t: "pokhara" }, { v: "Lalitpur", t: "lalitpur" }, { v: "Bharatpur", t: "bharatpur" }]
                    current: win.o.place
                    onChosen: v => {
                        const c = { Kathmandu: [27.7172, 85.3240], Pokhara: [28.2096, 83.9856], Lalitpur: [27.6644, 85.3188], Bharatpur: [27.6833, 84.4333] }[v];
                        win.o.place = v; win.o.latitude = c[0]; win.o.longitude = c[1];
                    }
                }
            }
            SetGroup {
                title: "custom"
                SetField { key: "place"; label: "name shown on the dashboard"; text: win.o.place; onEdited: v => win.o.place = v }
                SetField { key: "latitude"; text: String(win.o.latitude); fieldWidth: 160; onEdited: v => { const n = parseFloat(v); if (!isNaN(n)) win.o.latitude = n; } }
                SetField { key: "longitude"; text: String(win.o.longitude); fieldWidth: 160; onEdited: v => { const n = parseFloat(v); if (!isNaN(n)) win.o.longitude = n; } }
            }
        }
    }

    Component {
        id: apps
        ColumnLayout {
            spacing: 2
            SetComment { text: "// used by keybinds, the dev panel and launcher projects" }
            SetGroup {
                title: "defaults"
                SetField { key: "terminal"; label: "Super+Return"; text: win.o.terminal; placeholder: "kitty"; onEdited: v => win.o.terminal = v }
                SetField { key: "browser"; label: "Super+B"; text: win.o.browser; placeholder: "brave"; onEdited: v => win.o.browser = v }
                SetField { key: "editor"; label: "projects open in this"; desc: "code, codium, zed, nvim…"; text: win.o.editor; placeholder: "code"; onEdited: v => win.o.editor = v }
                SetField { key: "files"; label: "Super+E"; text: win.o.files; placeholder: "nautilus"; onEdited: v => win.o.files = v }
            }
        }
    }

    Component {
        id: keybinds
        ColumnLayout {
            spacing: 2
            SetComment { text: "// read-only cheat sheet · edit binds in ~/.config/hypr/hyprland.lua" }
            Repeater {
                model: [
                    { g: "launch", k: [["Super", "launcher"], ["Super+Return", "terminal"], ["Super+B", "browser"], ["Super+E", "files"], ["Super+,", "settings"]] },
                    { g: "launcher_modes", k: [["Super+V", "clipboard (preview · pins)"], ["Super+O", "git projects"], ["Super+.", "emoji & symbols"], ["Super+/", "web / docs search"]] },
                    { g: "panels", k: [["Super+A", "control centre"], ["Super+D", "dashboard"], ["Super+Shift+D", "dev panel"], ["Super+Tab", "overview"], ["Alt+Tab", "window switcher"], ["Super+W", "wallpapers"], ["Print", "capture menu"]] },
                    { g: "windows", k: [["Super+Q", "close"], ["Super+F", "fullscreen"], ["Super+M", "maximise"], ["Super+Shift+F", "float"], ["Super+J", "toggle split"], ["Super+arrows", "focus"], ["Super+Shift+arrows", "move"], ["Super+Ctrl+arrows", "resize"], ["Super+drag", "move / resize"]] },
                    { g: "workspaces", k: [["Super+1…9", "go to"], ["Super+Shift+1…9", "send window"], ["3-finger swipe", "next / previous"], ["Super+S", "scratchpad"]] },
                    { g: "system", k: [["Super+L", "lock"], ["Super+N", "night light"], ["Super+Shift+N", "night light auto"], ["Shift+Print", "region screenshot"], ["Super+Shift+R", "record"], ["Super+I", "wifi radar"], ["Super+Shift+I", "bluetooth radar"], ["Super+`", "notification centre"], ["Super+T", "focus timer start/pause"], ["Super+Shift+T", "focus details"], ["Super+Shift+M", "media"], ["Super+Shift+A", "audio output"], ["Super+Shift+C", "webcam mirror"], ["Super+Ctrl+C", "webcam bubble"], ["Super+Esc", "power menu"], ["Super+Shift+E", "power menu"]] }
                ]
                SetGroup {
                    id: kbGroup
                    required property var modelData
                    title: modelData.g
                    Repeater {
                        model: kbGroup.modelData.k
                        Rectangle {
                            id: kbRow
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 28
                            radius: 5
                            color: kbHov.hovered ? Theme.alpha(Theme.text, 0.045) : "transparent"
                            HoverHandler { id: kbHov }
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                x: 14
                                spacing: 4
                                Repeater {
                                    model: String(kbRow.modelData[0]).split("+")
                                    Rectangle {
                                        required property string modelData
                                        width: kt.implicitWidth + 12; height: 20; radius: 4
                                        color: Theme.alpha(Theme.bg, 0.7)
                                        border.width: 1
                                        border.color: Theme.cardHi
                                        Text { id: kt; anchors.centerIn: parent; text: parent.modelData.toLowerCase(); font.family: Theme.mono; font.pixelSize: 11; color: Theme.accent }
                                    }
                                }
                            }
                            Text {
                                x: 200
                                anchors.verticalCenter: parent.verticalCenter
                                text: "→ " + kbRow.modelData[1]
                                font.family: Theme.mono
                                font.pixelSize: 12
                                color: Theme.subtext
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: about
        ColumnLayout {
            spacing: 2
            SetComment { text: "// $ aurora --version" }
            SetGroup {
                title: "system"
                Repeater {
                    model: versions.lines
                    RowLayout {
                        id: verLine
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 14
                        Layout.topMargin: 5
                        Layout.bottomMargin: 5
                        Text { text: verLine.modelData.split(/\s+/)[0]; font.family: Theme.mono; font.pixelSize: 13; color: Theme.sky; Layout.preferredWidth: 140 }
                        Text { text: "= " + verLine.modelData.replace(/^\S+\s+/, ""); font.family: Theme.mono; font.pixelSize: 12; color: Theme.yellow; Layout.fillWidth: true }
                    }
                }
            }
            SetGroup {
                title: "files"
                SetAction { key: "settings.json"; label: "every option on these pages, as one file"; button: "edit"; onClicked: { win.close(); Quickshell.execDetached([win.o.editor || "code", Settings.home + "/.config/aurora/settings.json"]) } }
                SetAction { key: "~/.config"; label: "config folder"; button: "open"; onClicked: { win.close(); Quickshell.execDetached([win.o.files || "nautilus", Settings.home + "/.config"]) } }
            }
            SetGroup {
                title: "reload"
                SetAction { key: "quickshell.reload()"; label: "bar, panels, launcher"; button: "reload"; onClicked: Quickshell.reload(true) }
                SetAction { key: "hyprctl.reload()"; label: "hyprland config"; button: "reload"; onClicked: Quickshell.execDetached(["hyprctl", "reload"]) }
            }
        }
    }

    Process {
        id: versions
        property var lines: []
        running: win.shown
        command: ["sh", "-c",
            "printf 'hyprland    %s\\n' \"$(hyprctl version 2>/dev/null | head -1 | cut -d' ' -f1-2)\"; " +
            "printf 'quickshell  %s\\n' \"$(qs --version 2>/dev/null | head -1)\"; " +
            "printf 'kernel      %s\\n' \"$(uname -r)\"; " +
            "printf 'host        %s\\n' \"$(cat /etc/hostname)\"; " +
            "printf 'uptime      %s\\n' \"$(uptime -p | sed 's/^up //')\""]
        stdout: StdioCollector { onStreamFinished: versions.lines = text.trim().split("\n") }
    }
}
