#!/bin/bash
# Sets up the macOS-like KDE Plasma desktop from this repository: three-finger
# gestures (InputActions), Spaces for maximized windows, the Overview with
# per-screen reorderable desktops and touchpad settings; with --power also
# screen lock and power settings. Safe to run again at any time, e.g. after
# reinstalling the system or after a KWin update.
#
# Requirements: Arch Linux / EndeavourOS, KDE Plasma 6 (Wayland), yay.
# Run it in a terminal inside the Plasma session: it asks for the sudo password.
set -euo pipefail

repo=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

step() {
    printf '\n\033[1m==> %s\033[0m\n' "$*"
}

in_plasma() {
    qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation >/dev/null 2>&1
}

# Whether the running KWin is the installed one, so freshly built plugins may be loaded.
kwin_current() {
    local running installed
    running=$(qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation 2>/dev/null | sed -n 's/^KWin version: //p' || true)
    installed=$(pacman -Q kwin | awk '{print $2}')
    [[ -n $running && $running == "${installed%-*}" ]]
}

install_time() {
    LC_ALL=C pacman -Qi "$1" 2>/dev/null | sed -n 's/^Install Date *: //p' | xargs -r -I{} date -d {} +%s
}

# Links a file of this repository into place, keeping a backup of what was there.
link() {
    local source=$repo/$1 target=$2
    mkdir -p "$(dirname "$target")"
    if [[ -e $target && ! -L $target ]]; then
        mv "$target" "$target.bak"
    fi
    ln -sfn "$source" "$target"
}

install_packages() {
    step "Packages"
    sudo pacman -S --needed --noconfirm base-devel git cmake extra-cmake-modules python vulkan-headers
    if ! command -v yay >/dev/null; then
        echo "yay is needed for the AUR package inputactions-kwin: https://github.com/Jguer/yay" >&2
        exit 1
    fi
    # The plugin must be built against the installed KWin, so rebuild it after a KWin update.
    local mode=--needed
    if pacman -Q inputactions-kwin >/dev/null 2>&1 \
            && (( $(install_time inputactions-kwin) < $(install_time kwin) )); then
        mode=--rebuild
    fi
    yay -S "$mode" --noconfirm --answerclean None --answerdiff None inputactions-kwin
}

setup_gestures() {
    step "Touchpad gestures (InputActions)"
    link inputactions/config.yaml ~/.config/inputactions/config.yaml
    link inputactions/swipe.sh ~/.config/inputactions/swipe.sh
    kwriteconfig6 --file kwinrc --group Plugins --key kwin_gesturesEnabled true
    if kwin_current; then
        qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect kwin_gestures >/dev/null
    fi
}

build_overview() {
    step "Overview with reorderable desktops, Spaces"
    "$repo/kwin-overview-reorder/build.sh"
}

setup_touchpads() {
    local device path property
    for device in $(qdbus6 org.kde.KWin /org/kde/KWin/InputDevice org.freedesktop.DBus.Properties.Get \
            org.kde.KWin.InputDeviceManager devicesSysNames); do
        path=/org/kde/KWin/InputDevice/$device
        [[ $(busctl --user get-property org.kde.KWin "$path" org.kde.KWin.InputDevice touchpad) == "b true" ]] || continue
        # KWin saves these to kcminputrc itself.
        for property in naturalScroll scrollTwoFinger tapToClick clickMethodClickfinger; do
            busctl --user set-property org.kde.KWin "$path" org.kde.KWin.InputDevice "$property" b true
        done
    done
}

apply_settings() {
    step "KDE settings"
    # Each screen switches desktops on its own; one row for left/right swipes.
    kwriteconfig6 --file kwinrc --group Windows --key PerOutputVirtualDesktops true
    kwriteconfig6 --file kwinrc --group Desktops --key Rows 1

    if ! in_plasma; then
        echo "Not in a Plasma session: the touchpad is set up on the next run inside Plasma."
        return
    fi
    busctl --user set-property org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager rows u 1
    qdbus6 org.kde.KWin /KWin reconfigure
    setup_touchpads
}

# The screen locks after 30 idle minutes. On AC the screen also turns off and
# the laptop sleeps after 30 minutes; battery settings stay as they are.
apply_power() {
    step "Screen lock and power"
    kwriteconfig6 --file kscreenlockerrc --group Daemon --key Timeout 30
    kwriteconfig6 --file powerdevilrc --group AC --group Display --key TurnOffDisplayIdleTimeoutSec 1800
    kwriteconfig6 --file powerdevilrc --group AC --group SuspendAndShutdown --key AutoSuspendIdleTimeoutSec 1800
    if in_plasma; then
        qdbus6 org.freedesktop.ScreenSaver /ScreenSaver org.kde.screensaver.configure
        qdbus6 org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement \
            org.kde.Solid.PowerManagement.reparseConfiguration >/dev/null 2>&1 || true
    fi
}

setup_guard() {
    step "Protection against KWin updates"
    local guard=$repo/kwin-overview-reorder/kwin-plugin-guard.sh
    local dropin=~/.config/systemd/user/plasma-kwin_wayland.service.d/kwin-plugin-guard.conf
    mkdir -p "$(dirname "$dropin")" ~/.config/autostart
    printf '[Service]\nExecStartPre=-%s\n' "$guard" > "$dropin"
    cat > ~/.config/autostart/kwin-plugin-guard-notify.desktop <<EOF
[Desktop Entry]
Type=Application
Name=KWin plugin rebuild reminder
Exec=$guard --notify
NoDisplay=true
EOF
    systemctl --user daemon-reload
}

main() {
    local power=false arg
    for arg in "$@"; do
        case $arg in
            --power) power=true ;;
            *)
                echo "Usage: $0 [--power]" >&2
                exit 1
                ;;
        esac
    done
    if [[ $EUID -eq 0 ]]; then
        echo "Run it as your user, not as root." >&2
        exit 1
    fi
    install_packages
    setup_gestures
    build_overview
    apply_settings
    if $power; then
        apply_power
    fi
    setup_guard
    step "Done"
    if ! kwin_current; then
        echo "Log out and back in to finish."
    fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
