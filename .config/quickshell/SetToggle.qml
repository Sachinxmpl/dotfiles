// Aurora Settings: true / false switch line

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: tg
    property string key
    property string label: ""
    property string desc: ""
    property bool checked: false
    signal toggled(bool v)
    Layout.fillWidth: true
    implicitHeight: tgLn.implicitHeight + 14
    radius: 5
    color: tgHov.hovered ? Theme.alpha(Theme.text, 0.045) : "transparent"
    HoverHandler { id: tgHov }
    SetCursor { visible: tgHov.hovered }
    RowLayout {
        id: tgLn
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 12 }
        spacing: 20
        SetLabels { key: tg.key; label: tg.label; desc: tg.desc }
        Row {
            spacing: 10
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            Item {
                width: tgRow.width; height: 22
                Row {
                    id: tgRow
                    spacing: 10
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        width: 34; height: 18; radius: 5
                        anchors.verticalCenter: parent.verticalCenter
                        color: tg.checked ? Theme.alpha(Theme.accent, 0.22) : Theme.alpha(Theme.text, 0.05)
                        border.width: 1
                        border.color: tg.checked ? Theme.accent : Theme.cardHi
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Rectangle {
                            width: 12; height: 12; radius: 3
                            y: 3
                            x: tg.checked ? parent.width - width - 3 : 3
                            color: tg.checked ? Theme.accent : Theme.dim
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                    }
                    Text {
                        width: 42
                        anchors.verticalCenter: parent.verticalCenter
                        text: tg.checked ? "true" : "false"
                        font.family: Theme.mono
                        font.pixelSize: 12
                        color: tg.checked ? Theme.teal : Theme.red
                    }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled(!tg.checked) }
            }
        }
    }
}
