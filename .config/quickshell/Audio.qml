pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Sound devices: which outputs/inputs exist, which are actually plugged in, and HDMI hotplug.
//   PipeWire (through Quickshell) gives the live devices, volume and default;
//   pactl adds what PipeWire doesn't expose here: whether a port is plugged in (so dead HDMI
//   outputs are hidden) and card profiles (some HDMI outputs only appear after switching one).
// Used by the bar's volume icon and the audio picker (AudioPanel.qml).
Singleton {
    id: au

    // ------------------------------------------------------------ live devices from PipeWire
    readonly property var allSinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property var allSources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio)
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    // a device whose port is unplugged ("not available") is hidden, unless it's the one in use
    function plugged(n) {
        const p = pa.dev[n.name];
        return !p || p.avail || n === sink || n === source;
    }
    readonly property var sinks: allSinks.filter(n => plugged(n))
    readonly property var sources: allSources.filter(n => plugged(n))

    function label(n) {
        if (!n) return "";
        const p = pa.dev[n.name];
        if (p && p.product) return p.product;                  // the monitor/TV's own name, from HDMI
        return n.description || n.nickname || n.name;
    }
    function kind(n) {
        if (!n) return "speakers";
        const s = (n.name + " " + (n.description || "")).toLowerCase();
        const port = (pa.dev[n.name] || {}).port || "";
        if (/hdmi|displayport/.test(s) || /hdmi/.test(port)) return "hdmi";
        if (s.indexOf("bluez") >= 0) return "bluetooth";
        if (/headphone|headset/.test(port) || /headphone|headset/.test(s)) return "headphones";
        if (s.indexOf("usb") >= 0) return "usb";
        return n.isSink ? "speakers" : "mic";
    }
    function icon(k) {
        return ({ hdmi: "󰡁", bluetooth: "󰂰", headphones: "󰋋", usb: "󰕓", speakers: "󰓃", mic: "󰍬" })[k] || "󰓃";
    }
    function use(n) {
        if (!n) return;
        if (n.isSink) Pipewire.preferredDefaultAudioSink = n;
        else Pipewire.preferredDefaultAudioSource = n;
    }

    // ------------------------------------------------------------ pactl: plugged-in state + profiles
    property bool hasPactl: true
    // dev:    node name → { avail, port, product }
    // offers: HDMI outputs that need a card profile switch first (and the way back to speakers)
    property var pa: ({ dev: {}, offers: [] })
    property bool primed: false
    readonly property var offers: pa.offers

    function refresh() { if (!query.running) query.running = true; else again = true }
    property bool again: false
    Process {
        id: query
        command: ["sh", "-c", "command -v pactl >/dev/null || { echo NOPACTL; exit; }; "
            + "pactl -f json list sinks; echo; echo @@; pactl -f json list sources; echo; echo @@; pactl -f json list cards"]
        stdout: StdioCollector { onStreamFinished: au.parse(text) }
        onExited: if (au.again) { au.again = false; au.refresh(); }
    }
    Component.onCompleted: refresh()

    function json(t) { try { return JSON.parse(t.trim() || "[]"); } catch (e) { return []; } }
    function availOf(s) { return !/not available|^no$/i.test(String(s || "")) }

    function parse(text) {
        if (text.trim() === "NOPACTL") { hasPactl = false; primed = true; return; }
        const parts = text.split("@@");
        const sinksJ = json(parts[0] || ""), sourcesJ = json(parts[1] || ""), cardsJ = json(parts[2] || "");
        const dev = {};
        // which cards already have a working (plugged) output
        const cardHasOut = {};
        for (const list of [sinksJ, sourcesJ]) {
            for (const d of list) {
                const port = (d.ports || []).find(p => p.name === d.active_port) || null;
                const avail = !port || availOf(port.availability);
                dev[d.name] = { avail: avail, port: d.active_port || "", product: "" };
                const card = (d.properties || {})["device.name"] || "";
                if (list === sinksJ && avail && card) (cardHasOut[card] = cardHasOut[card] || []).push(d.active_port || "");
            }
        }
        const offers = [];
        for (const c of cardsJ) {
            const props = c.properties || {}, ports = c.ports || {}, profiles = c.profiles || {};
            const cdesc = props["device.description"] || props["device.product.name"] || c.name;
            const active = String(c.active_profile || "");
            // monitor names on this card's plugged HDMI ports
            for (const pn in ports) {
                const p = ports[pn], pp = p.properties || {};
                const product = pp["device.product.name"] || "";
                if (!product) continue;
                for (const d of sinksJ)
                    if ((d.properties || {})["device.name"] === c.name && d.active_port === pn) dev[d.name].product = product;
            }
            // HDMI port plugged in, but no output on this card uses it yet → offer its best profile
            for (const pn in ports) {
                const p = ports[pn];
                const isHdmi = /hdmi|displayport/i.test(pn + " " + (p.type || "") + " " + (p.description || ""));
                if (!isHdmi || !availOf(p.availability)) continue;
                if ((cardHasOut[c.name] || []).indexOf(pn) >= 0) continue;
                let best = null;
                for (const prof of (p.profiles || [])) {
                    const pr = profiles[prof];
                    if (!pr || pr.available === false || prof === active || !(pr.sinks > 0)) continue;
                    // keep the mic if possible (…+input:…), then the card's own priority
                    const score = (prof.indexOf("+input") >= 0 ? 1e6 : 0) + (pr.priority || 0);
                    if (!best || score > best.score) best = { prof: prof, score: score };
                }
                if (!best) continue;
                const product = (p.properties || {})["device.product.name"] || "";
                offers.push({ key: c.name + "/" + pn, card: c.name, profile: best.prof, kind: "hdmi",
                              label: product || p.description || "HDMI", detail: cdesc });
            }
            // card switched to HDMI only: offer the way back to its speakers / headphones
            if (active && active !== "off" && active.indexOf("output:analog") < 0 && active.indexOf("HiFi") < 0) {
                let back = null;
                for (const prof in profiles) {
                    const pr = profiles[prof];
                    if (prof.indexOf("output:analog") < 0 || pr.available === false) continue;
                    const score = (prof.indexOf("+input") >= 0 ? 1e6 : 0) + (pr.priority || 0);
                    if (!back || score > back.score) back = { prof: prof, score: score };
                }
                if (back) offers.push({ key: c.name + "/analog", card: c.name, profile: back.prof, kind: "speakers",
                                        label: "Speakers / headphones", detail: cdesc });
            }
        }
        const prevKeys = hotKeys();
        pa = { dev: dev, offers: offers };
        if (primed) {
            const now = hotKeys();
            for (const k of now) if (prevKeys.indexOf(k) < 0) { arrived(k); break; }
        } else primed = true;
    }

    // HDMI things that can be switched to right now (sink names + offer keys)
    function hotKeys() {
        const out = [];
        for (const name in pa.dev) if (pa.dev[name].avail && /hdmi|displayport|bluez_output/i.test(name + " " + pa.dev[name].port)) out.push(name);
        for (const o of pa.offers) if (o.kind === "hdmi") out.push(o.key);
        return out;
    }
    signal arrived(string key)            // a new HDMI or bluetooth output just became usable

    // switch a card profile; the new output becomes the default as soon as it shows up
    property string pendingCard: ""
    function enable(offer) {
        pendingCard = offer.card;
        setProfile.command = ["pactl", "set-card-profile", offer.card, offer.profile];
        setProfile.running = true;
        pendingTimer.restart();
    }
    Process { id: setProfile; onExited: refreshSoon.restart() }
    Timer { id: pendingTimer; interval: 5000; onTriggered: au.pendingCard = "" }
    onAllSinksChanged: {
        refreshSoon.restart();                    // devices coming/going in PipeWire itself
        if (!pendingCard) return;
        const n = allSinks.find(s => (s.properties || {})["device.name"] === pendingCard);
        if (n) { use(n); pendingCard = ""; }
    }

    // ------------------------------------------------------------ hotplug: pactl subscribe
    Timer { id: refreshSoon; interval: 350; onTriggered: au.refresh() }
    Process {
        id: watch
        running: au.hasPactl
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            onRead: line => {
                // card/sink/source changes (plug, unplug, profile); ignore app streams
                if (/ on (card|sink|source|server) /.test(line)) refreshSoon.restart();
            }
        }
        onExited: restartWatch.restart()          // pipewire-pulse restarted: listen again
    }
    Timer { id: restartWatch; interval: 3000; onTriggered: if (au.hasPactl) watch.running = true }
}
