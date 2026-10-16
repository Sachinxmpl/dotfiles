// Aurora dashboard: clock, calendar, weather, live system graphs and media.
//   Opens from the bar's clock or Super+D.  Esc / click outside closes.
//   ←/→ change the calendar month · T jumps back to today
// Polling (CPU, RAM, temps, GPU) only runs while the dashboard is open.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris

PanelWindow {
    id: dash

    // ---- knobs --------------------------------------------------------------
    // weather location (default: Kathmandu). Find yours on open-meteo.com
    property real   latitude: 27.7172
    property real   longitude: 85.3240
    property string place: "Kathmandu"
    property bool   showGpu: true          // nvidia-smi briefly wakes the dGPU while open
    property real   dim: 0.06
    property int    openMs: 190
    property int    closeMs: 120
    property int    samples: 40            // graph history length (1 sample / s)

    property bool shown: false
    visible: shown
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "dash"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle { id: backdrop; anchors.fill: parent; color: "black"; opacity: 0 }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: Panels.dashOpen = false
    }

    // ------------------------------------------------------------ open / close
    Connections {
        target: Panels
        function onDashOpenChanged() {
            if (Panels.dashOpen) {
                hide.stop();
                dash.shown = true;
                dash.monthOffset = 0;
                keys.forceActiveFocus();
                dash.refreshOnce();
                appear.restart();
            } else {
                appear.stop();
                hide.restart();
            }
        }
    }
    ParallelAnimation {
        id: appear
        NumberAnimation { target: backdrop; property: "opacity"; to: dash.dim; duration: dash.openMs; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "opacity"; to: 1; duration: dash.openMs; easing.type: Easing.OutQuad }
        NumberAnimation { target: slide; property: "y"; from: -14; to: 0; duration: dash.openMs + 40; easing.type: Easing.OutQuint }
    }
    ParallelAnimation {
        id: hide
        onFinished: dash.shown = false
        NumberAnimation { target: backdrop; property: "opacity"; to: 0; duration: dash.closeMs; easing.type: Easing.InQuad }
        NumberAnimation { target: card; property: "opacity"; to: 0; duration: dash.closeMs; easing.type: Easing.InQuad }
        NumberAnimation { target: slide; property: "y"; to: -8; duration: dash.closeMs; easing.type: Easing.InQuad }
    }

    Item {
        id: keys
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) Panels.dashOpen = false;
            else if (e.key === Qt.Key_Left) dash.monthOffset--;
            else if (e.key === Qt.Key_Right) dash.monthOffset++;
            else if (e.key === Qt.Key_T) dash.monthOffset = 0;
            else return;
            e.accepted = true;
        }
    }

    // =========================================================== data
    SystemClock { id: clock; precision: SystemClock.Seconds }
    readonly property string userName: Quickshell.env("USER") || "you"
    readonly property string greeting: {
        const h = clock.date.getHours();
        return h < 5 ? "Up late" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : h < 21 ? "Good evening" : "Good night";
    }

    // ---- CPU / RAM / uptime from /proc ------------------------------------
    property var cpuHist: []
    property var ramHist: []
    property var gpuHist: []
    property var tempHist: []
    property real cpu: 0          // %
    property real ram: 0          // %
    property real ramUsedGb: 0
    property real ramTotalGb: 0
    property real cpuTemp: -1     // °C
    property real gpu: -1         // %
    property real gpuTemp: -1
    property string uptime: ""
    property real diskUsed: 0     // bytes
    property real diskTotal: 1
    property var _lastCpu: null

    function pushHist(arr, v) {
        const a = arr.slice(-(samples - 1));
        a.push(v);
        return a;
    }

    FileView { id: statFile; path: "/proc/stat"; printErrors: false
        onLoaded: {
            const l = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = l[3] + (l[4] || 0);
            const total = l.reduce((s, x) => s + x, 0);
            if (dash._lastCpu) {
                const dt = total - dash._lastCpu.total, di = idle - dash._lastCpu.idle;
                dash.cpu = dt > 0 ? Math.max(0, Math.min(100, (1 - di / dt) * 100)) : 0;
                dash.cpuHist = dash.pushHist(dash.cpuHist, dash.cpu);
            }
            dash._lastCpu = { total: total, idle: idle };
        }
    }
    FileView { id: memFile; path: "/proc/meminfo"; printErrors: false
        onLoaded: {
            const t = text();
            const get = k => Number((t.match(new RegExp("^" + k + ":\\s+(\\d+)", "m")) || [0, 0])[1]);
            const total = get("MemTotal"), avail = get("MemAvailable");
            if (total > 0) {
                dash.ramTotalGb = total / 1048576;
                dash.ramUsedGb = (total - avail) / 1048576;
                dash.ram = (total - avail) / total * 100;
                dash.ramHist = dash.pushHist(dash.ramHist, dash.ram);
            }
        }
    }
    FileView { id: upFile; path: "/proc/uptime"; printErrors: false
        onLoaded: {
            const s = Math.floor(Number(text().split(" ")[0]));
            const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
            dash.uptime = (d ? d + "d " : "") + (h ? h + "h " : "") + m + "m";
        }
    }

    // ---- temperatures + GPU (one small shell script, every 2 s) -----------
    Process {
        id: sensorsProc
        command: ["sh", "-c",
            "t=''; for want in coretemp k10temp zenpower acpitz; do for h in /sys/class/hwmon/hwmon*; do " +
            "[ \"$(cat $h/name 2>/dev/null)\" = \"$want\" ] && t=$(cat $h/temp1_input 2>/dev/null) && break 2; done; done; " +
            "echo \"cpu ${t:-x}\"; " +
            (dash.showGpu ? "command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | sed 's/^/gpu /;s/,//'" : "true")]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.trim().split("\n")) {
                    const p = line.trim().split(/\s+/);
                    if (p[0] === "cpu" && p[1] !== "x") {
                        dash.cpuTemp = Number(p[1]) / 1000;
                        dash.tempHist = dash.pushHist(dash.tempHist, dash.cpuTemp);
                    } else if (p[0] === "gpu" && p.length >= 3) {
                        dash.gpu = Number(p[1]);
                        dash.gpuTemp = Number(p[2]);
                        dash.gpuHist = dash.pushHist(dash.gpuHist, dash.gpu);
                    }
                }
            }
        }
    }
    Process {
        id: diskProc
        command: ["df", "-B1", "--output=used,size", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split("\n").pop().trim().split(/\s+/).map(Number);
                if (p.length === 2) { dash.diskUsed = p[0]; dash.diskTotal = p[1]; }
            }
        }
    }

    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: dash.shown
        onTriggered: {
            statFile.reload(); memFile.reload();
            if (dash.player) dash.player.positionChanged();
        }
    }
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: dash.shown
        onTriggered: if (!sensorsProc.running) sensorsProc.running = true
    }
    function refreshOnce() {
        upFile.reload();
        diskProc.running = true;
        if (Date.now() - weatherAt > 10 * 60 * 1000) weatherProc.running = true;
    }

    // ---- weather (open-meteo, no API key) ---------------------------------
    property var weather: null
    property real weatherAt: 0
    property bool weatherFailed: false
    Process {
        id: weatherProc
        command: ["curl", "-s", "--max-time", "8",
            "https://api.open-meteo.com/v1/forecast?latitude=" + dash.latitude + "&longitude=" + dash.longitude +
            "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day" +
            "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=5"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    if (!j.current) throw "bad";
                    dash.weather = j;
                    dash.weatherAt = Date.now();
                    dash.weatherFailed = false;
                } catch (e) { dash.weatherFailed = true; }
            }
        }
    }
    // WMO weather code → [Nerd Font glyph, words]
    function wx(code, day) {
        if (code === 0) return [day === 0 ? "󰖔" : "󰖙", "Clear"];
        if (code <= 2) return [day === 0 ? "󰼱" : "󰖕", "Partly cloudy"];
        if (code === 3) return ["󰖐", "Overcast"];
        if (code <= 48) return ["󰖑", "Fog"];
        if (code <= 57) return ["󰖗", "Drizzle"];
        if (code <= 67) return ["󰖗", "Rain"];
        if (code <= 77) return ["󰖘", "Snow"];
        if (code <= 82) return ["󰖖", "Showers"];
        if (code <= 86) return ["󰖘", "Snow showers"];
        return ["󰖓", "Thunderstorm"];
    }

    // ---- media ------------------------------------------------------------
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    function fmtTime(s) {
        s = Math.max(0, Math.floor(s));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    // ---- calendar ---------------------------------------------------------
    property int monthOffset: 0
    readonly property date viewMonth: {
        const d = clock.date;
        return new Date(d.getFullYear(), d.getMonth() + monthOffset, 1);
    }
    // 42 cells, weeks start on Monday
    readonly property var calCells: {
        const first = viewMonth;
        const lead = (first.getDay() + 6) % 7;
        const cells = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(first.getFullYear(), first.getMonth(), 1 - lead + i);
            cells.push({ day: d.getDate(), inMonth: d.getMonth() === first.getMonth(),
                         today: d.toDateString() === clock.date.toDateString(),
                         weekend: d.getDay() === 0 || d.getDay() === 6 });
        }
        return cells;
    }

    // =========================================================== UI pieces
    component Card: Rectangle {
        radius: Theme.radius
        color: Theme.alpha(Theme.card, 0.55)
        border.width: 1
        border.color: Theme.border
    }
    component Caption: Text {
        font.family: Theme.font
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
        color: Theme.muted
    }
    component T: Text {
        font.family: Theme.font
        font.pixelSize: 13
        color: Theme.text
    }
    component Glyph: Text {
        font.family: Theme.iconFont
        color: Theme.subtext
    }
    // little line graph with a soft fill
    component Spark: Canvas {
        id: spark
        property var values: []
        property real maxValue: 100
        property color stroke: Theme.accent
        property int capacity: 40           // matches dash.samples
        onValuesChanged: requestPaint()
        onStrokeChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const v = values, n = capacity;
            if (!v || v.length < 2) return;
            const w = width, h = height, step = w / (n - 1);
            const x0 = w - (v.length - 1) * step;
            const y = val => h - 2 - Math.min(1, val / maxValue) * (h - 4);
            ctx.beginPath();
            ctx.moveTo(x0, y(v[0]));
            for (let i = 1; i < v.length; i++) ctx.lineTo(x0 + i * step, y(v[i]));
            ctx.strokeStyle = stroke;
            ctx.lineWidth = 1.6;
            ctx.lineJoin = "round";
            ctx.stroke();
            ctx.lineTo(w, h); ctx.lineTo(x0, h); ctx.closePath();
            const g = ctx.createLinearGradient(0, 0, 0, h);
            g.addColorStop(0, Qt.rgba(stroke.r, stroke.g, stroke.b, 0.28));
            g.addColorStop(1, Qt.rgba(stroke.r, stroke.g, stroke.b, 0));
            ctx.fillStyle = g;
            ctx.fill();
        }
    }
    // one row of the system card: icon · name · value · graph
    component Stat: RowLayout {
        id: stat
        property string icon
        property string name
        property string value
        property string sub: ""
        property var hist: []
        property real maxValue: 100
        property color tint: Theme.accent
        spacing: 12
        Layout.fillWidth: true
        Rectangle {
            implicitWidth: 34; implicitHeight: 34; radius: 10
            color: Theme.alpha(stat.tint, 0.14)
            Glyph { anchors.centerIn: parent; text: stat.icon; color: stat.tint; font.pixelSize: 16 }
        }
        ColumnLayout {
            spacing: 0
            Layout.fillWidth: false
            Layout.preferredWidth: 110
            Caption { text: stat.name }
            RowLayout {
                spacing: 5
                T { text: stat.value; font.pixelSize: 16; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
                T { text: stat.sub; font.pixelSize: 11; color: Theme.muted; visible: stat.sub !== "" }
            }
        }
        Spark {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            values: stat.hist
            maxValue: stat.maxValue
            stroke: stat.tint
        }
    }
    component MediaBtn: Rectangle {
        id: mb
        property string icon
        property bool big: false
        signal clicked()
        implicitWidth: big ? 40 : 32; implicitHeight: implicitWidth
        radius: implicitWidth / 2
        color: big ? Theme.accent : (mbArea.containsMouse ? Theme.cardHover : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
        Glyph { anchors.centerIn: parent; text: mb.icon; font.pixelSize: mb.big ? 18 : 16; color: mb.big ? Theme.onAccent : Theme.subtext }
        MouseArea { id: mbArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mb.clicked() }
    }

    // =========================================================== the card
    Rectangle {
        id: card
        opacity: 0
        transform: Translate { id: slide; y: -14 }
        anchors.top: parent.top
        anchors.topMargin: Theme.barHeight + 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: 820
        height: body.implicitHeight + 36
        radius: Theme.radius + 6
        color: Theme.surface          // solid: the page behind shouldn't show through
        border.width: 1
        border.color: Theme.line
        clip: true

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // swallow clicks

        RowLayout {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            spacing: 16

            // ================= left column: time + calendar
            ColumnLayout {
                // fixed width; nested layouts fill by default, which squeezed the right column
                Layout.fillWidth: false
                Layout.preferredWidth: 300
                Layout.maximumWidth: 300
                Layout.alignment: Qt.AlignTop
                spacing: 16

                // ---- big clock
                ColumnLayout {
                    spacing: 2
                    Layout.leftMargin: 4
                    RowLayout {
                        spacing: 4
                        T {
                            text: Qt.formatDateTime(clock.date, "HH:mm")
                            font.pixelSize: 56
                            font.weight: Font.Light
                            font.letterSpacing: -1.5
                            font.features: { "tnum": 1 }
                        }
                        T {
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 12
                            text: Qt.formatDateTime(clock.date, "ss")
                            font.pixelSize: 16
                            color: Theme.accent
                            font.features: { "tnum": 1 }
                        }
                    }
                    T { text: Qt.formatDateTime(clock.date, "dddd, d MMMM"); font.pixelSize: 15; color: Theme.subtext }
                    T { text: dash.greeting + ", " + dash.userName; font.pixelSize: 12; color: Theme.muted; Layout.topMargin: 2 }
                }

                // ---- calendar
                Card {
                    Layout.fillWidth: true
                    implicitHeight: calCol.implicitHeight + 24

                    ColumnLayout {
                        id: calCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            T {
                                Layout.leftMargin: 4
                                text: Qt.formatDateTime(dash.viewMonth, "MMMM yyyy")
                                font.weight: Font.DemiBold
                                font.pixelSize: 14
                            }
                            Item { Layout.fillWidth: true }
                            MediaBtn { icon: "󰅁"; onClicked: dash.monthOffset-- }
                            MediaBtn { icon: "󰅂"; onClicked: dash.monthOffset++ }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 7
                            rowSpacing: 2
                            columnSpacing: 2
                            Repeater {
                                model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                                Caption {
                                    required property string modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData
                                    font.letterSpacing: 0
                                    color: index >= 5 ? Theme.violet : Theme.muted
                                }
                            }
                            Repeater {
                                model: dash.calCells
                                Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: 10
                                    color: modelData.today ? Theme.accent : "transparent"
                                    T {
                                        anchors.centerIn: parent
                                        text: modelData.day
                                        font.pixelSize: 12
                                        font.weight: modelData.today ? Font.Bold : Font.Normal
                                        color: modelData.today ? Theme.onAccent
                                             : !modelData.inMonth ? Theme.dim
                                             : modelData.weekend ? Theme.violet : Theme.text
                                        opacity: modelData.inMonth ? 1 : 0.6
                                    }
                                }
                            }
                        }
                        T {
                            visible: dash.monthOffset !== 0
                            Layout.alignment: Qt.AlignHCenter
                            text: "press T for today"
                            font.pixelSize: 11
                            color: Theme.muted
                        }
                    }
                }
            }

            // ================= right column: weather · system · media
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 470
                Layout.minimumWidth: 470
                Layout.alignment: Qt.AlignTop
                spacing: 12

                // ---- weather
                Card {
                    Layout.fillWidth: true
                    implicitHeight: wxCol.implicitHeight + 28

                    ColumnLayout {
                        id: wxCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14
                            Glyph {
                                text: dash.weather ? dash.wx(dash.weather.current.weather_code, dash.weather.current.is_day)[0] : "󰖐"
                                font.pixelSize: 42
                                color: Theme.yellow
                            }
                            ColumnLayout {
                                Layout.fillWidth: false
                                spacing: 0
                                RowLayout {
                                    spacing: 8
                                    T {
                                        text: dash.weather ? Math.round(dash.weather.current.temperature_2m) + "°" : "--°"
                                        font.pixelSize: 34
                                        font.weight: Font.Light
                                    }
                                    ColumnLayout {
                                        spacing: 0
                                        T {
                                            text: dash.weather ? dash.wx(dash.weather.current.weather_code, 1)[1] : (dash.weatherFailed ? "Offline" : "Loading…")
                                            font.weight: Font.DemiBold
                                        }
                                        T { text: dash.place; font.pixelSize: 11; color: Theme.muted }
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            ColumnLayout {
                                visible: dash.weather !== null
                                Layout.fillWidth: false
                                spacing: 3
                                T { Layout.alignment: Qt.AlignRight; font.pixelSize: 11; color: Theme.muted
                                    text: dash.weather ? "feels " + Math.round(dash.weather.current.apparent_temperature) + "°" : "" }
                                T { Layout.alignment: Qt.AlignRight; font.pixelSize: 11; color: Theme.muted
                                    text: dash.weather ? "humidity " + dash.weather.current.relative_humidity_2m + "%" : "" }
                                T { Layout.alignment: Qt.AlignRight; font.pixelSize: 11; color: Theme.muted
                                    text: dash.weather ? "wind " + Math.round(dash.weather.current.wind_speed_10m) + " km/h" : "" }
                            }
                        }

                        // 5-day strip
                        RowLayout {
                            visible: dash.weather !== null
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: dash.weather ? dash.weather.daily.time.length : 0
                                Rectangle {
                                    required property int index
                                    readonly property var dly: dash.weather.daily
                                    Layout.fillWidth: true
                                    implicitHeight: 74
                                    radius: 12
                                    color: index === 0 ? Theme.alpha(Theme.accent, 0.10) : Theme.alpha(Theme.bg, 0.35)
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 2
                                        Caption {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: index === 0 ? "TODAY" : Qt.formatDate(new Date(dly.time[index] + "T00:00"), "ddd").toUpperCase()
                                            color: index === 0 ? Theme.accent : Theme.muted
                                        }
                                        Glyph {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: dash.wx(dly.weather_code[index], 1)[0]
                                            font.pixelSize: 18
                                            color: Theme.text
                                        }
                                        T {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: Math.round(dly.temperature_2m_max[index]) + "°  <font color='" + Theme.muted + "'>" + Math.round(dly.temperature_2m_min[index]) + "°</font>"
                                            textFormat: Text.StyledText
                                            font.pixelSize: 12
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- system
                Card {
                    Layout.fillWidth: true
                    implicitHeight: sysCol.implicitHeight + 28

                    ColumnLayout {
                        id: sysCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            Caption { text: "SYSTEM" }
                            Item { Layout.fillWidth: true }
                            T { text: "up " + dash.uptime; font.pixelSize: 11; color: Theme.muted }
                        }
                        Stat {
                            icon: "󰻠"; name: "CPU"
                            value: Math.round(dash.cpu) + "%"
                            sub: dash.cpuTemp > 0 ? Math.round(dash.cpuTemp) + "°C" : ""
                            hist: dash.cpuHist
                            tint: Theme.accent
                        }
                        Stat {
                            icon: "󰍛"; name: "MEMORY"
                            value: dash.ramUsedGb.toFixed(1) + " GB"
                            sub: "/ " + Math.round(dash.ramTotalGb) + ""
                            hist: dash.ramHist
                            tint: Theme.sky
                        }
                        Stat {
                            visible: dash.showGpu && dash.gpu >= 0
                            icon: "󰢮"; name: "GPU"
                            value: Math.round(dash.gpu) + "%"
                            sub: dash.gpuTemp > 0 ? Math.round(dash.gpuTemp) + "°C" : ""
                            hist: dash.gpuHist
                            tint: Theme.violet
                        }
                        Stat {
                            visible: dash.cpuTemp > 0
                            icon: "󰔏"; name: "TEMP"
                            value: Math.round(dash.cpuTemp) + "°C"
                            hist: dash.tempHist
                            maxValue: 100
                            tint: dash.cpuTemp > 85 ? Theme.red : dash.cpuTemp > 70 ? Theme.yellow : Theme.pink
                        }
                        // disk usage bar
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Rectangle {
                                implicitWidth: 34; implicitHeight: 34; radius: 10
                                color: Theme.alpha(Theme.yellow, 0.14)
                                Glyph { anchors.centerIn: parent; text: "󰋊"; color: Theme.yellow; font.pixelSize: 16 }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                RowLayout {
                                    Layout.fillWidth: true
                                    Caption { text: "DISK  /" }
                                    Item { Layout.fillWidth: true }
                                    T {
                                        font.pixelSize: 11; color: Theme.muted
                                        text: (dash.diskUsed / 1e9).toFixed(0) + " of " + (dash.diskTotal / 1e9).toFixed(0) + " GB"
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 6; radius: 3
                                    color: Theme.card
                                    Rectangle {
                                        height: parent.height; radius: 3
                                        width: parent.width * Math.min(1, dash.diskUsed / dash.diskTotal)
                                        color: Theme.yellow
                                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- media (only when something is playing / paused)
                Card {
                    visible: dash.player !== null
                    Layout.fillWidth: true
                    implicitHeight: 92

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        Rectangle {
                            implicitWidth: 68; implicitHeight: 68; radius: 12
                            clip: true
                            gradient: Gradient {
                                GradientStop { position: 0; color: Theme.gradA }
                                GradientStop { position: 1; color: Theme.gradB }
                            }
                            Image {
                                anchors.fill: parent
                                source: dash.player ? dash.player.trackArtUrl : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: status === Image.Ready
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            T {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: dash.player ? (dash.player.trackTitle || "Unknown") : ""
                                font.weight: Font.DemiBold
                            }
                            T {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: dash.player ? (dash.player.trackArtist || dash.player.identity) : ""
                                font.pixelSize: 12
                                color: Theme.muted
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 8
                                T { text: dash.player ? dash.fmtTime(dash.player.position) : ""; font.pixelSize: 10; color: Theme.muted; font.features: { "tnum": 1 } }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 4; radius: 2
                                    color: Theme.card
                                    Rectangle {
                                        height: parent.height; radius: 2
                                        color: Theme.accent
                                        width: dash.player && dash.player.length > 0
                                               ? parent.width * Math.min(1, dash.player.position / dash.player.length) : 0
                                    }
                                }
                                T { text: dash.player && dash.player.length > 0 ? dash.fmtTime(dash.player.length) : ""; font.pixelSize: 10; color: Theme.muted; font.features: { "tnum": 1 } }
                            }
                        }
                        MediaBtn { icon: "󰒮"; onClicked: if (dash.player) dash.player.previous() }
                        MediaBtn {
                            big: true
                            icon: dash.player && dash.player.isPlaying ? "󰏤" : "󰐊"
                            onClicked: if (dash.player) dash.player.togglePlaying()
                        }
                        MediaBtn { icon: "󰒭"; onClicked: if (dash.player) dash.player.next() }
                    }
                }
            }
        }
    }
}
