pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Every Aurora option in one place: ~/.config/aurora/settings.json
// The Settings window (Super+,) edits these live. The shell reads them directly;
// Hyprland gets them through a generated ~/.config/hypr/aurora-settings.lua, and
// idle timeouts through a regenerated ~/.config/hypr/hypridle.conf.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property alias o: opts          // Settings.o.blur, Settings.o.terminal, …
    property bool windowOpen: false
    property bool editing: false            // a text field in the Settings window has focus
    property int  writes: 0                 // bumps on every save (the window flashes "written")

    FileView {
        id: file
        path: root.home + "/.config/aurora/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onAdapterUpdated: { writeAdapter(); root.writes++; root.queueApply(); }
        onLoaded: root.queueApply()
        onLoadFailed: { writeAdapter(); root.queueApply(); }   // first run: create the file with defaults

        JsonAdapter {
            id: opts

            // ---- appearance
            property string colorSource: "wallpaper"     // wallpaper · static (original Aurora palette)
            property string scheme: "scheme-vibrant"     // matugen style for wallpaper colours
            property string uiFont: "Inter"
            property string monoFont: "JetBrainsMono Nerd Font"
            property real   fontScale: 1.0
            property int    barHeight: 44
            property int    radius: 14
            property real   barOpacity: 0.72

            // ---- bar
            property int  workspaces: 5
            property bool barTitle: true
            property bool barMedia: true
            property bool visualizer: true           // live spectrum from cava (bar pill + media panel)
            property string vizStyle: "bars"         // bars · wave
            property string audioHotplug: "ask"      // when HDMI audio appears: ask (open the picker) · switch · off
            property bool barStats: true
            property bool barNet: true
            property bool barDev: true
            property string barGpu: "auto"           // NVIDIA pill: auto (only while awake) · always · off
            property bool barFocus: true             // focus timer pill

            // ---- focus tracker (Focus.qml)
            property real   focusGoal: 6               // hours a day
            property int    focusIdle: 5               // minutes without input → away (that time isn't counted)
            property string focusTags: "code,study,read,other"
            property string focusDistract: "YouTube,Facebook,Instagram,Reddit,X,TikTok,Netflix,Discord,Telegram,Steam"
            property bool   focusAuto: false           // start by itself after 2 min in an editor
            property bool   focusGoalNotify: false     // one quiet notification when the goal is reached
            property int    focusBreak: 0              // break reminder every N minutes of one stretch (0 = never)
            property bool barBattery: true
            property bool clock24h: true
            property bool clockSeconds: false

            // ---- notifications (do not disturb schedule, HH:MM, may cross midnight)
            property bool   dndSchedule: false
            property string dndFrom: "22:00"
            property string dndTo: "07:00"

            // ---- windows (Hyprland)
            property int    gapsIn: 2
            property int    gapsOut: 0
            property int    borderSize: 2
            property int    rounding: 10
            property bool   blur: true
            property int    blurSize: 6
            property int    blurPasses: 3
            property bool   shadow: true
            property real   inactiveOpacity: 0.96
            property bool   dimInactive: false
            property bool   animations: true
            property real   animSpeed: 1.0           // 0.5 = twice as fast, 2 = slower
            property string layout: "dwindle"        // dwindle · master · scrolling

            // ---- input
            property string kbLayout: "us"
            property string kbOptions: ""
            property int    repeatRate: 25
            property int    repeatDelay: 600
            property real   sensitivity: 0.0
            property bool   flatAccel: false
            property bool   naturalScroll: true
            property bool   tapToClick: true
            property bool   disableWhileTyping: true
            property real   scrollFactor: 1.0
            property bool   clickFinger: true          // two-finger click = right click (Windows/macOS style)
            property bool   swipe: true

            // ---- display
            property int  refreshRate: 144
            property real scale: 1.0
            property int  vrr: 0                       // 0 off · 1 on · 2 fullscreen only

            // ---- idle & power (seconds, 0 = never)
            property int  dimAfter: 150
            property int  lockAfter: 300
            property int  screenOffAfter: 330
            property int  suspendAfter: 900
            property bool suspendOnAC: false

            // ---- location (weather + night light)
            property string place: "Kathmandu"
            property real   latitude: 27.7172
            property real   longitude: 85.3240

            // ---- default apps
            property string terminal: "kitty"
            property string browser: "brave"
            property string editor: "code"
            property string files: "nautilus"
        }
    }

    // ------------------------------------------------------------ apply (debounced)
    function queueApply() { applyTimer.restart() }
    Timer { id: applyTimer; interval: 500; onTriggered: root.apply() }

    FileView { id: luaOut;  path: root.home + "/.config/hypr/aurora-settings.lua"; printErrors: false }
    FileView { id: idleOut; path: root.home + "/.config/hypr/hypridle.conf"; printErrors: false }
    property string lastLua: ""
    property string lastIdle: ""
    property string lastScheme: ""

    function apply() {
        const lua = hyprLua();
        if (lua !== lastLua) { luaOut.setText(lua); lastLua = lua; }      // Hyprland reloads by itself

        const idle = hypridleConf();
        if (idle !== lastIdle) {
            const first = lastIdle === "";
            idleOut.setText(idle);
            lastIdle = idle;
            if (!first) Quickshell.execDetached(["sh", "-c", "pkill -x hypridle; sleep 0.3; setsid -f hypridle >/dev/null 2>&1"]);
        }

        if (lastScheme !== "" && opts.scheme !== lastScheme && opts.colorSource === "wallpaper")
            regenerateColors();
        lastScheme = opts.scheme;
    }

    // re-run matugen on the current wallpaper with the chosen scheme
    function regenerateColors() {
        Quickshell.execDetached(["sh", "-c",
            "w=$(cat ~/.cache/aurora/wallpaper.path 2>/dev/null) && [ -f \"$w\" ] && AURORA_SCHEME=" + opts.scheme +
            " ~/.local/bin/aurora-wall \"$w\""]);
    }

    function luaStr(s) { return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"' }

    function hyprLua() {
        const o = opts;
        const lines = [
            "-- generated by the Aurora Settings window (Super+,) from ~/.config/aurora/settings.json",
            "-- edit settings there; changes here get overwritten",
            "return {",
            "    terminal = " + luaStr(o.terminal) + ",",
            "    browser  = " + luaStr(o.browser) + ",",
            "    files    = " + luaStr(o.files) + ",",
            "    editor   = " + luaStr(o.editor) + ",",
            "    color_source = " + luaStr(o.colorSource) + ",",
            "    workspaces   = " + o.workspaces + ",",
            "    gaps_in = " + o.gapsIn + ", gaps_out = " + o.gapsOut + ", border_size = " + o.borderSize + ",",
            "    rounding = " + o.rounding + ", layout = " + luaStr(o.layout) + ",",
            "    blur = " + o.blur + ", blur_size = " + o.blurSize + ", blur_passes = " + o.blurPasses + ",",
            "    shadow = " + o.shadow + ", inactive_opacity = " + o.inactiveOpacity.toFixed(2) + ",",
            "    dim_inactive = " + o.dimInactive + ",",
            "    animations = " + o.animations + ", anim_speed = " + o.animSpeed.toFixed(2) + ",",
            "    kb_layout = " + luaStr(o.kbLayout) + ", kb_options = " + luaStr(o.kbOptions) + ",",
            "    repeat_rate = " + o.repeatRate + ", repeat_delay = " + o.repeatDelay + ",",
            "    sensitivity = " + o.sensitivity.toFixed(2) + ", flat_accel = " + o.flatAccel + ",",
            "    natural_scroll = " + o.naturalScroll + ", tap_to_click = " + o.tapToClick + ",",
            "    disable_while_typing = " + o.disableWhileTyping + ", scroll_factor = " + o.scrollFactor.toFixed(2) + ",",
            "    click_finger = " + o.clickFinger + ",",
            "    swipe = " + o.swipe + ",",
            "    refresh_rate = " + o.refreshRate + ", scale = " + o.scale.toFixed(2) + ", vrr = " + o.vrr + ",",
            "}",
            ""
        ];
        return lines.join("\n");
    }

    function hypridleConf() {
        const o = opts;
        const dpmsOff = "hyprctl dispatch 'hl.dsp.dpms({ action = \"off\" })'";
        const dpmsOn = "hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'";
        let s = "# ~/.config/hypr/hypridle.conf — generated by Aurora Settings (Super+,) → Power & idle\n" +
                "# edit the timings there; changes here get overwritten\n\n" +
                "general {\n" +
                "    lock_cmd = pidof hyprlock || hyprlock\n" +
                "    before_sleep_cmd = loginctl lock-session\n" +
                "    after_sleep_cmd = " + dpmsOn + "\n" +
                "}\n";
        if (o.dimAfter > 0)
            s += "\nlistener {\n    timeout = " + o.dimAfter + "\n    on-timeout = brightnessctl -s set 15%\n    on-resume = brightnessctl -r\n}\n";
        if (o.lockAfter > 0)
            s += "\nlistener {\n    timeout = " + o.lockAfter + "\n    on-timeout = loginctl lock-session\n}\n";
        if (o.screenOffAfter > 0)
            s += "\nlistener {\n    timeout = " + o.screenOffAfter + "\n    on-timeout = " + dpmsOff + "\n    on-resume = " + dpmsOn + " && brightnessctl -r\n}\n";
        if (o.suspendAfter > 0)
            s += "\nlistener {\n    timeout = " + o.suspendAfter + "\n    on-timeout = " +
                 (o.suspendOnAC ? "systemctl suspend"
                                : "[ \"$(cat /sys/class/power_supply/AC*/online 2>/dev/null | head -1)\" = \"0\" ] && systemctl suspend") + "\n}\n";
        return s;
    }
}
