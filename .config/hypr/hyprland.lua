-- ~/.config/hypr/hyprland.lua
-- Aurora rice · stage 1: clean base (Hyprland 0.56, Lua config)
-- Edit + save = Hyprland reloads automatically. Errors show as a red bar at the top.

------------------
---- MONITORS ----
------------------
-- Laptop panel at 144 Hz
hl.monitor({ output = "eDP-1", mode = "1920x1080@144", position = "0x0", scale = "1" })
-- Anything else plugged in (HDMI etc.): sensible defaults, placed to the right
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "1" })


---------------------
---- MY PROGRAMS ----
---------------------
local terminal = "kitty"
local browser  = "firefox"
local menu     = "qs ipc call launcher toggle"   -- Aurora launcher (Super+Space)


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Wayland for Qt, GTK, Electron (VS Code, Discord...)
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- hide harmless Qt text-input warnings in the Quickshell log
hl.env("QT_LOGGING_RULES", "qt.qpa.wayland.textinput=false")

-- NVIDIA (kept from your old config, since it works)
-- hl.env("LIBVA_DRIVER_NAME", "nvidia")
-- hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
-- hl.env("NVD_BACKEND", "direct")


-------------------
---- AUTOSTART ----
-------------------
hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start hyprpolkitagent")  -- password popups for GUI apps
    hl.exec_cmd("qs")                                       -- Aurora shell (bar)
    hl.exec_cmd("hypridle")                                 -- auto dim / lock / screen off
    hl.exec_cmd("wl-paste --type text --watch cliphist store")   -- clipboard history (Super+V)
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("awww-daemon")                              -- wallpaper daemon
    hl.exec_cmd("sleep 1 && $HOME/.local/bin/aurora-wall --restore")         -- last wallpaper (Super+W to pick)
end)


-----------------------
---- LOOK AND FEEL ----
-----------------------
-- Border colours follow the wallpaper: matugen writes ~/.config/hypr/colors.lua.
-- Without that file, the original Aurora teal → sky gradient is used.
local okColors, wal = pcall(require, "colors")
if not okColors or type(wal) ~= "table" then wal = {} end
local borderA  = wal.active_a or "rgba(6ee7c8ee)"
local borderB  = wal.active_b or "rgba(7cc4ffee)"
local borderIn = wal.inactive or "rgba(1b2235aa)"

hl.config({
    general = {
        gaps_in  = 2,     -- 4px between windows
        gaps_out = 0,     -- windows touch the screen edges and the bar
        border_size = 2,
        col = {
            active_border   = { colors = { borderA, borderB }, angle = 45 },
            inactive_border = borderIn,
        },
        resize_on_border = true,
        allow_tearing    = false,
        layout = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,
        active_opacity   = 1.0,
        inactive_opacity = 0.96,

        shadow = {
            enabled      = true,
            range        = 18,
            render_power = 3,
            color        = 0x66000000,
        },

        blur = {
            enabled  = true,
            size     = 6,
            passes   = 3,
            vibrancy = 0.17,
        },
    },

    animations = { enabled = true },

    cursor = {
        no_hardware_cursors = true,   -- NVIDIA cursor lag fix (from your old config)
    },

    dwindle = {
        preserve_split = true,   -- a split keeps its direction when windows close
        force_split    = 2,      -- new windows always open to the right / below
    },

    gestures = {
        workspace_swipe_create_new = false,  -- swiping past 5 doesn't make empty workspaces
        workspace_swipe_cancel_ratio = 0.3,  -- a shorter swipe is enough
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        disable_splash_rendering = true,
    },

    input = {
        kb_layout    = "us",
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad = {
            natural_scroll = true,
            tap_to_click   = true,
        },
    },
})

-- Animations (Hyprland 0.56 defaults: smooth and snappy)
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 238.1191, dampening = 24.21279333 })

hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4.1,  spring = "easy",         style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })

-- Touchpad: 3-finger swipe left/right switches workspace
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Workspaces 1-5 always exist (even when empty), so swiping and the bar
-- can always reach them. Without this, an empty workspace disappears.
for i = 1, 5 do
    hl.workspace_rule({ workspace = tostring(i), persistent = true })
end


---------------------
---- KEYBINDINGS ----
---------------------
local mod = "SUPER"

