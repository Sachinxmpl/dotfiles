pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The NVIDIA GPU: is it awake, and which programs are keeping it awake?
// Asleep (runtime-suspended, D3cold) it uses ~0 W; awake it costs a few watts of battery.
// Nothing here wakes it: the state comes from /sys and the program list from /proc.
// Only while the GPU panel is open *and* the GPU is already awake do we ask nvidia-smi
// for temperature / load / power.
Singleton {
    id: g

    property string dev: ""                  // /sys/bus/pci/devices/0000:01:00.0
    readonly property bool present: dev !== ""
    property string status: ""               // runtime PM: active · suspended · …
    property string dstate: ""               // D0 (on) · D3hot · D3cold (off)
    readonly property bool awake: status === "active"
    property var procs: []                   // [{ pid, name }] programs with the GPU open
    property var info: ({})                  // from nvidia-smi: name temp util power memUsed memTotal pstate
    property bool watching: false            // GpuPanel open → live details
    property string name: ""                // remembered from the last nvidia-smi answer

    // one small shell call; it only scans /proc while the GPU is awake
    Process {
        id: probe
        command: ["sh", "-c",
            "for d in /sys/bus/pci/devices/*; do "
            + "[ \"$(cat $d/vendor 2>/dev/null)\" = 0x10de ] || continue; "
            + "case \"$(cat $d/class 2>/dev/null)\" in 0x03*) ;; *) continue;; esac; "
            + "echo \"DEV $d\"; echo \"ST $(cat $d/power/runtime_status 2>/dev/null)\"; echo \"PS $(cat $d/power_state 2>/dev/null)\"; "
            + "if [ \"$(cat $d/power/runtime_status 2>/dev/null)\" = active ]; then "
            + "find /proc/[0-9]*/fd -maxdepth 1 -lname '/dev/nvidia[0-9]*' 2>/dev/null | cut -d/ -f3 | sort -un | "
            + "while read p; do echo \"P $p $(cat /proc/$p/comm 2>/dev/null)\"; done; fi; break; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                let dev = "", st = "", ps = "";
                const procs = [];
                for (const l of text.split("\n")) {
                    if (l.startsWith("DEV ")) dev = l.slice(4).trim();
                    else if (l.startsWith("ST ")) st = l.slice(3).trim();
                    else if (l.startsWith("PS ")) ps = l.slice(3).trim();
                    else if (l.startsWith("P ")) {
                        const m = l.match(/^P (\d+) ?(.*)$/);
                        if (m) procs.push({ pid: +m[1], name: m[2] || "?" });
                    }
                }
                g.dev = dev; g.status = st; g.dstate = ps; g.procs = procs;
                if (!g.awake) g.info = ({});
            }
        }
    }
    function refresh() { if (!probe.running) probe.running = true }
    Timer { interval: g.watching ? 1500 : 4000; running: true; repeat: true; triggeredOnStart: true; onTriggered: g.refresh() }

    // live details (only while you're looking, and only when it's already awake)
    Process {
        id: smi
        command: ["nvidia-smi", "--query-gpu=name,temperature.gpu,utilization.gpu,power.draw,memory.used,memory.total,pstate",
                  "--format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(",").map(s => s.trim());
                if (f.length < 7) return;
                const num = s => (isNaN(parseFloat(s)) ? -1 : parseFloat(s));
                g.name = f[0];
                g.info = { name: f[0], temp: num(f[1]), util: num(f[2]), power: num(f[3]),
                           memUsed: num(f[4]), memTotal: num(f[5]), pstate: f[6] };
            }
        }
    }
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: g.watching && g.awake
        onTriggered: if (!smi.running) smi.running = true
    }

    function kill(pid) { killer.command = ["kill", String(pid)]; killer.running = true; }
    Process { id: killer; onExited: refreshSoon.restart() }
    Timer { id: refreshSoon; interval: 600; onTriggered: g.refresh() }
}
