// Aurora focus panel: today's focused time, what it went into, and the week.
//   open:  click the focus pill in the bar  ·  Super+Shift+T  ·  qs ipc call focus panel
//   keys:  Space start / pause · 1–9 pick what you're doing · Tab next one · Esc close
//   start/pause without opening anything: Super+T, or right-click the pill

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: fp

    property bool shown: false
    visible: shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "focus"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function tagColor(t) {
        const c = [Theme.accent, Theme.sky, Theme.violet, Theme.yellow, Theme.pink, Theme.red];
        const i = Focus.tags.indexOf(t);
        return c[(i < 0 ? c.length - 1 : i) % c.length];
    }
    readonly property real pct: Math.min(1, Focus.total / Focus.goalSecs)

    // live seconds while you're looking
    Timer { interval: 1000; repeat: true; running: fp.shown; onTriggered: Focus.now = Date.now() }

    function close() { Panels.focusOpen = false }
    property bool wasInside: false
    Timer { id: leaveTimer; interval: 350; onTriggered: if (!cardHover.hovered) fp.close() }
    Connections {
        target: Panels
        function onFocusOpenChanged() {
            if (Panels.focusOpen) {
                hide.stop();
                fp.shown = true;
                fp.wasInside = false;
                Focus.now = Date.now();
                Focus.loadWeek();
                card.forceActiveFocus();
                appear.restart();
            } else {
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
        onFinished: fp.shown = false
        NumberAnimation { target: slide; property: "y"; to: -8; duration: 120; easing.type: Easing.InCubic }
        NumberAnimation { target: card; property: "opacity"; to: 0; duration: 110 }
    }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: fp.close() }

    component Mono: Text {
        font.family: Theme.mono
        font.pixelSize: 11
        color: Theme.muted
    }
    // "# apps" list with bars
    component TopList: ColumnLayout {
        id: tl
        property string title: ""
        property var items: []
        property color tint: Theme.accent
        property string empty: "—"
        spacing: 5
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        Mono { text: "# " + tl.title; color: Theme.dim }
        Mono { visible: tl.items.length === 0; text: tl.empty; color: Theme.dim; opacity: 0.7 }
        Repeater {
            model: tl.items
            ColumnLayout {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: modelData.k
                        font.family: Theme.font; font.pixelSize: 12
                        color: index === 0 ? Theme.text : Theme.subtext
                    }
                    Mono { text: Focus.fmt(modelData.v); color: Theme.dim; font.features: { "tnum": 1 } }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 3; radius: 2
                    color: Theme.card
                    Rectangle {
                        width: parent.width * Math.min(1, modelData.v / Math.max(1, tl.items[0].v))
                        height: parent.height; radius: 2
                        color: tl.tint
                        opacity: 0.9 - index * 0.12
                    }
                }
            }
        }
    }

    // ============================================================ the card
    Rectangle {
        id: card
        objectName: "card"
        anchors { top: parent.top; right: parent.right; topMargin: Theme.barHeight + 8; rightMargin: 10 }
        width: 600
        height: col.implicitHeight + 2
        radius: Theme.radius
        color: Theme.bg
        border.width: 1
        border.color: Theme.alpha(Focus.running ? fp.tagColor(Focus.tag) : Theme.accent, 0.3)
        transform: Translate { id: slide; y: 0 }
        focus: true

        HoverHandler {
            id: cardHover
            onHoveredChanged: {
                if (hovered) { fp.wasInside = true; leaveTimer.stop(); }
                else if (fp.wasInside && Panels.focusOpen) leaveTimer.restart();
            }
        }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: card.forceActiveFocus() }

        Keys.onPressed: e => {
            const k = e.key;
            if (k === Qt.Key_Escape || k === Qt.Key_Q) fp.close();
            else if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) Focus.toggle();
            else if (k >= Qt.Key_1 && k <= Qt.Key_9) { const t = Focus.tags[k - Qt.Key_1]; if (t) Focus.setTag(t); }
            else if (k === Qt.Key_Tab) Focus.cycleTag();
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
                    Text { text: "focus"; font.family: Theme.mono; font.pixelSize: 13; font.weight: Font.Bold; color: Theme.text }
                    Mono { text: Qt.formatDate(new Date(), "ddd d MMM"); color: Theme.dim }
                    Item { Layout.fillWidth: true }
                    Mono {
                        text: "goal " + (Settings.o.focusGoal || 6) + "h"
                        color: Theme.dim
                    }
                }
            }

            // ---------------------------------------------------- hero: ring · today · start
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 18
                Layout.bottomMargin: 10
                spacing: 18

                Canvas {
                    id: ring
                    objectName: "ring"
                    implicitWidth: 86
                    implicitHeight: 86
                    property real p: fp.pct
                    property color c: Focus.running ? fp.tagColor(Focus.tag) : Theme.accent
                    onPChanged: requestPaint()
                    onCChanged: requestPaint()
                    onPaint: {
                        const g = getContext("2d"), r = width / 2 - 6;
                        g.reset();
                        g.lineWidth = 7; g.lineCap = "round";
                        g.strokeStyle = Theme.card;
                        g.beginPath(); g.arc(width / 2, height / 2, r, 0, Math.PI * 2); g.stroke();
                        if (p > 0) {
                            g.strokeStyle = c;
                            g.beginPath(); g.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.01, p)); g.stroke();
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: fp.pct >= 1 ? "✓" : Math.round(fp.pct * 100) + "%"
                        font.family: Theme.mono; font.pixelSize: fp.pct >= 1 ? 22 : 15; font.weight: Font.Bold
                        color: fp.pct >= 1 ? Theme.accent : Theme.text
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        objectName: "total"
                        text: Focus.fmt(Focus.total)
                        font.family: Theme.font; font.pixelSize: 30; font.weight: Font.DemiBold
                        color: Theme.text
                    }
                    Mono {
                        text: Focus.total >= Focus.goalSecs ? "goal done · " + Focus.fmt(Focus.total - Focus.goalSecs) + " extra"
                            : Focus.fmt(Focus.goalSecs - Focus.total) + " to go"
                        color: Theme.dim
                    }
                    Mono {
                        objectName: "stateLine"
                        Layout.topMargin: 4
                        textFormat: Text.PlainText
                        text: !Focus.running ? "paused" + (Focus.day.segments.length ? " · " + Focus.day.segments.length + " stretches today" : "")
                            : Focus.idle ? "away · counting resumes when you're back"
                            : "this stretch " + Focus.fmt(Focus.stretch) + " · " + Focus.tag
                        color: !Focus.running ? Theme.muted : Focus.idle ? Theme.yellow : fp.tagColor(Focus.tag)
                    }
                }

                // start / pause
                Rectangle {
                    objectName: "toggle"
                    implicitWidth: 104
                    implicitHeight: 44
                    radius: 22
                    color: Focus.running ? "transparent" : (tgArea.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent)
                    border.width: Focus.running ? 2 : 0
                    border.color: fp.tagColor(Focus.tag)
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        Text { text: Focus.running ? "󰏤" : "󰐊"; font.family: Theme.iconFont; font.pixelSize: 16; color: Focus.running ? fp.tagColor(Focus.tag) : Theme.onAccent; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: Focus.running ? "pause" : "start"; font.family: Theme.mono; font.pixelSize: 13; font.weight: Font.Bold; color: Focus.running ? fp.tagColor(Focus.tag) : Theme.onAccent; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { id: tgArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Focus.toggle() }
                }
            }

            // ---------------------------------------------------- what you're doing
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                spacing: 6
                Repeater {
                    model: Focus.tags
                    Rectangle {
                        required property string modelData
                        required property int index
                        readonly property bool cur: Focus.tag === modelData
                        readonly property real secs: (Focus.rev, Focus.day.tags[modelData] || 0)
                        objectName: "tag:" + modelData
                        implicitWidth: tagRow.implicitWidth + 16
                        implicitHeight: 26
                        radius: 6
                        color: cur ? Theme.alpha(fp.tagColor(modelData), 0.16) : tagArea.containsMouse ? Theme.hover : "transparent"
                        border.width: 1
                        border.color: cur ? Theme.alpha(fp.tagColor(modelData), 0.7) : Theme.cardHi
                        Row {
                            id: tagRow
                            anchors.centerIn: parent
                            spacing: 6
                            Mono { text: index + 1; color: Theme.dim }
                            Mono { text: modelData; color: cur ? fp.tagColor(modelData) : Theme.muted }
                            Mono { visible: secs >= 60; text: Focus.fmt(secs); color: Theme.dim }
                        }
                        MouseArea { id: tagArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Focus.setTag(modelData) }
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // now
            Mono {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 8
                elide: Text.ElideRight
                textFormat: Text.PlainText
                visible: Focus.nowApp !== ""
                text: "▸ " + Focus.nowApp + (Focus.nowProject ? " · " + Focus.nowProject : "") + (Focus.nowDistraction ? "  · " + Focus.nowDistraction + " (counted as a distraction)" : "")
                color: Focus.nowDistraction ? Theme.yellow : Theme.dim
            }

            // ---------------------------------------------------- timeline
            Item {
                id: tlBox
                objectName: "timeline"
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 14
                implicitHeight: 44
                readonly property var segs: (Focus.rev, Focus.day.segments)
                // window: an hour before the first stretch → an hour after now, at least 6 h wide
                readonly property double t1: {
                    const d = new Date(Focus.now); d.setMinutes(0, 0, 0);
                    return d.getTime() + 3600000;
                }
                readonly property double t0: {
                    const first = segs.length ? segs[0][0] : Focus.now;
                    const d = new Date(Math.min(first, t1 - 6 * 3600000)); d.setMinutes(0, 0, 0);
                    return d.getTime();
                }
                function xOf(t) { return (t - t0) / (t1 - t0) * width }
                Rectangle { y: 6; width: parent.width; height: 18; radius: 4; color: Theme.card }
                Repeater {
                    model: tlBox.segs
                    Rectangle {
                        required property var modelData
                        y: 6
                        x: tlBox.xOf(modelData[0])
                        width: Math.max(2, tlBox.xOf(modelData[1]) - x)
                        height: 18
                        radius: 3
                        color: fp.tagColor(modelData[2])
                        opacity: 0.85
                    }
                }
                // now marker
                Rectangle { x: tlBox.xOf(Focus.now); y: 2; width: 2; height: 26; radius: 1; color: Theme.text; opacity: 0.7 }
                Repeater {
                    model: Math.round((tlBox.t1 - tlBox.t0) / 3600000) + 1
                    Mono {
                        required property int index
                        readonly property double t: tlBox.t0 + index * 3600000
                        readonly property int step: (tlBox.t1 - tlBox.t0) > 10 * 3600000 ? 2 : 1
                        visible: index % step === 0
                        x: Math.min(tlBox.width - width, Math.max(0, tlBox.xOf(t) - width / 2))
                        y: 28
                        text: new Date(t).getHours()
                        font.pixelSize: 9
                        color: Theme.dim
                    }
                }
            }

            // ---------------------------------------------------- where the time went
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 10
                spacing: 22
                TopList { title: "apps"; items: (Focus.rev, Focus.top(Focus.day.apps, 5)); tint: Theme.accent; empty: "start the timer to see this" }
                TopList { title: "projects"; items: (Focus.rev, Focus.top(Focus.day.projects, 5)); tint: Theme.sky; empty: "from VS Code / terminal titles" }
                TopList {
                    title: "distractions"
                    items: (Focus.rev, Focus.top(Focus.day.distract, 5))
                    tint: Theme.yellow
                    empty: "none 👌"
                }
            }

            // ---------------------------------------------------- week
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 14
                Layout.bottomMargin: 14
                spacing: 6
                readonly property var days: Focus.week.concat([{ date: Focus.day.date, total: Focus.total }])
                readonly property real peak: Math.max(Focus.goalSecs, ...days.map(d => d.total))
                Mono {
                    text: "# week   " + Focus.fmt(parent.days.reduce((a, d) => a + d.total, 0)) + " · avg " + Focus.fmt(parent.days.reduce((a, d) => a + d.total, 0) / Math.max(1, parent.days.length))
                    color: Theme.dim
                }
                Item {
                    id: weekBox
                    objectName: "week"
                    Layout.fillWidth: true
                    implicitHeight: 64
                    readonly property var days: parent.days
                    readonly property real peak: parent.peak
                    // goal line
                    Rectangle {
                        width: parent.width; height: 1
                        y: 46 - 46 * Focus.goalSecs / weekBox.peak
                        color: Theme.alpha(Theme.accent, 0.35)
                    }
                    Row {
                        anchors.fill: parent
                        spacing: 8
                        Repeater {
                            model: weekBox.days
                            Item {
                                required property var modelData
                                required property int index
                                readonly property bool isToday: index === weekBox.days.length - 1
                                width: (weekBox.width - 8 * (weekBox.days.length - 1)) / Math.max(1, weekBox.days.length)
                                height: weekBox.height
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 18
                                    width: parent.width; height: Math.max(2, 46 * modelData.total / weekBox.peak)
                                    radius: 3
                                    color: modelData.total >= Focus.goalSecs ? Theme.accent : isToday ? Theme.alpha(Theme.accent, 0.6) : Theme.alpha(Theme.text, 0.22)
                                }
                                Mono {
                                    anchors.bottom: parent.bottom
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: ["S", "M", "T", "W", "T", "F", "S"][new Date(modelData.date + "T12:00:00").getDay()] + " " + (modelData.total >= 360 ? (modelData.total / 3600).toFixed(1) : "–")
                                    font.pixelSize: 9
                                    color: isToday ? Theme.text : Theme.dim
                                }
                            }
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
                    anchors.rightMargin: 12
                    spacing: 10
                    Rectangle {
                        Layout.fillHeight: true
                        implicitWidth: modeText.implicitWidth + 20
                        radius: Math.max(0, card.radius - 1)
                        color: !Focus.running ? Theme.dim : Focus.idle ? Theme.yellow : fp.tagColor(Focus.tag)
                        Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: parent.radius; color: parent.color }
                        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: parent.radius; color: parent.color }
                        Text {
                            id: modeText
                            anchors.centerIn: parent
                            text: !Focus.running ? "PAUSED" : Focus.idle ? "AWAY" : "FOCUS"
                            font.family: Theme.mono; font.pixelSize: 11; font.weight: Font.Bold
                            color: Theme.onAccent
                        }
                    }
                    Mono { text: "idle after " + (Settings.o.focusIdle || 5) + "m"; color: Theme.dim }
                    Item { Layout.fillWidth: true }
                    Mono { text: "␣ start/pause · 1-" + Focus.tags.length + " tag · tab next · Super+T anywhere"; font.pixelSize: 10; color: Theme.dim }
                }
            }
        }
    }
}
