// "key value" pair for the bar's status line, e.g.  cpu 12%
// The value keeps a fixed width (valueChars digits) so the bar doesn't jitter.
import QtQuick

Row {
    id: kv
    property string key
    property string value
    property color valueColor: Theme.text
    property int valueChars: 4
    spacing: 5
    Text {
        text: kv.key
        color: Theme.dim
        font.family: Theme.mono
        font.pixelSize: 11
        anchors.verticalCenter: parent.verticalCenter
    }
    Text {
        text: kv.value
        color: kv.valueColor
        font.family: Theme.mono
        font.pixelSize: 12
        font.weight: Font.DemiBold
        anchors.verticalCenter: parent.verticalCenter
        // JetBrains Mono at 12px is ~7.2px per character
        width: Math.max(implicitWidth, kv.valueChars * 7.4)
        horizontalAlignment: Text.AlignRight
    }
}
