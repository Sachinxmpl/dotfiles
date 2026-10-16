//@ pragma IconTheme Papirus-Dark
// ~/.config/quickshell/shell.qml  ·  Aurora shell entry point
// Run with:  qs        (it reloads automatically when you save a file)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

ShellRoot {
    // one bar per monitor
    Variants {
        model: Quickshell.screens

        Bar {
            required property var modelData
            screen: modelData
        }
    }

    // panels (open on the main screen)
    Scrim {}
    ControlCenter {}
    Launcher {}
    WallPicker {}
    Dashboard {}
    Overview {}
    DevPanel {}
    Capture {}

    // pop-ups
    Toasts {}
    Osd {}

    // the notification daemon (replaces dunst)
    NotificationServer {
        id: notifServer
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        imageSupported: true
        onNotification: n => Notifs.push(n)
        Component.onCompleted: Notifs.server = notifServer
    }

    // commands for keybinds / terminal:
    //   qs ipc call cc toggle | open | close
    //   qs ipc call launcher toggle | open | close | mode <prefix>
    //   qs ipc call walls toggle | open | close
    //   qs ipc call dash toggle | open | close
    //   qs ipc call overview toggle | open | close
    //   qs ipc call dev toggle | open | close
    //   qs ipc call capture toggle | open | close
    //   qs ipc call osd brightness | volume
    //   qs ipc call notifs dnd | clear
    //   qs ipc call night toggle | on | auto | off | cycle | warmer | cooler
    IpcHandler {
        target: "cc"
        function toggle(): void { Panels.toggleCc() }
        function open(): void { Panels.closeAll(); Panels.ccOpen = true }
        function close(): void { Panels.ccOpen = false }
    }
    IpcHandler {
        target: "launcher"
        function toggle(): void { Panels.toggleLauncher() }
        function open(): void { Panels.closeAll(); Panels.launcherOpen = true }
        function close(): void { Panels.launcherOpen = false }
        // qs ipc call launcher mode ";"   (; clipboard · ~ projects · : emoji · ? web · > run · = calc)
        function mode(prefix: string): void {
            Panels.closeAll();
            Panels.launcherPrefix = prefix;
            Panels.launcherOpen = true;
        }
    }
    IpcHandler {
        target: "walls"
        function toggle(): void { Panels.toggleWalls() }
        function open(): void { Panels.closeAll(); Panels.wallsOpen = true }
        function close(): void { Panels.wallsOpen = false }
    }
    IpcHandler {
        target: "dash"
        function toggle(): void { Panels.toggleDash() }
        function open(): void { Panels.closeAll(); Panels.dashOpen = true }
        function close(): void { Panels.dashOpen = false }
    }
    IpcHandler {
        target: "overview"
        function toggle(): void { Panels.toggleOverview() }
        function open(): void { Panels.closeAll(); Panels.overviewOpen = true }
        function close(): void { Panels.overviewOpen = false }
    }
    IpcHandler {
        target: "dev"
        function toggle(): void { Panels.toggleDev() }
        function open(): void { Panels.closeAll(); Panels.devOpen = true }
        function close(): void { Panels.devOpen = false }
    }
    IpcHandler {
        target: "night"
        function toggle(): void { NightLight.toggle() }
        function cycle(): void { NightLight.cycle() }
        function on(): void { NightLight.setMode("on") }
        function auto(): void { NightLight.setMode("auto") }
        function off(): void { NightLight.setMode("off") }
        function warmer(): void { NightLight.warmer() }
        function cooler(): void { NightLight.cooler() }
    }
    IpcHandler {
        target: "capture"
        function toggle(): void { Panels.toggleCapture() }
        function open(): void { Panels.closeAll(); Panels.captureOpen = true }
        function close(): void { Panels.captureOpen = false }
    }
    IpcHandler {
        target: "notifs"
        function dnd(): void { Notifs.dnd = !Notifs.dnd }
        function clear(): void { Notifs.clearAll() }
    }
}
