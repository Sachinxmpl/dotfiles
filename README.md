# Aurora · dotfiles

My Arch Linux + Hyprland desktop: a Quickshell bar and panels styled like a code editor, with colours taken from the wallpaper.
Managed with [yadm](https://yadm.io).

**Stack:** Hyprland (Lua config) · Quickshell · matugen · kitty · fish + starship · Neovim (LazyVim) · SDDM

## Install

```sh
sudo pacman -S --needed yadm git
yadm clone https://github.com/Sachinxmpl/dotfiles
yadm bootstrap      # packages, login theme, dark mode, wallpaper colours
```

Reboot and log in to Hyprland. Package list: [`.config/yadm/packages.txt`](.config/yadm/packages.txt).
Optional from the AUR: `envycontrol` (GPU mode switch).

## What's in it

- **Bar:** workspaces, now playing with a live visualizer, CPU/mem/temp, dev pill (git branch, containers, ports), focus timer, NVIDIA GPU indicator, network, Bluetooth, volume, battery
- **Panels:** launcher, control centre, dashboard, notification centre, media, audio output picker, Wi-Fi/Bluetooth, clipboard history, webcam mirror, power menu, Alt+Tab switcher, overview, capture/record
- **Settings window** (Super+,), and a focus tracker with time per app and per project
- **Wallpaper colours:** `aurora-wall` runs matugen, which recolours the shell, Hyprland, kitty, fish, starship, btop, GTK, KDE apps, VS Code and Neovim

## Keys

| Key | Does | Key | Does |
|---|---|---|---|
| `Super` | launcher | `Super+A` | control centre |
| `Super+Return` | terminal | `Super+D` | dashboard |
| `Super+,` | settings | `Super+Tab` / `Alt+Tab` | overview / switcher |
| `Super+V` | clipboard | `` Super+` `` | notifications |
| `Super+W` | wallpapers | `Super+Shift+M` | media |
| `Super+T` | focus timer | `Super+Shift+A` | audio output |
| `Super+I` | Wi-Fi | `Super+Shift+I` | Bluetooth |
| `Super+Shift+C` | webcam | `Super+Esc` | power menu |
| `Print` | capture | `Super+L` | lock |

All keybinds are listed in Settings → `keybinds.md`; they're defined in [`.config/hypr/hyprland.lua`](.config/hypr/hyprland.lua).

## Layout

```
.config/hypr/          hyprland.lua, hypridle, hyprlock
.config/quickshell/    bar, panels, settings (shell.qml is the entry point)
.config/matugen/       colour templates for each app
.local/bin/aurora-*    wallpaper, screenshots, recording, theme sync scripts
.config/yadm/          bootstrap, packages.txt, SDDM theme
wallpapers/
```
