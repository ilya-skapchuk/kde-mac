# KDE like a MacBook

KDE Plasma 6 (Wayland) set up for a laptop the way macOS works: three-finger gestures, a desktop of its own for every maximized window, and desktops per screen that can be reordered in the Overview. One command installs it all.

## What you get

**Touchpad**

| Gesture | Action |
|---|---|
| 2 fingers | natural scrolling |
| Click with two / three fingers | right / middle click |
| 3 fingers left / right | next desktop of the screen under the cursor |
| 3 fingers up | Overview; up again for the grid of all desktops |
| 3 fingers down | back from the grid and the Overview; on the desktop it hides all windows (up brings them back) |
| 4 fingers | KDE's built-in gestures: all desktops, the screen follows the fingers |

**Desktops**

- A maximized or fullscreen window gets a desktop of its own, named after the window, like a full-screen app on macOS. When the window is restored, minimized or closed, its desktop goes away and the window returns to its regular desktop.
- Each screen has its own desktops and switches them independently.
- Desktops in the Overview's top bar can be reordered by dragging; the others make room. Windows can be dragged to another desktop or another screen.

## Requirements

- Arch Linux or an Arch-based distribution such as EndeavourOS
- KDE Plasma 6 in a Wayland session
- [yay](https://github.com/Jguer/yay) for the AUR

Tested with KDE Plasma 6.7.5 and InputActions 0.9.2.

## Install

```sh
git clone https://github.com/ilya-skapchuk/kde-mac.git ~/kde-mac
~/kde-mac/install.sh
```

Run it in Konsole inside Plasma: it asks for the sudo password. It is safe to run again at any time. If something isn't active afterwards, log out and back in.

Keep the folder where it is: KDE runs a script from it at every login. If you move it, run `install.sh` again.

### Options

`install.sh --power` also sets the screen to lock after 30 idle minutes, and, on AC, the screen to turn off and the laptop to sleep after 30 minutes. Battery settings stay as they are.

## What install.sh changes

- Installs `base-devel`, `git`, `cmake`, `extra-cmake-modules`, `python` and `vulkan-headers`, and [`inputactions-kwin`](https://aur.archlinux.org/packages/inputactions-kwin) from the AUR.
- Builds and installs the package `kwin-overview-reorder`, a modified copy of KDE's Overview, and switches the stock Overview off.
- Installs the KWin script `macspaces` (desktops for maximized windows).
- Links `~/.config/inputactions/config.yaml` and `swipe.sh` to this folder. Existing files are kept as `*.bak`.
- Lets each screen switch desktops independently and puts all desktops in one row.
- Touchpads: natural scrolling, two-finger scrolling, tap to click, two- and three-finger clicks for right and middle click.
- Adds a check that switches the plugins off after a KWin update, before they could crash it (see below).

## After a KWin update

The gesture and Overview plugins are built for a specific KWin version. When `pacman -Syu` updates KWin, they are switched off at the next login (KDE's stock Overview comes back) and a notification appears. To bring them back, run `install.sh` again: it rebuilds both. Then log out and back in.

## Conflicts

Don't use it together with other KWin scripts that move maximized windows to desktops of their own (such as MACsimize6), or with your own InputActions configuration: `install.sh` replaces it.

## Troubleshooting

- **Gestures get in the way:** hold Backspace + Space + Enter for 2 seconds to suspend InputActions until its settings are reloaded.
- **Back to KDE's stock Overview:**
  ```sh
  sudo pacman -R kwin-overview-reorder
  kwriteconfig6 --file kwinrc --group Plugins --key overviewEnabled true
  ```
  then log out and back in.
- **Logs:** `journalctl --user -b | grep -i -E "kwin|inputactions"`

## What's where

| In the repository | What it is | Installed to |
|---|---|---|
| `inputactions/` | gesture settings: `config.yaml` and `swipe.sh` | links in `~/.config/inputactions/` |
| `kwin-overview-reorder/` | KDE's Overview with per-screen desktops and drag-and-drop: `patch-overview.py` edits the Overview sources from KWin, `spaces.cpp` decides which desktops belong to which screen, `build.sh` builds and installs the package | package `kwin-overview-reorder` |
| `kwin-overview-reorder/spaces-script/` | KWin script: desktops of their own for maximized windows | `~/.local/share/kwin/scripts/macspaces` |
| `kwin-overview-reorder/kwin-plugin-guard.sh` | switches off plugins built for an older KWin | runs before KWin starts (`~/.config/systemd/user/plasma-kwin_wayland.service.d/`) and at login (`~/.config/autostart/`) |
| `install.sh` | installs packages, builds the plugins, applies the KDE settings | — |

## Uninstall

```sh
sudo pacman -R kwin-overview-reorder inputactions-kwin inputactions-ctl
kpackagetool6 --type=KWin/Script --remove macspaces
kwriteconfig6 --file kwinrc --group Plugins --key overviewEnabled true
rm -r ~/.config/inputactions \
    ~/.config/systemd/user/plasma-kwin_wayland.service.d/kwin-plugin-guard.conf \
    ~/.config/autostart/kwin-plugin-guard-notify.desktop
```

Then log out and back in.

## Credits

- [InputActions](https://github.com/taj-ny/InputActions) handles the touchpad gestures.
- The Overview is built from the Overview effect of [KWin](https://invent.kde.org/plasma/kwin) by the KDE developers.
- The idea of desktops for maximized windows comes from [MACsimize6](https://github.com/Ubiquitine/MACsimize6).

## License

[GPL-2.0-or-later](LICENSE), the same as KWin.
