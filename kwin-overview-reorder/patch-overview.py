#!/usr/bin/env python3
"""Turn KWin's Overview effect sources into the "overviewreorder" plugin.

Usage: patch-overview.py <kwin sources>/src/plugins/overview <output dir>

The effect is renamed so it can't clash with the built-in Overview, the top
bar and the desktop views of each screen list only that screen's desktops
(SpacesOverviewEffect in spaces.h), and the desktops in the top bar can be
reordered by dragging: the others make room as a thumbnail is dragged over them. Every edit must match exactly once,
so an incompatible KWin version fails the build loudly instead of producing a
broken effect.
"""

import shutil
import sys
from pathlib import Path


def edit(path, old, new):
    text = path.read_text()
    found = text.count(old)
    if found != 1:
        sys.exit(f"{path.name}: expected exactly one match, found {found}:\n{old}")
    path.write_text(text.replace(old, new))


def rename(path, old, new):
    text = path.read_text()
    if old not in text:
        sys.exit(f"{path.name}: '{old}' not found")
    path.write_text(text.replace(old, new))


src, out = Path(sys.argv[1]), Path(sys.argv[2])
(out / "qml").mkdir(parents=True)

for name in ("main.cpp", "overvieweffect.cpp", "overvieweffect.h",
             "overviewconfig.kcfg", "overviewconfig.kcfgc"):
    shutil.copy(src / name, out / name)
for name in ("Main.qml", "DesktopBar.qml", "DesktopView.qml"):
    # Plasma 6.8 moved the QML files out of the qml/ subdirectory.
    qml = src / "qml" / name
    shutil.copy(qml if qml.exists() else src / name, out / "qml" / name)

# --- C++: a separate plugin with its own class, config class and QML module.
for name in ("main.cpp", "overvieweffect.cpp", "overvieweffect.h"):
    rename(out / name, "OverviewEffect", "OverviewReorderEffect")
rename(out / "overvieweffect.cpp", "OverviewConfig", "OverviewReorderConfig")
edit(out / "overviewconfig.kcfgc", "ClassName=OverviewConfig", "ClassName=OverviewReorderConfig")
edit(out / "overvieweffect.cpp",
     'QStringLiteral("org.kde.kwin.overview")',
     'QStringLiteral(OVERVIEW_QML_URI)')
edit(out / "main.cpp", '"metadata.json.stripped"', '"metadata.json"')
edit(out / "main.cpp", '#include "overvieweffect.h"', '#include "spaces.h"')
edit(out / "main.cpp", "KWIN_EFFECT_FACTORY_SUPPORTED(OverviewReorderEffect,",
     "KWIN_EFFECT_FACTORY_SUPPORTED(SpacesOverviewEffect,")

# --- DesktopBar.qml
bar = out / "qml" / "DesktopBar.qml"

edit(bar, "\n    Flickable {\n", """
    // The desktop being dragged follows the pointer, while its place in the bar
    // stays empty and moves along as the other desktops make room.
    ShaderEffectSource {
        id: dragGhost
        property Item card: null
        property point grabOffset
        z: 1
        visible: card !== null
        sourceItem: card
        hideSource: true
        width: bar.desktopWidth
        height: bar.desktopHeight
    }

    function dragDesktop(dragged, scenePosition) {
        const position = bar.mapFromItem(null, scenePosition.x, scenePosition.y);
        dragGhost.x = position.x - dragGhost.grabOffset.x;
        dragGhost.y = position.y - dragGhost.grabOffset.y;

        // Go by the slot under the pointer rather than by the thumbnails'
        // animated positions, so that they don't swap back and forth.
        const cards = [];
        for (let i = 0; i < desktopRepeater.count; ++i) {
            const card = desktopRepeater.itemAt(i);
            if (card && card.visible) {
                cards.push(card);
            }
        }
        const inGrid = desktopGrid.mapFromItem(null, scenePosition.x, scenePosition.y);
        const slot = verticalDesktopBar
            ? Math.floor(inGrid.y / (bar.columnHeight + desktopGrid.spacing))
            : Math.floor(inGrid.x / (bar.desktopWidth + desktopGrid.spacing));
        const target = cards[Math.max(0, Math.min(cards.length - 1, slot))];
        if (target && target !== dragged) {
            KWinComponents.Workspace.moveDesktop(dragged.desktop, target.desktop.x11DesktopNumber - 1);
        }
    }

    // "Desktop N", counting the ordinary desktops of this screen (the Spaces
    // of maximized windows are named with a leading U+2060).
    function nextDesktopName() {
        let count = 0;
        for (let i = 0; i < desktopRepeater.count; ++i) {
            const card = desktopRepeater.itemAt(i);
            if (card && card.visible && !card.desktop.name.startsWith("\\u2060")) {
                ++count;
            }
        }
        return i18nd("kwin", "Desktop %1", count + 1);
    }

    Flickable {
""")

