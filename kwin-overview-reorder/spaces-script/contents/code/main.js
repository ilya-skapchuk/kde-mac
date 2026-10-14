// Spaces, macOS style: a maximized or fullscreen window gets a virtual desktop
// of its own ("Space"), inserted right after the desktop it came from and named
// after the window. Ordinary desktops ("Desktop 1", ...) hold all other windows.
// When the window is restored, minimized or closed, it goes back to that
// desktop and its Space is removed.
//
// Space names start with an invisible marker; the reorderable Overview uses it
// to tell Spaces from ordinary desktops.

const MARKER = "\u2060";
const MAXIMIZE_FULL = 3;
// While the screen slides over to a new Space the window stays visible on all
// desktops, so it doesn't vanish halfway (browsers also leave fullscreen when hidden).
const SWITCH_ANIMATION_MS = 600;
// While screens come and go, KWin moves windows between them on its own. That's
// no reason to switch desktops; windows are checked once things have settled.
const SCREEN_CHANGE_GRACE_MS = 3000;
let screensChangedAt = 0;
// KWin may restore and re-maximize a window in one go (e.g. when moving it to
// another screen); only the state a window settles in counts.
const SETTLE_MS = 250;

const EXCLUDED_CLASSES = [
    "kwin", "kwin_wayland", "plasmashell", "org.kde.plasmashell", "krunner", "org.kde.krunner",
    "ksmserver", "ksmserver-logout-greeter", "kscreenlocker_greet", "ksplashqml",
    "spectacle", "org.kde.spectacle", "flameshot", "org.flameshot.flameshot",
    "yakuake", "org.kde.yakuake", "xwaylandvideobridge", "xdg-desktop-portal-kde",
];

// window id -> { window, space: desktop id, home: desktop id, busy: bool }
const records = new Map();
// window id -> { follow: bool } for windows waiting to settle
const pending = new Map();
// QTimers are kept referenced until they fire.
const timers = new Set();

function windowId(window) {
    return String(window.internalId);
}

function isSpace(desktop) {
    return desktop.name.startsWith(MARKER);
}

function desktopById(id) {
    return workspace.desktops.find(desktop => desktop.id === id) || null;
}

function indexOf(desktop) {
    return workspace.desktops.findIndex(other => other.id === desktop.id);
}

function screenOf(window) {
    return window.output || workspace.activeScreen;
}

function screensSettling() {
    return Date.now() - screensChangedAt < SCREEN_CHANGE_GRACE_MS;
}

function later(ms, callback) {
    const timer = new QTimer();
    timer.singleShot = true;
    timer.interval = ms;
    timer.timeout.connect(() => {
        timers.delete(timer);
        callback();
    });
    timers.add(timer);
    timer.start();
}

function manageable(window) {
    const cls = String(window.resourceClass || "").toLowerCase();
    const name = String(window.resourceName || "").toLowerCase();
    return window.normalWindow && !window.deleted && !window.skipTaskbar && !window.popupWindow
        && !EXCLUDED_CLASSES.includes(cls) && !EXCLUDED_CLASSES.includes(name);
}

function wantsSpace(window) {
    return manageable(window) && !window.minimized
        && (window.fullScreen || window.maximizeMode === MAXIMIZE_FULL);
}

// Other windows of the app owning a Space (or without any identity, like
// Chromium's picture-in-picture) may stay on it.
function isCompanion(window, owner) {
    const cls = String(window.resourceClass || "");
    return !cls || cls === String(owner.resourceClass) || (window.pid > 0 && window.pid === owner.pid);
}

function windowsOn(desktop, except) {
    return workspace.windowList().filter(window => manageable(window) && !window.onAllDesktops
        && (!except || windowId(window) !== windowId(except))
        && window.desktops.some(other => other.id === desktop.id));
}

function recordOfSpace(desktop) {
    for (const record of records.values()) {
        if (record.space === desktop.id) {
            return record;
        }
    }
    return null;
}

// The ordinary desktop a Space returns to: the recorded one while it exists,
// otherwise the nearest ordinary desktop to the left, then to the right.
function homeFor(record, space) {
    const home = record && desktopById(record.home);
    if (home && !isSpace(home)) {
        return home;
    }
    const desktops = workspace.desktops;
    const index = space ? indexOf(space) : 0;
    for (let i = index - 1; i >= 0; --i) {
        if (!isSpace(desktops[i])) {
            return desktops[i];
        }
    }
    for (let i = index + 1; i < desktops.length; ++i) {
        if (!isSpace(desktops[i])) {
            return desktops[i];
        }
    }
    return desktops[0];
}

function enterSpace(window) {
    const id = windowId(window);
    const screen = screenOf(window);
    const current = window.desktops.length === 1 ? window.desktops[0] : workspace.currentDesktopForScreen(screen);
    const home = isSpace(current) ? homeFor(recordOfSpace(current), current) : current;

    const position = indexOf(current) + 1;
    workspace.createDesktop(position, MARKER + window.caption);
    const space = workspace.desktops[position];
    const record = { window: window, space: space.id, home: home.id, busy: true };
    records.set(id, record);

    window.onAllDesktops = true;
    workspace.setCurrentDesktopForScreen(space, screen);
    later(SWITCH_ANIMATION_MS, () => {
        record.busy = false;
        const target = desktopById(record.space);
        if (records.get(id) !== record || window.deleted || !target) {
            return;
        }
        window.desktops = [target];
        // In case it changed state or screen during the animation.
        evaluate(window);
        followScreen(window);
    });
}

