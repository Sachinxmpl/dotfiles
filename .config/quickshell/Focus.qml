pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Focus tracker: how much real work you did today, on what, and where the time went.
//   Start / pause it yourself (Super+T, or right-click the bar pill). While it runs it quietly notes,
//   every few seconds, which app is in front and which project it belongs to.
//   Away from the keyboard for a while → that time is taken back off and counting pauses by itself
//   until you're back. Nothing pops up unless you turn it on in Settings → focus.
// Data: ~/.local/share/aurora/focus/YYYY-MM-DD.json (one small file per day, plain JSON).
Singleton {
    id: f

    readonly property string dir: Quickshell.env("HOME") + "/.local/share/aurora/focus"
    readonly property var tags: String(Settings.o.focusTags || "code,study,read,other").split(",").map(s => s.trim()).filter(s => s)
    readonly property real goalSecs: Math.max(0.5, Settings.o.focusGoal || 6) * 3600
    readonly property int idleSecs: Math.max(1, Settings.o.focusIdle || 5) * 60

    // ------------------------------------------------------------ state
    property bool running: false
    property string tag: tags[0] || "code"
    property bool idle: false
    property var day: blank(today())          // today's numbers (see blank())
    property bool loaded: false
    property double segStart: 0               // start of the current unbroken stretch (ms)
    property double lastTick: 0
    property int rev: 0                       // bumps on every change so bindings refresh

    readonly property real total: (rev, day.total)
    readonly property real stretch: (rev, running && !idle && segStart ? (now - segStart) / 1000 : 0)
    property double now: Date.now()

    function blank(d) { return { date: d, total: 0, tags: {}, apps: {}, projects: {}, distract: {}, segments: [], open: null } }
    function pad(n) { return String(n).padStart(2, "0") }
    function dateOf(ms) { const d = new Date(ms); return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }
    function today() { return dateOf(Date.now()) }
    function fmt(s) {
        s = Math.max(0, Math.floor(s));
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60;
        return h > 0 ? h + "h " + pad(m) + "m" : m + "m";
    }
    function clock(s) {                         // 2:05 for the bar
        s = Math.max(0, Math.floor(s));
        return Math.floor(s / 3600) + ":" + pad(Math.floor(s / 60) % 60);
    }

    // ------------------------------------------------------------ what's in front
    readonly property var win: ToplevelManager.activeToplevel
    readonly property string appId: win ? String(win.appId || "") : ""
    readonly property string title: win ? String(win.title || "") : ""

    function appName(id) {
        const k = String(id || "").toLowerCase();
        const known = { "code": "VS Code", "code-oss": "VS Code", "vscodium": "VSCodium", "code-url-handler": "VS Code",
            "kitty": "kitty", "foot": "foot", "alacritty": "Alacritty", "org.wezfurlong.wezterm": "WezTerm", "com.mitchellh.ghostty": "Ghostty",
            "brave-browser": "Brave", "firefox": "Firefox", "chromium": "Chromium", "google-chrome": "Chrome", "zen": "Zen",
            "org.kde.okular": "Okular", "org.gnome.nautilus": "Files", "notion-app": "Notion", "obsidian": "Obsidian",
            "discord": "Discord", "vesktop": "Discord", "org.telegram.desktop": "Telegram", "spotify": "Spotify",
            "steam": "Steam", "vlc": "VLC", "nvim-kitty": "Neovim", "jetbrains-idea": "IntelliJ", "jetbrains-pycharm": "PyCharm",
            "org.qbittorrent.qbittorrent": "qBittorrent", "libreoffice-writer": "Writer" };
        if (known[k]) return known[k];
        const last = k.split(".").pop();
        return last ? last.charAt(0).toUpperCase() + last.slice(1) : "";
    }
    function isBrowser(id) { return /brave|firefox|chrom|zen|vivaldi|librewolf|qutebrowser/i.test(id) }
    function isTerminal(id) { return /kitty|foot|alacritty|wezterm|ghostty|konsole|terminal/i.test(id) }

    // the project behind a window: VS Code's folder, a terminal's directory, a JetBrains project
    function projectOf(id, t) {
        if (!t) return "";
        const parts = t.replace(/^●\s*/, "").split(/ [-—–] /);
        if (/code|codium/i.test(id) && parts.length >= 3) return parts[parts.length - 2].replace(/\s*\[.*\]$/, "").trim();
        if (/code|codium/i.test(id) && parts.length === 2) return parts[0].trim();
        if (/jetbrains/i.test(id) && parts.length >= 2) return parts[0].trim();
        if (isTerminal(id) || /nvim/i.test(id)) {
            const m = t.match(/(?:~|\/)[^\s:]*/g);
            if (!m) return "";
            const p = m[m.length - 1].replace(/\/+$/, "");
            if (p === "~" || p === "" || p === "/" || /^\/(tmp|etc|usr|var)/.test(p)) return "";
            const name = p.split("/").pop();
            return name.startsWith(".") ? "" : name;
        }
        return "";
    }
    // time sinks: sites in a browser title, or whole apps (Settings → focus → distractions)
    readonly property var sinks: String(Settings.o.focusDistract || "YouTube,Facebook,Instagram,Reddit,X,TikTok,Netflix,Discord,Telegram,Steam")
        .split(",").map(s => s.trim()).filter(s => s)
    function distractionOf(id, t) {
        const name = appName(id);
        for (const s of sinks) {
            if (name.toLowerCase() === s.toLowerCase()) return s;
            if (!isBrowser(id)) continue;
            if (s === "X") { if (/ \/ X(\b| -|$)| on X:/.test(t)) return "X"; continue; }
            if (t.toLowerCase().indexOf(s.toLowerCase()) >= 0) return s;
        }
        return "";
    }
    readonly property string nowApp: appName(appId)
    readonly property string nowProject: projectOf(appId, title)
    readonly property string nowDistraction: distractionOf(appId, title)

    // ------------------------------------------------------------ controls
    function start(t) {
        if (t && tags.indexOf(t) >= 0) setTag(t);
        if (running) return;
        running = true;
        idle = false;
        lastTick = Date.now();
        openSeg(lastTick);
        autoSnooze = 0;
        save();
    }
    function pause() {
        if (!running) return;
        tick();
        closeSeg(Date.now());
        running = false;
        idle = false;
        recent = [];
        autoSnooze = Date.now() + 30 * 60000;    // auto-start leaves you alone for a while after a manual pause
        save();
    }
    function toggle() { running ? pause() : start() }
    function setTag(t) {
        if (tags.indexOf(t) < 0 || t === tag) return;
        if (running) { tick(); closeSeg(Date.now()); tag = t; openSeg(Date.now()); save(); }
        else tag = t;
    }
    function cycleTag() { setTag(tags[(tags.indexOf(tag) + 1) % tags.length]) }

    // ------------------------------------------------------------ the clock
    // a stretch is one unbroken run of work; idle and pauses end it (that's the timeline)
    function openSeg(t) { segStart = t; day.segments.push([t, t, tag]); rev++ }
    function closeSeg(t) {
        if (!segStart) return;
        const s = day.segments[day.segments.length - 1];
        if (s && s[0] === segStart) {
            s[1] = Math.max(s[0], t);
            if (s[1] - s[0] < 20000) day.segments.pop();        // drop sub-20 s blips
        }
        segStart = 0;
        rev++;
    }
    function add(map, key, dt) { if (key) map[key] = (map[key] || 0) + dt }

    // last few minutes of ticks, so going idle can take that time back off
    property var recent: []
    function tick() {
        const t = Date.now();
        now = t;
        if (dateOf(t) !== day.date) rollover(t);
        if (!running || idle) { lastTick = t; return; }
        const dt = Math.min(t - lastTick, 15000) / 1000;          // timers sleep with the laptop: never count a gap
        lastTick = t;
        if (dt <= 0) return;
        const app = nowApp, proj = nowProject, sink = nowDistraction;
        day.total += dt;
        add(day.tags, tag, dt);
        add(day.apps, app || "other", dt);
        add(day.projects, proj, dt);
        add(day.distract, sink, dt);
        const s = day.segments[day.segments.length - 1];
        if (s && s[0] === segStart) s[1] = t;
        recent.push({ t: t, dt: dt, tag: tag, app: app || "other", proj: proj, sink: sink });
        while (recent.length && recent[0].t < t - idleSecs * 1000 - 30000) recent.shift();
        dirty = true;
        rev++;
        breakCheck();
    }
    Timer { interval: 5000; repeat: true; running: true; onTriggered: f.tick() }
    Timer { interval: 30000; repeat: true; running: true; onTriggered: if (f.dirty) f.save() }

    // ------------------------------------------------------------ away from the keyboard
    IdleMonitor {
        id: idleMon
        enabled: f.running
        timeout: f.idleSecs
        respectInhibitors: false                   // watching a video is not working
        onIsIdleChanged: f.setIdle(isIdle)
    }
    function setIdle(v) {
        if (v === idle) return;
        const t = Date.now();
        if (v) {
            tick();
            // take back what was counted while you were already away
            const since = t - idleSecs * 1000;
            let left = idleSecs;                       // newest ticks first, until the away time is covered
            for (let i = recent.length - 1; i >= 0 && left > 0; i--) {
                const r = recent[i], dt = Math.min(r.dt, left);
                left -= dt;
                day.total -= dt;
                add(day.tags, r.tag, -dt);
                add(day.apps, r.app, -dt);
                add(day.projects, r.proj, -dt);
                add(day.distract, r.sink, -dt);
            }
            recent = [];
            closeSeg(Math.max(segStart, since));
            idle = true;
        } else {
            idle = false;
            lastTick = t;
            if (running) openSeg(t);
        }
        clean();
        save();
    }
    function clean() {
        for (const m of [day.tags, day.apps, day.projects, day.distract])
            for (const k in m) if (m[k] < 1) delete m[k];
        if (day.total < 0) day.total = 0;
        rev++;
    }

    // ------------------------------------------------------------ midnight
    function rollover(t) {
        const wasRunning = running && !idle;
        if (wasRunning) {
            const mid = new Date(t); mid.setHours(0, 0, 0, 0);
            closeSeg(mid.getTime() - 1);
        }
        save();
        day = blank(dateOf(t));
        recent = [];
        dayFile.path = dir + "/" + day.date + ".json";
        if (wasRunning) openSeg(t);
        rev++;
    }

    // ------------------------------------------------------------ gentle nudges (both off by default)
    property bool goalTold: false
    property double lastBreak: 0
    function breakCheck() {
        if (Settings.o.focusGoalNotify && !goalTold && day.total >= goalSecs) {
            goalTold = true;
            Quickshell.execDetached(["notify-send", "-a", "Focus", "-i", "emblem-ok-symbolic", "Goal reached", fmt(day.total) + " of focused work today"]);
        }
        const every = (Settings.o.focusBreak || 0) * 60;
        if (every > 0 && stretch >= every && Date.now() - lastBreak > every * 1000) {
            lastBreak = Date.now();
            Quickshell.execDetached(["notify-send", "-a", "Focus", "-i", "face-smile", "Stretch break?", fmt(stretch) + " without a break"]);
        }
    }

    // ------------------------------------------------------------ auto-start (off by default)
    property double autoSnooze: 0
    property int codeStreak: 0
    Timer {
        interval: 10000; repeat: true
        running: Settings.o.focusAuto === true && !f.running
        onTriggered: {
            const coding = /code|codium|jetbrains|nvim/i.test(f.appId) || (f.isTerminal(f.appId) && f.nowProject !== "");
            f.codeStreak = coding && !idleMon.isIdle ? f.codeStreak + 1 : 0;
            if (f.codeStreak >= 12 && Date.now() > f.autoSnooze) { f.codeStreak = 0; f.start("code"); }
        }
    }

    // ------------------------------------------------------------ files
    property bool dirty: false
    FileView {
        id: dayFile
        path: f.dir + "/" + f.today() + ".json"
        printErrors: false
        onLoaded: f.restore(text())
        onLoadFailed: f.restore("")
    }
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", dir])

    function restore(text) {
        if (loaded) return;
        let d = null;
        try { d = JSON.parse(text); } catch (e) { d = null; }
        if (!d || d.date !== today()) d = blank(today());
        for (const k of ["tags", "apps", "projects", "distract"]) if (!d[k]) d[k] = {};
        if (!d.segments) d.segments = [];
        day = d;
        loaded = true;
        // shell restarted / crashed while running: pick up where it left off (if it was minutes ago)
        const o = d.open;
        d.open = null;
        if (o && Date.now() - (o.beat || 0) < 10 * 60000) {
            if (o.tag && tags.indexOf(o.tag) >= 0) tag = o.tag;
            running = true;
            lastTick = Date.now();
            openSeg(lastTick);
        }
        rev++;
        loadWeek();
    }
    function save() {
        if (!loaded) return;
        day.open = running ? { tag: tag, beat: Date.now() } : null;
        dayFile.setText(JSON.stringify(day));
        dirty = false;
    }

    // ------------------------------------------------------------ the last 7 days (for the panel)
    property var week: []                       // [{ date, total }] oldest first, today last
    function loadWeek() { if (!weekProc.running) weekProc.running = true }
    Process {
        id: weekProc
        command: ["sh", "-c", 'cd "$1" 2>/dev/null || exit 0; for i in 6 5 4 3 2 1; do d=$(date -d "-$i day" +%F); '
            + 't=$(sed -n "s/.*\\"total\\": *\\([0-9.]*\\).*/\\1/p" "$d.json" 2>/dev/null | head -1); echo "$d ${t:-0}"; done', "_", f.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const l of text.trim().split("\n")) {
                    const p = l.trim().split(" ");
                    if (p.length === 2) out.push({ date: p[0], total: +p[1] || 0 });
                }
                f.week = out;
            }
        }
    }
    // top N of a map as [{ k, v }]
    function top(map, n) {
        return Object.keys(map || {}).map(k => ({ k: k, v: map[k] })).filter(x => x.v >= 30)
            .sort((a, b) => b.v - a.v).slice(0, n || 5);
    }
}
