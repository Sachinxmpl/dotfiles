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
    SettingsWindow {}
    PowerMenu {}
    Radar {}
    Switcher { id: switcherWin }
    NotifCenter {}
    Media {}
    AudioPanel {}
    GpuPanel {}
    Clip {}
    FocusPanel {}

    // webcam mirror: only loaded while open, so the camera (and its light) is off otherwise.
    // Loaded by file name so a missing Qt Multimedia can't break the rest of the shell.
    LazyLoader {
        id: mirrorLoader
        active: Panels.mirrorOpen || Panels.mirrorRecording
        source: "Mirror.qml"
    }
    Connections {
        target: Panels
        function onMirrorOpenChanged() { if (Panels.mirrorOpen) mirrorCheck.restart() }
    }
    Timer {
        id: mirrorCheck
        interval: 1500
        onTriggered: if (Panels.mirrorOpen && !mirrorLoader.item) {
            Panels.mirrorOpen = false;
            Quickshell.execDetached(["notify-send", "-a", "Camera", "-i", "camera-web", "Mirror needs Qt Multimedia",
                                     "sudo pacman -S --needed qt6-multimedia qt6-multimedia-ffmpeg"]);
        }
    }

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
    //   qs ipc call settings toggle | open | close
    //   qs ipc call power toggle | open | close | profile <name> | cycle
    //   qs ipc call radar wifi | bt | close
    //   qs ipc call switcher next | prev | commit | cancel
    //   qs ipc call osd brightness | volume
    //   qs ipc call notifs toggle | open | dnd | clear
    //   qs ipc call media toggle | open | close
    //   qs ipc call mirror toggle | bubble | close
    //   qs ipc call audio toggle | close
    //   qs ipc call gpu toggle | close
    //   qs ipc call clip toggle | close
    //   qs ipc call focus toggle | start <tag> | pause | panel | status
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
        target: "settings"
        function toggle(): void { Panels.closeAll(); Settings.windowOpen = !Settings.windowOpen }
        function open(): void { Panels.closeAll(); Settings.windowOpen = true }
        function close(): void { Settings.windowOpen = false }
    }
    IpcHandler {
        target: "power"
        function toggle(): void { Settings.windowOpen = false; Panels.togglePower() }
        function open(): void { Settings.windowOpen = false; Panels.closeAll(); Panels.powerOpen = true }
        function close(): void { Panels.powerOpen = false }
        function profile(name: string): void { Power.setProfile(name) }
        function cycle(): void { Power.cycleProfile() }
    }
    IpcHandler {
        target: "radar"
        function wifi(): void { Settings.windowOpen = false; Panels.toggleRadar("wifi") }
        function bt(): void { Settings.windowOpen = false; Panels.toggleRadar("bt") }
        function close(): void { Panels.radarOpen = false }
    }
    IpcHandler {
        target: "switcher"
        function next(): void { switcherWin.step(1) }
        function prev(): void { switcherWin.step(-1) }
        function commit(): void { switcherWin.commit() }
        function cancel(): void { switcherWin.cancel() }
    }
    IpcHandler {
        target: "notifs"
        function toggle(): void { Settings.windowOpen = false; Panels.toggleNotif() }
        function open(): void { Settings.windowOpen = false; Panels.closeAll(); Panels.notifOpen = true }
        function dnd(): void { Notifs.dnd = !Notifs.dnd }
        function clear(): void { Notifs.clearAll() }
    }
    IpcHandler {
        target: "media"
        function toggle(): void { Settings.windowOpen = false; Panels.toggleMedia() }
        function open(): void { Settings.windowOpen = false; Panels.closeAll(); Panels.mediaOpen = true }
        function close(): void { Panels.mediaOpen = false }
    }
    IpcHandler {
        target: "mirror"
        function toggle(): void { Settings.windowOpen = false; Panels.toggleMirror() }
        function bubble(): void { Panels.toggleBubble() }
        function close(): void { Panels.mirrorOpen = false }
    }
    IpcHandler {
        target: "audio"
        function toggle(): void { Settings.windowOpen = false; Panels.toggleAudio() }
        function close(): void { Panels.audioOpen = false }
    }
    IpcHandler {
        target: "gpu"
        function toggle(): void { Settings.windowOpen = false; Panels.toggleGpu() }
        function close(): void { Panels.gpuOpen = false }
    }
    IpcHandler {
        target: "clip"
        function toggle(): void { Settings.windowOpen = false; Panels.toggleClip() }
        function close(): void { Panels.clipOpen = false }
    }
    IpcHandler {
        target: "focus"
        function toggle(): void { Focus.toggle() }
        function start(tag: string): void { Focus.start(tag) }
        function pause(): void { Focus.pause() }
        function panel(): void { Settings.windowOpen = false; Panels.toggleFocus() }
        function status(): string {
            return (Focus.running ? (Focus.idle ? "away" : "focus") : "paused") + " " + Focus.tag + " " + Focus.fmt(Focus.total);
        }
    }
}