// Sends what is left on a Space home, moves screens showing it to `home` and removes it.
function closeSpace(space, home, except) {
    if (!space) {
        return;
    }
    windowsOn(space, except).forEach(window => {
        if (!records.has(windowId(window))) {
            window.desktops = [home];
        }
    });
    workspace.screens.forEach(screen => {
        if (workspace.currentDesktopForScreen(screen).id === space.id) {
            workspace.setCurrentDesktopForScreen(home, screen);
        }
    });
    if (windowsOn(space, except).length === 0) {
        workspace.removeDesktop(space);
    }
}

function leaveSpace(window) {
    const id = windowId(window);
    const record = records.get(id);
    records.delete(id);
    const space = desktopById(record.space);
    const home = homeFor(record, space);
    if (!window.deleted) {
        window.desktops = [home];
    }
    closeSpace(space, home, window);
}

function evaluate(window) {
    const id = windowId(window);
    const record = records.get(id);
    if ((record && record.busy) || window.move || window.resize || screensSettling()) {
        return;
    }
    const wants = wantsSpace(window);
    if (!record) {
        if (wants && !window.onAllDesktops) {
            enterSpace(window);
        }
        return;
    }
    if (!wants) {
        leaveSpace(window);
        return;
    }
    const space = desktopById(record.space);
    if (window.onAllDesktops) {
        // Pinned to all desktops by the user: it no longer needs a Space.
        records.delete(id);
        closeSpace(space, homeFor(record, space), window);
        return;
    }
    if (!space) {
        // Its Space was deleted (e.g. in the Overview): leave fullscreen, like on macOS.
        records.delete(id);
        window.fullScreen = false;
        window.setMaximize(false, false);
        window.desktops = [homeFor(record, null)];
        return;
    }
    const onSpace = window.desktops.length === 1 && window.desktops[0].id === space.id;
    if (!onSpace) {
        // Moved to another desktop: its Space moves along.
        records.delete(id);
        closeSpace(space, homeFor(record, space), window);
        enterSpace(window);
    }
}

// The Space travels with its window to another screen.
function followScreen(window) {
    const record = records.get(windowId(window));
    const space = record && desktopById(record.space);
    if (!space || record.busy || window.move || window.resize || screensSettling()) {
        return;
    }
    const screen = screenOf(window);
    workspace.screens.forEach(other => {
        if (other.name !== screen.name && workspace.currentDesktopForScreen(other).id === space.id) {
            workspace.setCurrentDesktopForScreen(homeFor(record, space), other);
        }
    });
    workspace.setCurrentDesktopForScreen(space, screen);
}

function rename(window) {
    const record = records.get(windowId(window));
    const space = record && desktopById(record.space);
    if (space && space.name !== MARKER + window.caption) {
        space.name = MARKER + window.caption;
    }
}

function closed(window) {
    const id = windowId(window);
    const record = records.get(id);
    if (!record) {
        return;
    }
    records.delete(id);
    const space = desktopById(record.space);
    closeSpace(space, homeFor(record, space), window);
}

// Checks the window once its state has settled; `follow` also takes its Space
// along to the screen it is on.
function schedule(window, follow) {
    const id = windowId(window);
    const entry = pending.get(id);
    if (entry) {
        entry.follow = entry.follow || follow;
        return;
    }
    pending.set(id, { follow: follow });
    later(SETTLE_MS, () => {
        const settled = pending.get(id);
        pending.delete(id);
        if (window.deleted) {
            return;
        }
        evaluate(window);
        if (settled.follow) {
            followScreen(window);
        }
    });
}

function attach(window) {
    window.maximizedChanged.connect(() => schedule(window, false));
    window.fullScreenChanged.connect(() => schedule(window, false));
    window.minimizedChanged.connect(() => schedule(window, false));
    window.desktopsChanged.connect(() => schedule(window, false));
    window.outputChanged.connect(() => schedule(window, true));
    window.interactiveMoveResizeFinished.connect(() => schedule(window, true));
    window.captionChanged.connect(() => rename(window));
    window.closed.connect(() => closed(window));
}

// A new window of another app opened on a Space goes to the Space's home
// desktop, and its screen follows it.
function windowAdded(window) {
    attach(window);
    if (wantsSpace(window)) {
        evaluate(window);
        return;
    }
    if (!manageable(window) || window.transient || window.onAllDesktops || window.desktops.length !== 1) {
        return;
    }
    const space = window.desktops[0];
    const record = isSpace(space) ? recordOfSpace(space) : null;
    if (!record || isCompanion(window, record.window)) {
        return;
    }
    const home = homeFor(record, space);
    window.desktops = [home];
    workspace.setCurrentDesktopForScreen(home, screenOf(window));
    workspace.activeWindow = window;
}

function start() {
    const windows = workspace.windowList();
    windows.forEach(attach);

    // Adopt Spaces that outlived a restart of this script, or were made by MACsimize6.
    windows.forEach(window => {
        if (!wantsSpace(window) || window.onAllDesktops || window.desktops.length !== 1) {
            return;
        }
        const desktop = window.desktops[0];
        if (windowsOn(desktop, window).length === 0 && (isSpace(desktop) || desktop.name === window.caption)) {
            records.set(windowId(window), { window: window, space: desktop.id, home: homeFor(null, desktop).id, busy: false });
            desktop.name = MARKER + window.caption;
        }
    });
    // Remove Spaces whose window is gone.
    workspace.desktops.filter(desktop => isSpace(desktop) && !recordOfSpace(desktop))
        .forEach(desktop => closeSpace(desktop, homeFor(null, desktop), null));
    // Maximized windows on ordinary desktops get their Spaces now.
    windows.forEach(evaluate);

    workspace.windowAdded.connect(windowAdded);
    workspace.windowRemoved.connect(closed);
    workspace.screensChanged.connect(() => {
        screensChangedAt = Date.now();
        later(SCREEN_CHANGE_GRACE_MS + 100, () => workspace.windowList().forEach(evaluate));
    });
}

start();
