pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Power state shared by the power menu (Super+Esc), the bar, the control centre and Settings.
//   profile: power-profiles-daemon   (powerprofilesctl)   power-saver · balanced · performance
//   gpu:     envycontrol, optional   (envycontrol)        integrated · hybrid · nvidia  (needs a reboot)
Singleton {
    id: pw

    property bool hasProfiles: false
    property string profile: "balanced"
    readonly property var profiles: ["power-saver", "balanced", "performance"]

    property bool hasEnvy: false
    property string gpu: ""              // mode envycontrol is set to
    property string bootGpu: ""          // mode this boot started with (what is actually running)
    readonly property bool gpuPending: gpu !== "" && bootGpu !== "" && gpu !== bootGpu
    property bool gpuBusy: false
    property string gpuError: ""

    property string uptime: ""

    function refresh() {
        probe.running = false; probe.running = true;
        uptimeGet.running = false; uptimeGet.running = true;
    }

    function setProfile(p) {
        if (!hasProfiles || profiles.indexOf(p) < 0) return;
        profile = p;                                           // optimistic, corrected by the next refresh
        Quickshell.execDetached(["powerprofilesctl", "set", p]);
        recheck.restart();
    }
    function cycleProfile() { setProfile(profiles[(profiles.indexOf(profile) + 1) % profiles.length]) }

    // asks for your password (polkit), rewrites the GPU config; takes effect after a reboot
    function setGpu(m) {
        if (!hasEnvy || gpuBusy || m === gpu) return;
        gpuError = "";
        gpuBusy = true;
        gpuSet.command = ["pkexec", "envycontrol", "-s", m];
        gpuSet.running = true;
    }

    Component.onCompleted: refresh()
    Timer { interval: 30000; running: true; repeat: true; onTriggered: pw.refresh() }
    Timer { id: recheck; interval: 800; onTriggered: pw.refresh() }

    // one shell call answers everything:  profile|has-ppd|envy-mode|has-envy|boot-mode
    // (boot-mode is remembered in $XDG_RUNTIME_DIR, which is wiped on reboot)
    Process {
        id: probe
        command: ["sh", "-c",
            "p=$(powerprofilesctl get 2>/dev/null); " +
            "if command -v envycontrol >/dev/null; then g=$(envycontrol --query 2>/dev/null | tail -1 | awk '{print $NF}'); e=1; else g=''; e=0; fi; " +
            "r=${XDG_RUNTIME_DIR:-/tmp}/aurora-gpu-boot; [ -s \"$r\" ] || printf '%s' \"$g\" > \"$r\"; b=$(cat \"$r\" 2>/dev/null); " +
            "printf '%s|%s|%s|%s|%s' \"$p\" \"$([ -n \"$p\" ] && echo 1 || echo 0)\" \"$g\" \"$e\" \"$b\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("|");
                pw.hasProfiles = f[1] === "1";
                if (f[0]) pw.profile = f[0];
                pw.hasEnvy = f[3] === "1";
                const g = (f[2] || "").trim().toLowerCase();
                pw.gpu = ["integrated", "hybrid", "nvidia"].indexOf(g) >= 0 ? g : "";
                pw.bootGpu = (f[4] || "").trim().toLowerCase();
            }
        }
    }

    Process {
        id: gpuSet
        stderr: StdioCollector { id: gpuErr }
        onExited: code => {
            pw.gpuBusy = false;
            if (code !== 0) pw.gpuError = code === 126 || code === 127 ? "cancelled" : (gpuErr.text.trim().split("\n").pop() || "failed");
            pw.refresh();
        }
    }

    Process {
        id: uptimeGet
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = Math.floor(parseFloat(text.split(" ")[0]));
                const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
                pw.uptime = d > 0 ? `${d}d ${h}h` : h > 0 ? `${h}h ${m}m` : `${m}m`;
            }
        }
    }
}
