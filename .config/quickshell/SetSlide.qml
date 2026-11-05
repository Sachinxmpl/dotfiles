// Aurora Settings: numeric slider line

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: sl
    property string key
    property string label: ""
    property string desc: ""
    property real value: 0
    property real from: 0
    property real to: 1
    property real step: 1
    property int decimals: 0
    property string suffix: ""
    signal moved(real v)
    Layout.fillWidth: true
    implicitHeight: slLn.implicitHeight + 14
    radius: 5
    color: slHov.hovered ? Theme.alpha(Theme.text, 0.045) : "transparent"
    HoverHandler { id: slHov }
    SetCursor { visible: slHov.hovered }
    RowLayout {
        id: slLn
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 12 }
        spacing: 20
        SetLabels { key: sl.key; label: sl.label; desc: sl.desc }
        Row {
            spacing: 10
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            Item {
                id: trackBox
                width: 200; height: 22
                readonly property real frac: Math.max(0, Math.min(1, (sl.value - sl.from) / (sl.to - sl.from)))
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; height: 2; radius: 1
                    color: Theme.cardHi
                    Rectangle { width: parent.width * trackBox.frac; height: parent.height; radius: 1; color: Theme.accent }
                }
                Rectangle {                                   // block cursor thumb
                    width: 8; height: 16; radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(parent.width - width, parent.width * trackBox.frac - width / 2))
                    color: slArea.pressed || slArea.containsMouse ? Theme.text : Theme.accent
                }
                MouseArea {
                    id: slArea
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    function set(mx) {
                        let v = sl.from + Math.max(0, Math.min(1, mx / width)) * (sl.to - sl.from);
                        v = Math.round(v / sl.step) * sl.step;
                        v = Number(v.toFixed(Math.max(sl.decimals, 2)));
                        if (v !== sl.value) sl.moved(v);
                    }
                    onPressed: m => set(m.x)
                    onPositionChanged: m => { if (pressed) set(m.x) }
                    onWheel: w => {
                        const v = Math.max(sl.from, Math.min(sl.to, sl.value + (w.angleDelta.y > 0 ? sl.step : -sl.step)));
                        sl.moved(Number(v.toFixed(Math.max(sl.decimals, 2))));
                    }
                }
            }
            Text {
                width: 64; height: 22
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignRight
                text: sl.value.toFixed(sl.decimals) + sl.suffix
                font.family: Theme.mono
                font.pixelSize: 12
                color: Theme.violet
            }
        }
    }
}
