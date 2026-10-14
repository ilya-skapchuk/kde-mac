#pragma once

#include "overvieweffect.h"

#include <QElapsedTimer>
#include <QHash>
#include <QStringList>

namespace KWin
{

/*
 * The Overview effect with a separate list of virtual desktops per screen,
 * like Spaces on macOS. KWin keeps a single global list, so a desktop counts
 * as a screen's desktop when it is in use there: it was switched to on that
 * screen (remembered in kwinrc), or it holds windows on that screen. A desktop
 * nobody has used yet is offered on every screen. The Space of a maximized
 * window (see spaces-script) goes wherever that window is.
 */
class SpacesOverviewEffect : public OverviewReorderEffect
{
    Q_OBJECT
    Q_PROPERTY(int spacesRevision READ spacesRevision NOTIFY spacesChanged)

public:
    SpacesOverviewEffect();

    int spacesRevision() const;

    Q_INVOKABLE bool isDesktopOnScreen(KWin::VirtualDesktop *desktop, KWin::LogicalOutput *screen) const;
    // Makes the desktop belong to this screen only.
    Q_INVOKABLE void assignDesktop(KWin::VirtualDesktop *desktop, KWin::LogicalOutput *screen);

Q_SIGNALS:
    void spacesChanged();

private:
    bool hasWindowsOn(VirtualDesktop *desktop, LogicalOutput *screen) const;
    bool hasWindowsElsewhere(VirtualDesktop *desktop, LogicalOutput *screen) const;
    bool canClaim(VirtualDesktop *desktop, LogicalOutput *screen) const;
    // Returns whether the desktop wasn't in use on that screen before.
    bool claim(VirtualDesktop *desktop, LogicalOutput *screen);
    void switchDesktop(int step);
    void save();
    void notifyChanged();

    QHash<QString, QStringList> m_screensByDesktop; // desktop id -> screen names
    QElapsedTimer m_screensChanged;
    int m_revision = 0;
};

} // namespace KWin
