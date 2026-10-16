// Notification pop-ups, stacked under the bar on the right.
//   click: open / default action · ✕: dismiss · hover: pause the timer

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications

PanelWindow {
    id: toasts

    visible: Notifs.popups.length > 0 && !Panels.ccOpen
    anchors { top: true; right: true }
    margins { top: 6; right: 6 }
    exclusiveZone: 0
    implicitWidth: 380
    implicitHeight: stack.implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "aurora-toasts"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    ColumnLayout {
        id: stack
        width: parent.width
        spacing: 8

        Repeater {
            model: Notifs.popups

            Rectangle {
                id: toast
                required property var modelData
                readonly property var n: modelData
                readonly property bool critical: n && n.urgency === NotificationUrgency.Critical
                readonly property var defaultAction: n ? (n.actions.find(a => a.identifier === "default") ?? null) : null
                readonly property var buttons: n ? n.actions.filter(a => a.identifier !== "default") : []

                Layout.fillWidth: true
                implicitHeight: body.implicitHeight + 26
                radius: 18
                color: Theme.alpha(Theme.surface, 0.95)
                border.width: 1
                border.color: critical ? Theme.alpha(Theme.red, 0.6)
                                       : Theme.alpha(Theme.text, 0.10)

                // slide in from the right
                opacity: 0
                transform: Translate { id: shift; x: 40 }
                Component.onCompleted: enter.start()
                ParallelAnimation {
                    id: enter
                    NumberAnimation { target: toast; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutQuad }
                    NumberAnimation { target: shift; property: "x"; to: 0; duration: 260; easing.type: Easing.OutQuint }
                }

                // auto-hide (critical ones stay until you deal with them)
                Timer {
                    running: !toast.critical && !hover.hovered
                    interval: {
                        const t = toast.n ? toast.n.expireTimeout : 0;
                        if (t <= 0) return 6000;
                        return Math.min(t > 100 ? t : t * 1000, 15000);   // ms or s, capped at 15s
                    }
                    onTriggered: Notifs.dropPopup(toast.n)
                }
                HoverHandler { id: hover }

                // click the card = default action (usually "open the app")
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (toast.defaultAction) toast.defaultAction.invoke();
                        Notifs.dropPopup(toast.n);
                    }
                }

                RowLayout {
                    id: body
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 13 }
                    spacing: 12

                    // app icon / image
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        implicitWidth: 40; implicitHeight: 40
                        radius: 12
                        color: Theme.card
                        clip: true
                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: toast.n && toast.n.image !== "" ? 40 : 24
                            source: !toast.n ? ""
                                  : toast.n.image !== "" ? toast.n.image
                                  : Quickshell.iconPath(toast.n.appIcon || toast.n.desktopEntry || "dialog-information",
                                                        "dialog-information")
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: toast.n ? toast.n.appName : ""
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 11
                                color: toast.critical ? Theme.red : Theme.muted
                            }
                            // dismiss
                            Rectangle {
                                implicitWidth: 22; implicitHeight: 22; radius: 11
                                color: closeArea.containsMouse ? Theme.hover : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: ""
                                    font.family: Theme.iconFont
                                    font.pixelSize: 11
                                    color: Theme.muted
                                }
                                MouseArea {
                                    id: closeArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: toast.n.dismiss()
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: toast.n ? toast.n.summary : ""
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: Theme.text
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: toast.n ? toast.n.body : ""
                            textFormat: Text.StyledText
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 12
                            color: Theme.subtext
                        }

                        // action buttons ("Reply", "Mark as read" ...)
                        RowLayout {
                            visible: toast.buttons.length > 0
                            Layout.topMargin: 6
                            spacing: 6
                            Repeater {
                                model: toast.buttons
                                Rectangle {
                                    required property var modelData
                                    implicitWidth: actText.implicitWidth + 22
                                    implicitHeight: 28
                                    radius: 10
                                    color: actArea.containsMouse ? Theme.cardHi : Theme.card
                                    Text {
                                        id: actText
                                        anchors.centerIn: parent
                                        text: modelData.text
                                        font.family: Theme.font
                                        font.pixelSize: 12
                                        color: Theme.text
                                    }
                                    MouseArea {
                                        id: actArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            modelData.invoke();
                                            Notifs.dropPopup(toast.n);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
