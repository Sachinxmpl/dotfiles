pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Live system numbers for the bar, straight from /proc and /sys (1 s refresh):
// network down/up speed, CPU %, memory, CPU temperature.
Singleton {
    id: st

    property int intervalMs: 1000

    // ---- outputs
    property real rxRate: 0        // bytes/s, all real interfaces (not lo/docker/veth/bridges)
    property real txRate: 0
    property real cpu: 0           // %
    property real memUsed: 0       // GiB
    property real memTotal: 0      // GiB
    readonly property real memPct: memTotal > 0 ? memUsed / memTotal * 100 : 0
    property real temp: -1         // °C, -1 if unknown
    property string iface: ""      // busiest interface, e.g. wlan0

    // 1536 → "1.5K", 2.3e6 → "2.3M"  (always short, for a fixed-width bar)
    function rate(b) {
        if (b < 1024) return Math.round(b) + "B";
        if (b < 1024 * 1024) { const k = b / 1024; return (k < 10 ? k.toFixed(1) : Math.round(k)) + "K"; }
        const m = b / 1048576; return (m < 10 ? m.toFixed(1) : Math.round(m)) + "M";
    }

    // ---- network: /proc/net/dev byte counters
    property var _net: null
    property real _netAt: 0
    FileView { id: netFile; path: "/proc/net/dev"; printErrors: false
        onLoaded: {
            const now = Date.now();
            let rx = 0, tx = 0, best = "", bestBytes = -1;
            for (const line of text().split("\n").slice(2)) {
                const m = line.trim().match(/^([^:]+):\s*(.*)$/);
                if (!m) continue;
                const name = m[1].trim();
                if (/^(lo|docker|veth|br-|virbr|vnet|tun|tap|wg)/.test(name)) continue;
                const f = m[2].trim().split(/\s+/).map(Number);
                rx += f[0]; tx += f[8];
                if (f[0] + f[8] > bestBytes) { bestBytes = f[0] + f[8]; best = name; }
            }
            if (st._net && now > st._netAt) {
                const dt = (now - st._netAt) / 1000;
                st.rxRate = Math.max(0, (rx - st._net.rx) / dt);
                st.txRate = Math.max(0, (tx - st._net.tx) / dt);
            }
            st._net = { rx: rx, tx: tx };
            st._netAt = now;
            st.iface = best;
        }
    }

    // ---- cpu: /proc/stat
    property var _cpu: null
    FileView { id: statFile; path: "/proc/stat"; printErrors: false
        onLoaded: {
            const l = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = l[3] + (l[4] || 0);
            const total = l.reduce((s, x) => s + x, 0);
            if (st._cpu) {
                const dt = total - st._cpu.total, di = idle - st._cpu.idle;
                st.cpu = dt > 0 ? Math.max(0, Math.min(100, (1 - di / dt) * 100)) : 0;
            }
            st._cpu = { total: total, idle: idle };
        }
    }

    // ---- memory: /proc/meminfo
    FileView { id: memFile; path: "/proc/meminfo"; printErrors: false
        onLoaded: {
            const t = text();
            const get = k => Number((t.match(new RegExp("^" + k + ":\\s+(\\d+)", "m")) || [0, 0])[1]);
            const total = get("MemTotal"), avail = get("MemAvailable");
            st.memTotal = total / 1048576;
            st.memUsed = (total - avail) / 1048576;
        }
    }

    // ---- temperature: find the CPU sensor once, then just read that file
    property string tempPath: ""
    Process {
        id: findTemp
        running: true
        command: ["sh", "-c",
            "for want in coretemp k10temp zenpower acpitz; do for h in /sys/class/hwmon/hwmon*; do " +
            "[ \"$(cat $h/name 2>/dev/null)\" = \"$want\" ] && [ -r $h/temp1_input ] && { echo $h/temp1_input; exit 0; }; done; done"]
        stdout: StdioCollector { onStreamFinished: st.tempPath = text.trim() }
    }
    FileView { id: tempFile; path: st.tempPath; printErrors: false
        onLoaded: { const v = Number(text().trim()); st.temp = v > 0 ? v / 1000 : -1; }
    }

    Timer {
        interval: st.intervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        property int n: 0
        onTriggered: {
            netFile.reload();
            statFile.reload();
            if (n % 2 === 0) memFile.reload();
            if (n % 3 === 0 && st.tempPath !== "") tempFile.reload();
            n++;
        }
    }
}
