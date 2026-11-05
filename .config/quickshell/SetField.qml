// Aurora Settings: text line, saved on Enter or when you click away

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: fd
    property string key
    property string label: ""
    property string desc: ""
    property string text: ""
    property string placeholder: ""
    property int fieldWidth: 260
    signal edited(string v)
    Layout.fillWidth: true
    implicitHeight: fdLn.implicitHeight + 14
    radius: 5
    color: fdHov.hovered ? Theme.alpha(Theme.text, 0.045) : "transparent"
    HoverHandler { id: fdHov }
    SetCursor { visible: fdHov.hovered }
    RowLayout {
        id: fdLn
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 12 }
        spacing: 20
        SetLabels { key: fd.key; label: fd.label; desc: fd.desc }
        Row {
            spacing: 10
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            Rectangle {
                width: fd.fieldWidth; height: 28
                radius: 5
                color: Theme.alpha(Theme.bg, 0.7)
                border.width: 1
                border.color: input.activeFocus ? Theme.accent : Theme.cardHi
                Text {
                    id: q
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\""
                    font.family: Theme.mono
                    font.pixelSize: 12
                    color: Theme.dim
                }
                TextInput {
                    id: input
                    anchors { fill: parent; leftMargin: 20; rightMargin: 12 }
                    verticalAlignment: TextInput.AlignVCenter
                    text: fd.text
                    font.family: Theme.mono
                    font.pixelSize: 12
                    color: Theme.yellow
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.onAccent
                    selectByMouse: true
                    clip: true
                    onActiveFocusChanged: Settings.editing = activeFocus
                    onEditingFinished: if (text !== fd.text) fd.edited(text)
                    Text {
                        visible: input.text === "" && !input.activeFocus
                        anchors.verticalCenter: parent.verticalCenter
                        text: fd.placeholder
                        font: input.font
                        color: Theme.dim
                    }
                }
            }
        }
    }
}
