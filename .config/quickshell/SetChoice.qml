// Aurora Settings: pick-one line: options = [{ v: value, t: label }, ...]

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: ch
    property string key
    property string label: ""
    property string desc: ""
    property var options: []
    property var current
    signal chosen(var v)
    Layout.fillWidth: true
    implicitHeight: chLn.implicitHeight + 14
    radius: 5
    color: chHov.hovered ? Theme.alpha(Theme.text, 0.045) : "transparent"
    HoverHandler { id: chHov }
    SetCursor { visible: chHov.hovered }
    RowLayout {
        id: chLn
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 12 }
        spacing: 20
        SetLabels { key: ch.key; label: ch.label; desc: ch.desc }
        Row {
            spacing: 10
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            Rectangle {
                width: seg.width + 6; height: 28
                radius: 6
                color: Theme.alpha(Theme.bg, 0.7)
                border.width: 1
                border.color: Theme.cardHi
                Row {
                    id: seg
                    anchors.centerIn: parent
                    spacing: 2
                    Repeater {
                        model: ch.options
                        Rectangle {
                            required property var modelData
                            readonly property bool on: modelData.v === ch.current
                            width: segText.implicitWidth + 18
                            height: 22
                            radius: 4
                            color: on ? Theme.accent : (segArea.containsMouse ? Theme.hover : "transparent")
                            Behavior on color { ColorAnimation { duration: 110 } }
                            Text {
                                id: segText
                                anchors.centerIn: parent
                                text: String(parent.modelData.t).toLowerCase()
                                font.family: Theme.mono
                                font.pixelSize: 12
                                font.weight: parent.on ? Font.Bold : Font.Normal
                                color: parent.on ? Theme.onAccent : Theme.muted
                            }
                            MouseArea { id: segArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.chosen(parent.modelData.v) }
                        }
                    }
                }
            }
        }
    }
}
