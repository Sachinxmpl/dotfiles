// Aurora Settings: accent bar on the hovered settings line

import QtQuick
import QtQuick.Layouts

Rectangle {
    width: 2
    height: parent.height - 10
    radius: 1
    anchors.verticalCenter: parent.verticalCenter
    color: Theme.accent
}
