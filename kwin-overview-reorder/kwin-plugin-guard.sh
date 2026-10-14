#!/bin/bash
# Keeps KWin plugins built against an older KWin from being loaded.
#
# Runs right before KWin starts (systemd drop-in for plasma-kwin_wayland.service):
# a plugin whose package was installed before the current KWin package is
# switched off (and the stock effect it replaces switched back on) until it is
# rebuilt. With --notify (run at login) it tells which packages need a rebuild.

state=${XDG_STATE_HOME:-$HOME/.local/state}/kwin-plugin-guard
repo=$(dirname "$(dirname "$(readlink -f "$0")")")

# Each build of the reorderable Overview has its own plugin id.
overview=$(basename /usr/lib/qt6/plugins/kwin/effects/plugins/overviewreorder_*.so .so)

# plugin id | package | stock effect it replaces
plugins=(
    "$overview|kwin-overview-reorder|overview"
    "kwin_gestures|inputactions-kwin|"
)

install_time() {
    local date
    date=$(LC_ALL=C pacman -Qi "$1" 2>/dev/null | sed -n 's/^Install Date *: //p')
    [[ -n $date ]] && date -d "$date" +%s
}

set_enabled() {
    kwriteconfig6 --file kwinrc --group Plugins --key "${1}Enabled" "$2"
}

if [[ $1 == --notify ]]; then
    packages=""
    for entry in "${plugins[@]}"; do
        IFS='|' read -r plugin package stock <<< "$entry"
        [[ -e $state/$plugin ]] && packages+=" $package"
    done
    [[ -n $packages ]] && notify-send --app-name=KWin --icon=dialog-warning "KWin was updated" \
        "Switched off until rebuilt:$packages. Run $repo/install.sh, then log out and back in."
    exit 0
fi

mkdir -p "$state"
kwin_time=$(install_time kwin) || exit 0

for entry in "${plugins[@]}"; do
    IFS='|' read -r plugin package stock <<< "$entry"
    time=$(install_time "$package") || continue
    if (( time < kwin_time )); then
        [[ -e $state/$plugin ]] && continue
        [[ $(kreadconfig6 --file kwinrc --group Plugins --key "${plugin}Enabled") == true ]] || continue
        set_enabled "$plugin" false
        [[ -n $stock ]] && set_enabled "$stock" true
        touch "$state/$plugin"
    elif [[ -e $state/$plugin ]]; then
        set_enabled "$plugin" true
        [[ -n $stock ]] && set_enabled "$stock" false
        rm "$state/$plugin"
    fi
done
