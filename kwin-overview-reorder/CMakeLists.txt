# Standalone build of the patched Overview effect (see patch-overview.py).
# The sources are copied next to this file by the PKGBUILD.

cmake_minimum_required(VERSION 3.22)
project(kwin-overview-reorder LANGUAGES CXX)

set(QT_MAJOR_VERSION 6)
find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick)
find_package(KF6 REQUIRED COMPONENTS Config CoreAddons GlobalAccel I18n)
find_package(KWin REQUIRED)

add_compile_definitions(TRANSLATION_DOMAIN="kwin")

kcoreaddons_add_plugin(overviewreorder INSTALL_NAMESPACE "kwin/effects/plugins")
target_sources(overviewreorder PRIVATE main.cpp overvieweffect.cpp spaces.cpp)
kconfig_add_kcfg_files(overviewreorder overviewconfig.kcfgc)

# KWin never unloads a plugin library, so each build gets its own file name
# (which is also the plugin id) and QML module; that lets a running KWin load a
# rebuilt version.
set(BUILD_ID "" CACHE STRING "Unique suffix for this build")
set(qml_uri org.kde.kwin.overviewreorder)
if(BUILD_ID)
    set_target_properties(overviewreorder PROPERTIES OUTPUT_NAME overviewreorder_${BUILD_ID})
    set(qml_uri ${qml_uri}.b${BUILD_ID})
endif()
target_compile_definitions(overviewreorder PRIVATE OVERVIEW_QML_URI="${qml_uri}")

qt_add_qml_module(overviewreorder
    NO_PLUGIN
    NO_CACHEGEN
    URI ${qml_uri}
    RESOURCE_PREFIX /qt/qml
    QML_FILES
        qml/DesktopBar.qml
        qml/DesktopView.qml
        qml/Main.qml
)

target_link_libraries(overviewreorder PRIVATE
    KWin::kwin
    KF6::ConfigGui
    KF6::CoreAddons
    KF6::GlobalAccel
    KF6::I18n
    Qt::Quick
)

# Since Plasma 6.8 the Overview search runs through KRunner.
file(READ overvieweffect.h _header)
if(_header MATCHES "KRunner")
    find_package(KF6 REQUIRED COMPONENTS Runner)
    target_link_libraries(overviewreorder PRIVATE KF6::Runner)
endif()
