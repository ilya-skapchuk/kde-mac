#!/bin/bash
# Builds the reorderable Overview for the installed KWin version, installs it
# and switches to it. Run it again after every KWin update.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

makepkg --force --cleanbuild --noconfirm
package=$(makepkg --packagelist | grep -v -- '-debug-')
# In a terminal ask for the password there, otherwise in a desktop dialog.
if [[ -t 0 ]]; then
    sudo pacman -U --noconfirm "$package"
else
    pkexec pacman -U --noconfirm "$package"
fi
rm -rf src pkg

# Every build has its own plugin id (see CMakeLists.txt): enable only the new one.
plugin=$(basename /usr/lib/qt6/plugins/kwin/effects/plugins/overviewreorder_*.so .so)
for old in $(sed -n '/^\[Plugins\]/,/^\[/s/^\(overviewreorder[^=]*\)Enabled=.*/\1/p' ~/.config/kwinrc); do
    kwriteconfig6 --file kwinrc --group Plugins --key "${old}Enabled" --delete
done
kwriteconfig6 --file kwinrc --group Plugins --key "${plugin}Enabled" true
kwriteconfig6 --file kwinrc --group Plugins --key overviewEnabled false
rm -f "${XDG_STATE_HOME:-$HOME/.local/state}"/kwin-plugin-guard/overviewreorder*

# The Spaces script is JavaScript and needs no build; keep the installed copy current.
kpackagetool6 --type=KWin/Script --upgrade spaces-script >/dev/null 2>&1 \
    || kpackagetool6 --type=KWin/Script --install spaces-script >/dev/null
kwriteconfig6 --file kwinrc --group Plugins --key macspacesEnabled true

# Loading a plugin built for another KWin version into the running one is unsafe.
running=$(qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation 2>/dev/null | sed -n 's/^KWin version: //p' || true)
installed=$(pacman -Q kwin | awk '{print $2}')
if [[ -z $running ]]; then
    echo "Done. It will be active in the next Plasma session."
elif [[ $running == "${installed%-*}" ]]; then
    for effect in overview $(qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadedEffects | grep '^overviewreorder'); do
        qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "$effect"
    done
    qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "$plugin" >/dev/null
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript macspaces >/dev/null
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start
    echo "Done: the reorderable Overview is active."
else
    echo "Done. KWin $running is still running (installed: $installed): log out and back in to use it."
fi
