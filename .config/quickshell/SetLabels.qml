// Aurora Settings: key + # comment column on the left of a settings line

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: lb
    property string key
    property string label: ""
    property string desc: ""
    Layout.fillWidth: true
    spacing: 2
    Text {
        text: lb.key
        font.family: Theme.mono
        font.pixelSize: 13
        color: Theme.sky
        elide: Text.ElideRight
        Layout.fillWidth: true
    }
    Text {
        visible: lb.label !== "" || lb.desc !== ""
        text: "# " + lb.label + (lb.label && lb.desc ? " · " : "") + lb.desc
        font.family: Theme.mono
        font.pixelSize: 11
        color: Theme.dim
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
}
