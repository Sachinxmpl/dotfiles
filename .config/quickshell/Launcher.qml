// Aurora launcher: search apps, run commands, do quick maths.
//   Super+Space / the bar's aurora button toggle it.
//   type to search · ↑↓ to move · Enter to open · Esc to close
//   ">"  run a shell command (in kitty)      e.g.  > docker ps
//   "="  calculator (Enter copies result)    e.g.  = 1920/1080*16
//   ";"  clipboard history (Super+V)         Enter copies · Shift+Del forgets
//   "~"  git projects (Super+O)              Enter editor · Ctrl+Enter terminal · Alt+Enter lazygit
//   ":"  emoji & dev symbols (Super+.)       Enter copies
//   "?"  web / docs search (Super+/)         e.g.  ? gh loadbalancer · ? aw hyprland · ? mdn flexbox

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: launcher

    // ---- look & feel knobs (edit these, save, and it updates live) ----
    property real dim: 0.18          // background darkness: 0 = none, 1 = black
    property int  openMs: 170        // open animation length (ms)
    property int  closeMs: 120       // close animation length (ms)

    // mapped while open, and until the close animation has finished
    property bool shown: false
    visible: shown
    // full screen: the dimmed area around the card is part of this window, so a
    // click outside the card lands here (with exclusive keyboard focus Hyprland
    // won't send clicks to other surfaces like the shared Scrim)
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // not "aurora-*": the backdrop shouldn't blur the whole screen
    WlrLayershell.namespace: "launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    // it only exists while open, and Esc / Super+Space / clicking outside close it
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // dimmed backdrop, fades with the card
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: "black"
        opacity: 0
    }

    // click anywhere outside the card → close
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: Panels.launcherOpen = false
    }

    // open / close animations
    Connections {
        target: Panels
        function onLauncherOpenChanged() {
            if (Panels.launcherOpen) {
                hide.stop();
                launcher.shown = true;
                search.text = Panels.launcherPrefix !== "" ? Panels.launcherPrefix + " " : "";
                Panels.launcherPrefix = "";
                launcher.clipLoaded = false;
                launcher.projLoaded = false;
                launcher.loadForMode();
                list.currentIndex = 0;
                search.forceActiveFocus();
                appear.restart();
            } else {
                appear.stop();
                hide.restart();
            }
        }
    }
    ParallelAnimation {
        id: appear
        NumberAnimation { target: backdrop; property: "opacity"; to: launcher.dim; duration: launcher.openMs; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "opacity"; to: 1; duration: launcher.openMs; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "scale"; from: 0.96; to: 1; duration: launcher.openMs; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        NumberAnimation { target: slide; property: "y"; from: -16; to: 0; duration: launcher.openMs; easing.type: Easing.OutQuint }
    }
    ParallelAnimation {
        id: hide
        onFinished: launcher.shown = false
        NumberAnimation { target: backdrop; property: "opacity"; to: 0; duration: launcher.closeMs; easing.type: Easing.InQuad }
        NumberAnimation { target: card; property: "opacity"; to: 0; duration: launcher.closeMs; easing.type: Easing.InQuad }
        NumberAnimation { target: card; property: "scale"; to: 0.97; duration: launcher.closeMs; easing.type: Easing.InQuad }
    }

    // ------------------------------------------------------------ usage memory
    // apps you open often float to the top
    property var usage: ({})
    FileView {
        id: usageFile
        path: Quickshell.statePath("launcher-usage.json")
        printErrors: false
        onLoaded: {
            try { launcher.usage = JSON.parse(text()) } catch (e) { launcher.usage = {} }
        }
    }
    function bump(id) {
        const u = Object.assign({}, usage);
        u[id] = (u[id] || 0) + 1;
        usage = u;
        usageFile.setText(JSON.stringify(u));
    }

    // ------------------------------------------------------------ search logic
    readonly property string query: search.text
    readonly property var prefixes: ({ ">": "run", "=": "calc", ";": "clip", "~": "proj", ":": "emoji", "?": "web" })
    readonly property string mode: prefixes[query.charAt(0)] || "apps"
    readonly property string term: (mode === "apps" ? query : query.slice(1)).trim()
    onModeChanged: loadForMode()

    function loadForMode() {
        if (mode === "clip" && !clipLoaded && !clipProc.running) clipProc.running = true;
        if (mode === "proj" && !projLoaded && !projProc.running) projProc.running = true;
    }

    // ---- clipboard history (cliphist) -------------------------------------
    property var clipItems: []
    property bool clipLoaded: false
    property bool clipMissing: false
    Process {
        id: clipProc
        command: ["sh", "-c", "command -v cliphist >/dev/null || { echo '__missing__'; exit 0; }; cliphist list | head -300"]
        stdout: StdioCollector {
            onStreamFinished: {
                launcher.clipMissing = text.startsWith("__missing__");
                launcher.clipItems = launcher.clipMissing ? [] : text.split("\n").filter(l => l.length > 0);
                launcher.clipLoaded = true;
            }
        }
    }

    // ---- git projects (aurora-projects) ------------------------------------
    property var projects: []
    property string editor: "code"
    property bool projLoaded: false
    Process {
        id: projProc
        command: [Quickshell.env("HOME") + "/.local/bin/aurora-projects"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const l of text.split("\n")) {
                    const f = l.split("\t");
                    if (f[0] === "#editor") { launcher.editor = f[1]; continue; }
                    if (f.length < 5) continue;
                    out.push({ name: f[0], path: f[1], branch: f[2], dirty: f[3] === "1", ts: Number(f[4]), lang: f[5] || "" });
                }
                launcher.projects = out;
                launcher.projLoaded = true;
            }
        }
    }
    function ago(ts) {
        const s = Date.now() / 1000 - ts;
        return s < 3600 ? Math.max(1, Math.round(s / 60)) + "m ago"
             : s < 86400 ? Math.round(s / 3600) + "h ago"
             : s < 86400 * 60 ? Math.round(s / 86400) + "d ago"
             : Math.round(s / 86400 / 30) + "mo ago";
    }
    readonly property var langGlyph: ({
        go: "", rust: "", ts: "", js: "", python: "",
        java: "", c: "", docker: ""
    })
    readonly property var termEditors: ["nvim", "vim", "vi", "hx", "helix", "nano", "micro", "kak"]

    // ---- emoji + dev symbols (emoji.tsv next to this file) ---------------
    FileView { id: emojiFile; path: Quickshell.shellPath("emoji.tsv"); printErrors: false }
    readonly property var emojis: (emojiFile.text() || "").split("\n").filter(l => l).map(l => l.split("\t"))

    // ---- web / docs search -------------------------------------------------
    readonly property var engines: [
        { k: "",    name: "DuckDuckGo",     url: "https://duckduckgo.com/?q=" },
        { k: "gh",  name: "GitHub",         url: "https://github.com/search?type=repositories&q=" },
        { k: "aw",  name: "ArchWiki",       url: "https://wiki.archlinux.org/index.php?search=" },
        { k: "aur", name: "AUR",            url: "https://aur.archlinux.org/packages?K=" },
        { k: "pkg", name: "Arch packages",  url: "https://archlinux.org/packages/?q=" },
        { k: "so",  name: "Stack Overflow", url: "https://stackoverflow.com/search?q=" },
        { k: "mdn", name: "MDN",            url: "https://developer.mozilla.org/en-US/search?q=" },
        { k: "go",  name: "Go packages",    url: "https://pkg.go.dev/search?q=" },
        { k: "py",  name: "Python docs",    url: "https://docs.python.org/3/search.html?q=" },
        { k: "npm", name: "npm",            url: "https://www.npmjs.com/search?q=" },
        { k: "dh",  name: "Docker Hub",     url: "https://hub.docker.com/search?q=" },
        { k: "aws", name: "AWS docs",       url: "https://docs.aws.amazon.com/search/doc-search.html?searchQuery=" },
        { k: "yt",  name: "YouTube",        url: "https://www.youtube.com/results?search_query=" }
    ]

    function score(e, q) {
        const n = (e.name || "").toLowerCase();
        if (n.startsWith(q)) return 100;
        if (n.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 80;
        if (n.includes(q)) return 60;
        if ((e.genericName || "").toLowerCase().includes(q)) return 40;
        if ((e.keywords || []).some(k => k.toLowerCase().startsWith(q))) return 35;
        if ((e.comment || "").toLowerCase().includes(q)) return 20;
        let i = 0;                                   // loose "fzf"-style match
        for (const c of n) if (c === q[i]) i++;
        return i === q.length ? 10 : 0;
    }

    function calc(expr) {
        if (!/^[0-9+\-*/().,%^ \t]+$/.test(expr)) return null;
        try {
            const v = Function(`"use strict"; return (${expr.replace(/\^/g, "**").replace(/,/g, ".")})`)();
            return (typeof v === "number" && isFinite(v)) ? +v.toFixed(10) : null;
        } catch (e) { return null }
    }

    readonly property var results: {
        if (mode === "run") {
            return term === "" ? [] : [{ kind: "run", title: term, subtitle: "Run in terminal", glyph: "" }];
        }
        if (mode === "calc") {
            const v = calc(term);
            return v === null ? [] : [{ kind: "calc", title: String(v), subtitle: term + "  ·  Enter to copy", glyph: "" }];
        }
        const q = term.toLowerCase();
        if (mode === "clip") {
            const out = [];
            for (const line of clipItems) {
                const tab = line.indexOf("\t");
                const id = line.slice(0, tab), prev = line.slice(tab + 1);
                if (q !== "" && !prev.toLowerCase().includes(q)) continue;
                const isImg = prev.startsWith("[[ binary data");
                out.push({ kind: "clip", line: line,
                           title: prev.replace(/\s+/g, " ").trim() || "(whitespace)",
                           subtitle: (isImg ? "image" : prev.length + " chars") + "  ·  #" + id,
                           glyph: isImg ? "󰋩" : "󰅌" });
                if (out.length >= 60) break;
            }
            return out;
        }
        if (mode === "proj") {
            const out = [];
            for (const p of projects) {
                let s = q === "" ? 1 : score({ name: p.name, comment: p.path }, q);
                if (s <= 0) continue;
                out.push({ kind: "proj", proj: p, s: s,
                           title: p.name,
                           subtitle: " " + p.branch + (p.dirty ? "  ●" : "") + "   ·   " + ago(p.ts)
                                     + (p.lang ? "   ·   " + p.lang : "") + "   ·   " + p.path.replace(Quickshell.env("HOME"), "~"),
                           glyph: langGlyph[p.lang] || "" });
            }
            out.sort((a, b) => b.s - a.s || b.proj.ts - a.proj.ts);
            return out.slice(0, 40);
        }
        if (mode === "emoji") {
            const words = q.split(/\s+/).filter(w => w);
            const out = [];
            for (const e of emojis) {
                const hay = (e[1] + " " + (e[2] || "")).toLowerCase();
                if (words.every(w => hay.includes(w))) {
                    out.push({ kind: "emoji", value: e[0], title: e[1], subtitle: e[2] || "", emoji: e[0] });
                    if (out.length >= 60) break;
                }
            }
            return out;
        }
        if (mode === "web") {
            if (term === "") return engines.slice(1).map(e => ({ kind: "hint", title: "? " + e.k + " …", subtitle: e.name, glyph: "󰖟" }));
            const first = term.split(/\s+/)[0].toLowerCase();
            const hit = engines.find(e => e.k !== "" && e.k === first);
            const out = [];
            if (/^(https?:\/\/)?[\w-]+(\.[\w-]+)+(\/\S*)?$/.test(term))
                out.push({ kind: "url", url: term.startsWith("http") ? term : "https://" + term, title: term, subtitle: "Open in browser", glyph: "󰌷" });
            if (hit) {
                const rest = term.slice(first.length).trim();
                if (rest !== "") out.push({ kind: "url", url: hit.url + encodeURIComponent(rest), title: rest, subtitle: "Search " + hit.name, glyph: "󰍉" });
            } else {
                for (const e of engines)
                    out.push({ kind: "url", url: e.url + encodeURIComponent(term), title: term, subtitle: "Search " + e.name + (e.k ? "   ·   ? " + e.k : ""), glyph: "󰍉" });
            }
            return out;
        }
        const apps = DesktopEntries.applications.values;
        const out = [];
        for (const e of apps) {
            const s = q === "" ? 1 : score(e, q);
            if (s > 0) out.push({ kind: "app", entry: e, s: s + Math.min(usage[e.id] || 0, 25),
                                  title: e.name, subtitle: e.comment || e.genericName || "" });
        }
        out.sort((a, b) => b.s - a.s || a.title.localeCompare(b.title));
        return out.slice(0, 40);
    }

    function activate(i, mods) {
        const r = results[i];
        if (!r) return;
        mods = mods || 0;
        if (r.kind === "hint") { search.text = r.title.replace(" …", " "); return; }
        if (r.kind === "clip") {
            Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | cliphist decode | wl-copy', "_", r.line]);
        } else if (r.kind === "emoji") {
            Quickshell.execDetached(["wl-copy", r.value]);
        } else if (r.kind === "url") {
            Quickshell.execDetached(["xdg-open", r.url]);
        } else if (r.kind === "proj") {
            const p = r.proj.path;
            if (mods & Qt.ControlModifier) Quickshell.execDetached(["kitty", "--directory", p]);
            else if (mods & Qt.AltModifier) Quickshell.execDetached(["kitty", "--directory", p, "sh", "-c", "lazygit || git status; exec $SHELL"]);
            else if (termEditors.includes(editor)) Quickshell.execDetached(["kitty", "--directory", p, editor, "."]);
            else Quickshell.execDetached([editor, p]);
        } else if (r.kind === "app") {
            bump(r.entry.id);
            if (r.entry.runInTerminal) Quickshell.execDetached(["kitty", "-e"].concat(r.entry.command));
            else r.entry.execute();
        } else if (r.kind === "run") {
            Quickshell.execDetached(["kitty", "--hold", "sh", "-c", r.title]);
        } else if (r.kind === "calc") {
            Quickshell.execDetached(["wl-copy", r.title]);
        }
        Panels.launcherOpen = false;
    }
    // Shift+Delete in clipboard mode: forget that entry
    function forget(i) {
        const r = results[i];
        if (!r || r.kind !== "clip") return;
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | cliphist delete', "_", r.line]);
        clipItems = clipItems.filter(l => l !== r.line);
    }

    // ------------------------------------------------------------ UI bits
    // (inline components can't see ids from this file, so state comes in as properties)
    component Chip: Rectangle {
        id: chip
        property string label
        property bool active: false
        signal clicked()
        implicitWidth: chipText.implicitWidth + 24
        implicitHeight: 28
        radius: 14
        color: active ? Theme.accent : (chipArea.containsMouse ? Theme.cardHover : Theme.card)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: chip.active ? Font.DemiBold : Font.Normal
            color: chip.active ? Theme.bg : Theme.muted
        }
        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    function setMode(prefix) {
        search.text = prefix === "" ? term : prefix + " " + term;
        search.forceActiveFocus();
    }

    // ------------------------------------------------------------ the card
    Rectangle {
        id: card
        width: 700
        anchors.horizontalCenter: parent.horizontalCenter
        y: 170
        implicitHeight: col.implicitHeight + 28

        // swallow clicks on the card's own padding so they don't close it
        MouseArea { anchors.fill: parent }
        radius: 24
        color: Theme.alpha(Theme.surface, 0.96)
        border.color: Theme.alpha(Theme.text, 0.12)
        border.width: 1

        opacity: 0
        transformOrigin: Item.Top
        transform: Translate { id: slide; y: 0 }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 12

            // ---- search box
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 54
                radius: 16
                color: Theme.bg
                border.color: Theme.alpha(Theme.accent, 0.45)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 14
                    spacing: 12

                    Text {
                        text: ({ run: "", calc: "󰃬", clip: "󰅌", proj: "󰊢", emoji: "󰞅", web: "󰖟" })[launcher.mode] || "󰍉"
                        font.family: Theme.iconFont
                        font.pixelSize: 17
                        color: Theme.accent
                    }
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: search.implicitHeight
                        TextInput {
                            id: search
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Theme.font
                            font.pixelSize: 18
                            color: Theme.text
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.bg
                            clip: true
                            onTextChanged: list.currentIndex = 0

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    Panels.launcherOpen = false;
                                } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_N && event.modifiers & Qt.ControlModifier)) {
                                    list.currentIndex = Math.min(list.currentIndex + 1, list.count - 1);
                                } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_P && event.modifiers & Qt.ControlModifier)) {
                                    list.currentIndex = Math.max(list.currentIndex - 1, 0);
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    launcher.activate(list.currentIndex, event.modifiers);
                                } else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier)) {
                                    launcher.forget(list.currentIndex);
                                } else {
                                    return;
                                }
                                event.accepted = true;
                            }
                        }
                        Text {
                            visible: search.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search apps   ·   ; clipboard   ·   ~ projects   ·   ? web"
                            font.family: Theme.font
                            font.pixelSize: 18
                            color: Theme.dim
                        }
                    }
                    Rectangle {
                        implicitWidth: escText.implicitWidth + 12
                        implicitHeight: 22
                        radius: 6
                        color: "transparent"
                        border.color: Theme.cardHi
                        Text {
                            id: escText
                            anchors.centerIn: parent
                            text: "esc"
                            font.family: Theme.iconFont
                            font.pixelSize: 11
                            color: Theme.dim
                        }
                    }
                }
            }

            // ---- mode chips
            RowLayout {
                spacing: 6
                Chip { label: "Apps";       active: launcher.mode === "apps";  onClicked: launcher.setMode("") }
                Chip { label: "Clipboard ;"; active: launcher.mode === "clip"; onClicked: launcher.setMode(";") }
                Chip { label: "Projects ~"; active: launcher.mode === "proj";  onClicked: launcher.setMode("~") }
                Chip { label: "Web ?";      active: launcher.mode === "web";   onClicked: launcher.setMode("?") }
                Chip { label: "Emoji :";    active: launcher.mode === "emoji"; onClicked: launcher.setMode(":") }
                Chip { label: "Run >";      active: launcher.mode === "run";   onClicked: launcher.setMode(">") }
                Chip { label: "Calc =";     active: launcher.mode === "calc";  onClicked: launcher.setMode("=") }
            }

            // ---- results
            ListView {
                id: list
                Layout.fillWidth: true
                implicitHeight: Math.min(count, 7) * 56
                visible: count > 0
                clip: true
                model: launcher.results
                currentIndex: 0
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 90
                highlight: Rectangle {
                    radius: 14
                    color: Theme.alpha(Theme.accent, 0.12)
                    border.color: Theme.alpha(Theme.accent, 0.25)
                    border.width: 1
                }

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 56

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 14
                        spacing: 14

                        // app icon, or a glyph tile for run / calc
                        Item {
                            implicitWidth: 36
                            implicitHeight: 36
                            IconImage {
                                anchors.fill: parent
                                visible: row.modelData.kind === "app"
                                source: row.modelData.kind === "app"
                                        ? Quickshell.iconPath(row.modelData.entry.icon, "application-x-executable") : ""
                                asynchronous: true
                            }
                            Rectangle {
                                anchors.fill: parent
                                visible: row.modelData.kind !== "app"
                                radius: 10
                                color: Theme.card
                                Text {
                                    anchors.centerIn: parent
                                    text: row.modelData.emoji || row.modelData.glyph || ""
                                    font.family: row.modelData.emoji ? Theme.font : Theme.iconFont
                                    font.pixelSize: row.modelData.emoji ? 20 : 16
                                    color: Theme.accent
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.title
                                elide: Text.ElideRight
                                font.family: ["app", "emoji", "url", "hint"].includes(row.modelData.kind) ? Theme.font : Theme.iconFont
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                color: Theme.text
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: row.modelData.subtitle
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 11
                                color: Theme.muted
                            }
                        }
                        Text {
                            visible: row.index === list.currentIndex
                            text: "enter"
                            font.family: Theme.iconFont
                            font.pixelSize: 11
                            color: Theme.muted
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: list.currentIndex = row.index
                        onClicked: launcher.activate(row.index, 0)
                    }
                }
            }

            // nothing matched
            Text {
                visible: list.count === 0
                Layout.leftMargin: 6
                text: launcher.mode === "calc" ? (launcher.term === "" ? "Type a sum, e.g.  = 1920 / 1080 * 16" : "Not a valid expression")
                    : launcher.mode === "run" ? "Type a command, e.g.  > docker ps"
                    : launcher.mode === "clip" ? (launcher.clipMissing ? "Clipboard history needs cliphist:  sudo pacman -S cliphist"
                                                 : !launcher.clipLoaded ? "Loading…"
                                                 : launcher.clipItems.length === 0 ? "Nothing copied yet" : "No clips match “" + launcher.term + "”")
                    : launcher.mode === "proj" ? (!launcher.projLoaded ? "Scanning for git repos…"
                                                 : launcher.projects.length === 0 ? "No git repos found in ~/code, ~/projects, ~/college … (see aurora-projects)"
                                                 : "No projects match “" + launcher.term + "”")
                    : launcher.mode === "emoji" ? "No emoji match “" + launcher.term + "”"
                    : "No apps match “" + launcher.term + "”"
                font.family: Theme.font
                font.pixelSize: 13
                color: Theme.dim
            }

            // ---- key hints
            Text {
                Layout.leftMargin: 6
                text: launcher.mode === "clip" ? "↑↓ move   ·   enter copy   ·   shift+del forget   ·   esc close"
                    : launcher.mode === "proj" ? "enter open in " + launcher.editor + "   ·   ctrl+enter terminal   ·   alt+enter lazygit   ·   esc close"
                    : launcher.mode === "emoji" ? "↑↓ move   ·   enter copy   ·   esc close"
                    : "↑↓ move   ·   enter open   ·   esc close"
                font.family: Theme.iconFont
                font.pixelSize: 11
                color: Theme.dim
            }
        }
    }
}
