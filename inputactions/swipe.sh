#!/bin/bash
# Three-finger swipes (called by InputActions), macOS-like:
#   up    - bring back windows hidden by "show desktop", otherwise open Overview,
#           then Grid View
#   down  - close Overview (Grid View -> Overview first), otherwise hide all windows
#   left  - next desktop of the screen under the cursor
#   right - previous desktop of the screen under the cursor

kwin_shortcut() {
    qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "$1"
}

# The reorderable Overview's plugin id changes with every build (overviewreorder_*).
overview_active() {
    qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.activeEffects | grep -q -e '^overview$' -e '^overviewreorder'
}

spaces_loaded() {
    qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadedEffects | grep -q '^overviewreorder'
}

showing_desktop() {
    [ "$(qdbus6 org.kde.KWin /KWin org.kde.KWin.showingDesktop)" = true ]
}

# Per-screen desktop lists come from the reorderable Overview; without it,
# fall back to KWin's global list.
switch_desktop() {
    if spaces_loaded; then
        kwin_shortcut "Switch to $1 Desktop on Screen"
    else
        kwin_shortcut "Switch One Desktop to the $2"
    fi
}

case "$1" in
    up)
        if showing_desktop; then
            kwin_shortcut "Show Desktop"
        elif overview_active; then
            kwin_shortcut "Cycle Overview"
        else
            kwin_shortcut Overview
        fi
        ;;
    down)
        if overview_active; then
            kwin_shortcut "Cycle Overview Opposite"
        elif ! showing_desktop; then
            # Not the D-Bus showDesktop(true) call: KWin reverts it as soon as the caller exits
            kwin_shortcut "Show Desktop"
        fi
        ;;
    left)
        # Fingers moving left bring in the desktop on the right, as on macOS.
        switch_desktop Next Right
        ;;
    right)
        switch_desktop Previous Left
        ;;
    *)
        echo "usage: $0 up|down|left|right" >&2
        exit 1
        ;;
esac