-- Apps
hl.bind(mod .. " + Return",    hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + E",         hl.dsp.exec_cmd("nautilus --new-window"))         -- files (Nautilus)
hl.bind(mod .. " + B",         hl.dsp.exec_cmd(browser))
hl.bind(mod .. " + Space",     hl.dsp.exec_cmd(menu))
hl.bind("SUPER + Super_L",     hl.dsp.exec_cmd(menu), { release = true })   -- tap Super alone
hl.bind(mod .. " + A",         hl.dsp.exec_cmd("qs ipc call cc toggle"))   -- control centre
hl.bind(mod .. " + V",         hl.dsp.exec_cmd("qs ipc call launcher mode ';'"))   -- clipboard history
hl.bind(mod .. " + O",         hl.dsp.exec_cmd("qs ipc call launcher mode '~'"))   -- open a git project
hl.bind(mod .. " + period",    hl.dsp.exec_cmd("qs ipc call launcher mode ':'"))   -- emoji & symbols
hl.bind(mod .. " + slash",     hl.dsp.exec_cmd("qs ipc call launcher mode '?'"))   -- web / docs search
hl.bind(mod .. " + SHIFT + D", hl.dsp.exec_cmd("qs ipc call dev toggle"))    -- dev panel (git · docker · ports)
hl.bind(mod .. " + N",         hl.dsp.exec_cmd("qs ipc call night toggle"))  -- night light on/off
hl.bind(mod .. " + SHIFT + N", hl.dsp.exec_cmd("qs ipc call night auto"))    -- night light: sunset → sunrise
hl.bind(mod .. " + ALT + N",   hl.dsp.exec_cmd("qs ipc call night warmer"))  -- warmer (Super+Ctrl+N cooler)
hl.bind(mod .. " + CTRL + N",  hl.dsp.exec_cmd("qs ipc call night cooler"))
hl.bind(mod .. " + D",         hl.dsp.exec_cmd("qs ipc call dash toggle"))   -- dashboard
hl.bind(mod .. " + W",         hl.dsp.exec_cmd("qs ipc call walls toggle"))  -- wallpaper picker
hl.bind(mod .. " + SHIFT + W", hl.dsp.exec_cmd("$HOME/.local/bin/aurora-wall --random"))      -- random wallpaper
hl.bind(mod .. " + L",         hl.dsp.exec_cmd("loginctl lock-session"))  -- lock (via hypridle)

-- Windows
hl.bind(mod .. " + Q",         hl.dsp.window.close())
hl.bind(mod .. " + F",         hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mod .. " + M",         hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind(mod .. " + SHIFT + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + J",         hl.dsp.layout("togglesplit"))
hl.bind(mod .. " + SHIFT + E", hl.dsp.exit())

-- Focus / move with arrows
for _, d in ipairs({ "left", "right", "up", "down" }) do
    hl.bind(mod .. " + " .. d,             hl.dsp.focus({ direction = d }))
    hl.bind(mod .. " + SHIFT + " .. d,     hl.dsp.window.move({ direction = d }))
    hl.bind(mod .. " + ALT + " .. d,       hl.dsp.window.swap({ direction = d }))
end

-- Tiling
local step = 40
hl.bind(mod .. " + CTRL + left",  hl.dsp.window.resize({ x = -step, y = 0, relative = true }), { repeating = true })
hl.bind(mod .. " + CTRL + right", hl.dsp.window.resize({ x =  step, y = 0, relative = true }), { repeating = true })
hl.bind(mod .. " + CTRL + up",    hl.dsp.window.resize({ x = 0, y = -step, relative = true }), { repeating = true })
hl.bind(mod .. " + CTRL + down",  hl.dsp.window.resize({ x = 0, y =  step, relative = true }), { repeating = true })
hl.bind(mod .. " + P",         hl.dsp.window.pseudo())                 -- keep window's own size inside its tile
hl.bind(mod .. " + C",         hl.dsp.window.center())                 -- center a floating window
hl.bind(mod .. " + G",         hl.dsp.group.toggle())                  -- turn tiles into tabs (and back)
hl.bind(mod .. " + CTRL + Tab", hl.dsp.group.next())                   -- next tab in a group
hl.bind(mod .. " + Tab",       hl.dsp.exec_cmd("qs ipc call overview toggle"))  -- workspace overview
hl.bind("ALT + Tab",           hl.dsp.window.cycle_next())             -- cycle windows on this workspace

-- Workspaces 1-10 (0 = 10)
for i = 1, 10 do
    local key = i % 10
    hl.bind(mod .. " + " .. key,           hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key,   hl.dsp.window.move({ workspace = i }))
end
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Scratchpad (a hidden workspace you can pop in/out)
hl.bind(mod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Mouse: SUPER + drag to move, SUPER + right-drag to resize
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Volume (works on lock screen too, holds to repeat)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })

-- Brightness
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+ && qs ipc call osd brightness"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%- && qs ipc call osd brightness"), { locked = true, repeating = true })

-- Media keys
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- Screenshots (saved to ~/Pictures/Screenshots and copied to clipboard)
local shotDir = "$HOME/Pictures/Screenshots"
local shotFile = shotDir .. "/shot-$(date +%F_%H-%M-%S).png"
hl.bind("Print",             hl.dsp.exec_cmd("qs ipc call capture toggle"))                 -- capture menu
hl.bind("SHIFT + Print",     hl.dsp.exec_cmd("$HOME/.local/bin/aurora-shot region"))        -- region → clipboard
hl.bind("CTRL + Print",      hl.dsp.exec_cmd("$HOME/.local/bin/aurora-shot screen"))        -- full screen
hl.bind("ALT + Print",       hl.dsp.exec_cmd("$HOME/.local/bin/aurora-shot region --edit")) -- region → annotate
hl.bind(mod .. " + SHIFT + R", hl.dsp.exec_cmd("$HOME/.local/bin/aurora-rec toggle region")) -- start/stop recording


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

-- Blur behind the Aurora shell (bar, and later the panels)
hl.layer_rule({
    name  = "aurora-blur",
    match = { namespace = "^aurora-.*" },
    blur  = true,
    ignore_alpha = 0.1,
})

-- Aurora panels animate themselves; skip Hyprland's own fade so they feel snappy
hl.layer_rule({
    name  = "aurora-no-anim",
    match = { namespace = "^(launcher|aurora-cc|scrim|walls|dash|overview|devpanel|capture)$" },
    no_anim = true,
})

-- Terminal popups launched from the bar (e.g. Wi-Fi picker) float, centered
hl.window_rule({
    name  = "float-aurora-popups",
    match = { class = "^aurora-float$" },
    float = true,
    size  = "820 560",
    center = true,
})

-- Small utility windows float, centered
hl.window_rule({
    name  = "float-utilities",
    match = { class = "^(pavucontrol|org.pulseaudio.pavucontrol|blueman-manager|nm-connection-editor)$" },
    float = true,
    size  = "900 600",
    center = true,
})
