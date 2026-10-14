/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "spaces.h"

#include "core/output.h"
#include "effect/effecthandler.h"
#include "effect/effectwindow.h"
#include "virtualdesktops.h"

#include <KConfigGroup>
#include <KGlobalAccel>

#include <QAction>

#include <algorithm>

namespace KWin
{

static KConfigGroup spacesConfig()
{
    return KConfigGroup(effects->config(), QStringLiteral("Effect-overviewreorder")).group(QStringLiteral("Spaces"));
}

// Desktops of maximized windows ("Spaces", made by spaces-script) are named
// with this invisible prefix. They belong to the screen their window is on.
static bool isWindowSpace(const VirtualDesktop *desktop)
{
    return desktop->name().startsWith(QChar(0x2060));
}

// Windows that make a desktop in use on the screen they are on.
static bool countsForDesktop(const EffectWindow *window, VirtualDesktop *desktop)
{
    return window->isNormalWindow() && !window->isDeleted() && !window->isOnAllDesktops()
        && !window->isSkipSwitcher() && window->isOnDesktop(desktop);
}

// The screens among `names` that are connected right now.
static QStringList connectedScreens(const QStringList &names)
{
    QStringList connected;
    const auto screens = effects->screens();
    for (const LogicalOutput *screen : screens) {
        if (names.contains(screen->name())) {
            connected.append(screen->name());
        }
    }
    return connected;
}

// While screens come and go, KWin moves windows and picks desktops for screens
// on its own; that says nothing about where the user works.
static constexpr qint64 ScreenChangeGraceMs = 3000;

SpacesOverviewEffect::SpacesOverviewEffect()
{
    m_screensChanged.start();

    const KConfigGroup config = spacesConfig();
    const auto desktops = effects->desktops();
    for (VirtualDesktop *desktop : desktops) {
        const QStringList screens = config.readEntry(desktop->id(), QStringList());
        if (!screens.isEmpty()) {
            m_screensByDesktop.insert(desktop->id(), screens);
        }
    }
    // Whatever a screen shows right now is in use there.
    const auto screens = effects->screens();
    if (screens.size() > 1) {
        for (LogicalOutput *screen : screens) {
            VirtualDesktop *desktop = effects->currentDesktop(screen);
            if (desktop && !isWindowSpace(desktop)) {
                claim(desktop, screen);
            }
        }
    }
    save();

    connect(effects, &EffectsHandler::desktopChanged, this,
            [this](VirtualDesktop *, VirtualDesktop *desktop, EffectWindow *, LogicalOutput *screen) {
                // Passing through another screen's desktop doesn't make it this screen's.
                if (canClaim(desktop, screen)
                    && (hasWindowsOn(desktop, screen) || !hasWindowsElsewhere(desktop, screen))) {
                    if (claim(desktop, screen)) {
                        save();
                    }
                }
                notifyChanged();
            });
    const auto screensChanged = [this]() {
        m_screensChanged.restart();
        notifyChanged();
    };
    connect(effects, &EffectsHandler::screenAdded, this, screensChanged);
    connect(effects, &EffectsHandler::screenRemoved, this, screensChanged);
    connect(effects, &EffectsHandler::desktopMoved, this, &SpacesOverviewEffect::notifyChanged);
    connect(effects, &EffectsHandler::desktopRemoved, this, [this](VirtualDesktop *desktop) {
        if (m_screensByDesktop.remove(desktop->id())) {
            save();
        }
        notifyChanged();
    });
    connect(effects, &EffectsHandler::desktopAdded, this, &SpacesOverviewEffect::notifyChanged);
    connect(effects, &EffectsHandler::windowAdded, this, &SpacesOverviewEffect::notifyChanged);
    connect(effects, &EffectsHandler::windowClosed, this, &SpacesOverviewEffect::notifyChanged);
    connect(effects, &EffectsHandler::stackingOrderChanged, this, &SpacesOverviewEffect::notifyChanged);

    const auto addSwitchAction = [this](const QString &name, int step) {
        auto action = new QAction(this);
        action->setObjectName(name);
        action->setText(name);
        KGlobalAccel::self()->setGlobalShortcut(action, QList<QKeySequence>());
        connect(action, &QAction::triggered, this, [this, step]() {
            switchDesktop(step);
        });
    };
    addSwitchAction(QStringLiteral("Switch to Next Desktop on Screen"), 1);
    addSwitchAction(QStringLiteral("Switch to Previous Desktop on Screen"), -1);
}

int SpacesOverviewEffect::spacesRevision() const
{
    return m_revision;
}

bool SpacesOverviewEffect::isDesktopOnScreen(VirtualDesktop *desktop, LogicalOutput *screen) const
{
    if (!desktop || !screen || effects->currentDesktop(screen) == desktop) {
        return true;
    }
    if (isWindowSpace(desktop)) {
        return hasWindowsOn(desktop, screen);
    }
    // The desktops of a disconnected screen are offered on the remaining ones.
    const QStringList owners = connectedScreens(m_screensByDesktop.value(desktop->id()));
    if (owners.contains(screen->name()) || hasWindowsOn(desktop, screen)) {
        return true;
    }
    if (!owners.isEmpty() || hasWindowsElsewhere(desktop, screen)) {
        return false;
    }
    // An unused desktop is offered everywhere, unless another screen shows it.
    const auto screens = effects->screens();
    return std::none_of(screens.cbegin(), screens.cend(), [&](LogicalOutput *other) {
        return other != screen && effects->currentDesktop(other) == desktop;
    });
}

void SpacesOverviewEffect::assignDesktop(VirtualDesktop *desktop, LogicalOutput *screen)
{
    if (!desktop || !screen) {
        return;
    }
    m_screensByDesktop.insert(desktop->id(), {screen->name()});
    save();
    notifyChanged();
}

bool SpacesOverviewEffect::hasWindowsOn(VirtualDesktop *desktop, LogicalOutput *screen) const
{
    const auto windows = effects->stackingOrder();
    return std::any_of(windows.cbegin(), windows.cend(), [&](const EffectWindow *window) {
        return countsForDesktop(window, desktop) && window->screen() == screen;
    });
}

bool SpacesOverviewEffect::hasWindowsElsewhere(VirtualDesktop *desktop, LogicalOutput *screen) const
{
    const auto windows = effects->stackingOrder();
    return std::any_of(windows.cbegin(), windows.cend(), [&](const EffectWindow *window) {
        return countsForDesktop(window, desktop) && window->screen() != screen;
    });
}

// Whether switching to the desktop on that screen means the user works with it
// there: not while screens come and go, not with a single screen (everything is
// on it then), and not for a desktop of a screen that is disconnected right now.
bool SpacesOverviewEffect::canClaim(VirtualDesktop *desktop, LogicalOutput *screen) const
{
    if (!desktop || !screen || isWindowSpace(desktop) || effects->screens().size() < 2
        || !m_screensChanged.hasExpired(ScreenChangeGraceMs)) {
        return false;
    }
    const QStringList owners = m_screensByDesktop.value(desktop->id());
    return owners.isEmpty() || !connectedScreens(owners).isEmpty();
}

bool SpacesOverviewEffect::claim(VirtualDesktop *desktop, LogicalOutput *screen)
{
    if (!desktop || !screen) {
        return false;
    }
    QStringList &owners = m_screensByDesktop[desktop->id()];
    if (owners.contains(screen->name())) {
        return false;
    }
    owners.append(screen->name());
    return true;
}

void SpacesOverviewEffect::switchDesktop(int step)
{
    LogicalOutput *screen = effects->activeScreen();
    QList<VirtualDesktop *> desktops;
    const auto allDesktops = effects->desktops();
    for (VirtualDesktop *desktop : allDesktops) {
        if (isDesktopOnScreen(desktop, screen)) {
            desktops.append(desktop);
        }
    }
    if (desktops.isEmpty()) {
        return;
    }
    int index = desktops.indexOf(effects->currentDesktop(screen)) + step;
    if (effects->optionRollOverDesktops()) {
        index = (index + desktops.size()) % desktops.size();
    }
    if (index >= 0 && index < desktops.size()) {
        effects->setCurrentDesktop(desktops[index], screen);
    }
}

void SpacesOverviewEffect::save()
{
    KConfigGroup config = spacesConfig();
    const QStringList keys = config.keyList();
    for (const QString &key : keys) {
        if (!m_screensByDesktop.contains(key)) {
            config.deleteEntry(key);
        }
    }
    for (auto it = m_screensByDesktop.cbegin(); it != m_screensByDesktop.cend(); ++it) {
        config.writeEntry(it.key(), it.value());
    }
    config.sync();
}

void SpacesOverviewEffect::notifyChanged()
{
    ++m_revision;
    Q_EMIT spacesChanged();
}

} // namespace KWin

#include "moc_spaces.cpp"