edit(bar, "        Grid {\n", "        Grid {\n            id: desktopGrid\n")
edit(bar, "            columns: verticalDesktopBar ? 1 : desktopCount + 1\n", """\
            columns: verticalDesktopBar ? 1 : desktopCount + 1

            move: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.OutCubic
                }
            }
""")

edit(bar, """
                Column {
                    id: delegate
""", """
                Column {
                    id: delegate
                    visible: {
                        effect.spacesRevision;
                        return effect.isDesktopOnScreen(delegate.desktop, targetScreen);
                    }
""")

edit(bar, "onClicked: desktopModel.create(desktopModel.rowCount())",
     "onClicked: effect.assignDesktop(desktopModel.create(desktopModel.rowCount(), bar.nextDesktopName()), targetScreen)")

edit(bar, """
                        HoverHandler {
                            id: thumbnailHover
                        }
""", """
                        DragHandler {
                            id: desktopDragHandler
                            target: null
                            acceptedButtons: Qt.LeftButton
                            grabPermissions: PointerHandler.CanTakeOverFromAnything
                            onActiveChanged: {
                                if (active) {
                                    const press = parent.mapFromItem(null, centroid.scenePressPosition.x, centroid.scenePressPosition.y);
                                    dragGhost.grabOffset = Qt.point(press.x, press.y);
                                    dragGhost.card = parent;
                                    bar.dragDesktop(delegate, centroid.scenePosition);
                                } else {
                                    dragGhost.card = null;
                                }
                            }
                            onCentroidChanged: {
                                if (active) {
                                    bar.dragDesktop(delegate, centroid.scenePosition);
                                }
                            }
                        }

                        HoverHandler {
                            id: thumbnailHover
                        }
""")

# A MouseArea child would take the press before the DragHandler sees it.
edit(bar, """
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onClicked: mouse => {
                                mouse.accepted = true;
                                delegate.activate();
                            }
                        }
""", """
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: delegate.activate()
                        }
""")

# Highlight a desktop while a window is dragged onto it.
edit(bar, "hovered: thumbnailHover.hovered\n",
     "hovered: thumbnailHover.hovered || dropArea.containsDrag\n")
edit(bar, """
                        DropArea {
                            anchors.fill: parent
                            onEntered: (drag) => {
""", """
                        DropArea {
                            id: dropArea
                            anchors.fill: parent
                            onEntered: (drag) => {
""")

edit(bar, "active: !bar.heap.dragActive && (",
     "active: !bar.heap.dragActive && !desktopDragHandler.active && (")

# --- Main.qml: the large desktop views (and the grid) list only this screen's
# desktops too. They follow a ListModel that is kept in sync with moves rather
# than resets, so the views aren't recreated while desktops get reordered.
main = out / "qml" / "Main.qml"

edit(main, "            id: allDesktopHeaps\n            model: desktopModel\n",
     "            id: allDesktopHeaps\n            model: screenDesktopModel\n")
edit(main, "property int desktops: Math.max(bar.desktopCount, 2)",
     "property int desktops: Math.max(allDesktopHeaps.count, 2)")
edit(main, "visible: bar.desktopCount === 1", "visible: allDesktopHeaps.count === 1")

edit(main, "onClicked: desktopModel.create(desktopModel.rowCount())",
     "onClicked: effect.assignDesktop(desktopModel.create(desktopModel.rowCount(), bar.nextDesktopName()), targetScreen)")
edit(main, "            desktopModel.create(desktopModel.rowCount());\n",
     "            effect.assignDesktop(desktopModel.create(desktopModel.rowCount(), bar.nextDesktopName()), targetScreen);\n")

edit(main, """
    KWinComponents.VirtualDesktopModel {
        id: desktopModel
    }
""", """
    KWinComponents.VirtualDesktopModel {
        id: desktopModel
    }

    ListModel {
        id: screenDesktopModel
        Component.onCompleted: container.syncScreenDesktops()
    }

    function syncScreenDesktops() {
        const desktops = KWinComponents.Workspace.desktops.filter(desktop => effect.isDesktopOnScreen(desktop, targetScreen));
        const idAt = row => {
            const desktop = screenDesktopModel.get(row).desktop;
            return desktop ? desktop.id : "";
        };
        for (let i = 0; i < desktops.length; ++i) {
            let j = i;
            while (j < screenDesktopModel.count && idAt(j) !== desktops[i].id) {
                ++j;
            }
            if (j === screenDesktopModel.count) {
                screenDesktopModel.insert(i, { desktop: desktops[i] });
            } else if (j !== i) {
                screenDesktopModel.move(j, i, 1);
            }
        }
        if (screenDesktopModel.count > desktops.length) {
            screenDesktopModel.remove(desktops.length, screenDesktopModel.count - desktops.length);
        }
    }

    Connections {
        target: effect
        function onSpacesChanged() {
            container.syncScreenDesktops();
        }
    }
""")
