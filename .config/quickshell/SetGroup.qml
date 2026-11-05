// Aurora Settings: a [section] header with its lines under it

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: grp
    property string title
    Layout.fillWidth: true
    Layout.topMargin: 12
    spacing: 0
    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        Layout.leftMargin: 14
        spacing: 12
        Text {
            text: "[" + grp.title + "]"
            font.family: Theme.mono
            font.pixelSize: 13
            font.weight: Font.Bold
            color: Theme.violet
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
    }
}
