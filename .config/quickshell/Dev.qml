pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Dev status shared by the bar pill and the Dev panel:
// git state of the terminal you're working in, docker containers, listening ports.
// Data comes from ~/.local/bin/aurora-devstat, polled every few seconds.
Singleton {
    id: dev

    // ---- knobs
    property int idleMs: 5000            // poll interval normally
    property int openMs: 2000            // poll interval while the Dev panel is open
    readonly property var terminals: ["kitty", "foot", "alacritty", "wezterm", "org.wezfurlong.wezterm", "com.mitchellh.ghostty", "ghostty"]

    // ---- state
    property string cwd: ""              // last terminal's working directory
    property var git: null               // { repo, branch, changed, ahead, behind, path }
    property var containers: []          // [{ name, image, state, status, ports }]
    property var ports: []               // [{ port, proc, pid, host }]
    property string docker: "none"       // ok | off | none
    readonly property int running: containers.filter(c => c.state === "running").length

    // which directory to ask about: the focused terminal's shell, else the last one we saw
    function target() {
        const t = Hyprland.activeToplevel;
        const ipc = t ? t.lastIpcObject : null;
        if (ipc && ipc.pid && terminals.includes((ipc.class || "").toLowerCase()))
            return "pid:" + ipc.pid;
        return cwd;
    }

    function refresh() {
        if (proc.running) return;
        proc.command = [Quickshell.env("HOME") + "/.local/bin/aurora-devstat", target()];
        proc.running = true;
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                let g = null, cs = [], ps = [], dk = "none", wd = "";
                for (const l of text.split("\n")) {
                    const f = l.split("\t");
                    if (f[0] === "cwd") wd = f[1];
                    else if (f[0] === "git") g = { repo: f[1], branch: f[2], changed: Number(f[3]), ahead: Number(f[4]), behind: Number(f[5]), path: f[6] };
                    else if (f[0] === "ctr") cs.push({ name: f[1], image: f[2], state: f[3], status: f[4], ports: f[5] || "" });
                    else if (f[0] === "port") ps.push({ port: Number(f[1]), proc: f[2], pid: f[3], host: f[4] });
                    else if (f[0] === "docker") dk = f[1];
                }
                if (wd !== "") dev.cwd = wd;
                dev.git = g;
                dev.containers = cs.sort((a, b) => (a.state === "running" ? 0 : 1) - (b.state === "running" ? 0 : 1));
                dev.ports = ps;
                dev.docker = dk;
            }
        }
    }

    Timer {
        interval: Panels.devOpen ? dev.openMs : dev.idleMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: dev.refresh()
    }
    // re-check right away when you switch windows
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() { refreshSoon.restart() }
    }
    Timer {
        id: refreshSoon
        interval: 250
        onTriggered: {
            const t = Hyprland.activeToplevel;
            if (t && !(t.lastIpcObject && t.lastIpcObject.pid)) Hyprland.refreshToplevels();
            dev.refresh();
        }
    }

    // ---- actions
    function sh(cmd) { Quickshell.execDetached(["sh", "-c", cmd]) }
    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }   // shell-quote
    function ctr(action, name) {
        if (action === "logs") Quickshell.execDetached(["kitty", "--class", "aurora-float", "--title", "logs · " + name, "docker", "logs", "-f", "--tail", "200", name]);
        else if (action === "shell") Quickshell.execDetached(["kitty", "--title", name, "docker", "exec", "-it", name, "sh", "-c", "command -v bash >/dev/null && exec bash || exec sh"]);
        else sh("docker " + action + " " + q(name) + " >/dev/null 2>&1");
        refreshSoon.restart();
    }
    // open a folder in your editor (VS Code / Codium / Zed if installed, else nvim in kitty)
    function openEditor(path) {
        sh("p=" + q(path) + "; e=${AURORA_EDITOR:-" + q(Settings.o.editor || "") + "}; [ -n \"$e\" ] || e=$(for x in code codium code-oss zed nvim vim; do command -v $x >/dev/null && echo $x && break; done); " +
           "case $e in nvim|vim|vi|hx|helix) kitty --directory \"$p\" $e . ;; *) $e \"$p\" ;; esac");
    }
    function openTerminal(path) { Quickshell.execDetached(["kitty", "--directory", path]) }
    function lazygit(path) { Quickshell.execDetached(["kitty", "--directory", path, "sh", "-c", "lazygit || { git status; exec $SHELL; }"]) }
    // open the repo's remote (GitHub/GitLab…) in the browser
    function openRemote(path) {
        sh("u=$(git -C " + q(path) + " remote get-url origin 2>/dev/null) && " +
           "u=$(printf %s \"$u\" | sed -E 's#^git@([^:]+):#https://\\1/#; s#^ssh://git@#https://#; s#\\.git$##') && xdg-open \"$u\"");
    }
    function killPort(p) {
        if (p.pid && p.pid !== "-") sh("kill " + q(p.pid));
        refreshSoon.restart();
    }
}
