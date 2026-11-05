// Aurora Settings: line with a run button

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: ac
    property string key
    property string label: ""
    property string desc: ""
    property string button: "run"
    signal clicked()
    Layout.fillWidth: true
    implicitHeight: acLn.implicitHeight + 14
    radius: 5
    color: acHov.hovered ? Theme.alpha(Theme.text, 0.045) : "transparent"
    HoverHandler { id: acHov }
    SetCursor { visible: acHov.hovered }
    RowLayout {
        id: acLn
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 12 }
        spacing: 20
        SetLabels { key: ac.key; label: ac.label; desc: ac.desc }
        Row {
            spacing: 10
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            Rectangle {
                width: acText.implicitWidth + 24; height: 26
                radius: 5
                color: acArea.containsMouse ? Theme.alpha(Theme.accent, 0.2) : "transparent"
                border.width: 1
                border.color: Theme.alpha(Theme.accent, acArea.containsMouse ? 0.9 : 0.45)
                Behavior on color { ColorAnimation { duration: 110 } }
                Text {
                    id: acText
                    anchors.centerIn: parent
                    text: "▸ " + ac.button.toLowerCase()
                    font.family: Theme.mono
                    font.pixelSize: 12
                    color: Theme.accent
                }
                MouseArea { id: acArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ac.clicked() }
            }
        }
    }
}
