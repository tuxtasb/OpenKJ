cmake_minimum_required(VERSION 3.21)

file(READ "src/okjversion.h" vercontents)
string(REGEX MATCH "OKJ_VERSION_MAJOR ([0-9]*)" _ ${vercontents})
set(ver_major ${CMAKE_MATCH_1})
string(REGEX MATCH "OKJ_VERSION_MINOR ([0-9]*)" _ ${vercontents})
set(ver_minor ${CMAKE_MATCH_1})
string(REGEX MATCH "OKJ_VERSION_BUILD ([0-9]*)" _ ${vercontents})
set(ver_build ${CMAKE_MATCH_1})
set(sem_ver "${ver_major}.${ver_minor}.${ver_build}")

project(openkj
        VERSION ${sem_ver}
        DESCRIPTION "Karaoke hosting software"
        HOMEPAGE_URL "https://openkj.org"
        LANGUAGES CXX C
        )

message(STATUS "Building OpenKJ ${sem_ver}")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

include(FetchContent)
include(GNUInstallDirs)

# Third party dependencies.  By default the system/SDK provided copies are
# used, falling back to fetching a pinned upstream release when they are not
# found.  Store builds (Windows/macOS) normally use the fetched copies.
option(OKJ_FETCH_TAGLIB "Always build TagLib from source instead of using a system copy" OFF)
option(OKJ_FETCH_SPDLOG "Always build spdlog from source instead of using a system copy" OFF)
set(OKJ_TAGLIB_VERSION "v2.3.2" CACHE STRING "TagLib release to fetch when building from source")
set(OKJ_SPDLOG_VERSION "v1.17.0" CACHE STRING "spdlog release to fetch when building from source")

# ---------------------------------------------------------------------------
# Qt 6
# ---------------------------------------------------------------------------
find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Widgets Sql Network Concurrent Svg PrintSupport)
qt_standard_project_setup()
set(CMAKE_AUTORCC ON)

# ---------------------------------------------------------------------------
# GStreamer (>= 1.20) - located through pkg-config on every platform.  The
# official Windows (MSVC) and macOS GStreamer installers ship .pc files, so we
# just point pkg-config at them.
# ---------------------------------------------------------------------------
if (WIN32)
    if (DEFINED ENV{GSTREAMER_1_0_ROOT_MSVC_X86_64})
        set(GST_ROOT "$ENV{GSTREAMER_1_0_ROOT_MSVC_X86_64}")
    elseif (DEFINED ENV{GSTREAMER_1_0_ROOT_X86_64})
        set(GST_ROOT "$ENV{GSTREAMER_1_0_ROOT_X86_64}")
    else ()
        set(GST_ROOT "C:/Program Files/gstreamer/1.0/msvc_x86_64")
    endif ()
    file(TO_CMAKE_PATH "${GST_ROOT}" GST_ROOT)
    message(STATUS "Using GStreamer root: ${GST_ROOT}")
    find_program(PKG_CONFIG_EXECUTABLE pkg-config HINTS "${GST_ROOT}/bin")
    set(ENV{PKG_CONFIG_PATH} "${GST_ROOT}/lib/pkgconfig")
elseif (APPLE)
    set(GST_ROOT "/Library/Frameworks/GStreamer.framework/Versions/1.0" CACHE PATH "GStreamer framework root")
    if (EXISTS "${GST_ROOT}/lib/pkgconfig")
        message(STATUS "Using GStreamer framework: ${GST_ROOT}")
        find_program(PKG_CONFIG_EXECUTABLE pkg-config HINTS "${GST_ROOT}/bin")
        set(ENV{PKG_CONFIG_PATH} "${GST_ROOT}/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}")
    endif ()
    option(BUNDLE_GSTREAMER "Copy the GStreamer framework into the app bundle" OFF)
endif ()

find_package(PkgConfig REQUIRED)
pkg_check_modules(GSTREAMER REQUIRED IMPORTED_TARGET
        gstreamer-1.0>=1.20
        gstreamer-base-1.0
        gstreamer-app-1.0
        gstreamer-audio-1.0
        gstreamer-pbutils-1.0
        gstreamer-controller-1.0
        gstreamer-video-1.0
        )
message(STATUS "Found GStreamer ${GSTREAMER_gstreamer-1.0_VERSION}")

# ---------------------------------------------------------------------------
# TagLib
# ---------------------------------------------------------------------------
if (NOT OKJ_FETCH_TAGLIB)
    find_package(TagLib 2 CONFIG QUIET)
    if (TagLib_FOUND)
        message(STATUS "Using system TagLib ${TagLib_VERSION} (CMake config)")
        set(OKJ_TAGLIB_TARGET TagLib::tag)
    else ()
        pkg_check_modules(TAGLIB QUIET IMPORTED_TARGET taglib>=1.12)
        if (TAGLIB_FOUND)
            message(STATUS "Using system TagLib ${TAGLIB_VERSION} (pkg-config)")
            set(OKJ_TAGLIB_TARGET PkgConfig::TAGLIB)
        endif ()
    endif ()
endif ()
if (NOT OKJ_TAGLIB_TARGET)
    message(STATUS "Building TagLib ${OKJ_TAGLIB_VERSION} from source")
    set(BUILD_SHARED_LIBS OFF)
    set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
    set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(BUILD_BINDINGS OFF CACHE BOOL "" FORCE)
    set(WITH_ZLIB OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(taglib
            GIT_REPOSITORY https://github.com/taglib/taglib.git
            GIT_TAG ${OKJ_TAGLIB_VERSION}
            GIT_SHALLOW TRUE
            GIT_SUBMODULES "3rdparty/utfcpp"
            EXCLUDE_FROM_ALL
            )
    FetchContent_MakeAvailable(taglib)
    # TagLib only exports its include directories for installed builds, so
    # expose its header directories to us when used from the build tree.
    get_target_property(_taglib_includes tag INCLUDE_DIRECTORIES)
    target_include_directories(tag INTERFACE
            "$<BUILD_INTERFACE:${taglib_SOURCE_DIR}/taglib;${_taglib_includes};${taglib_BINARY_DIR};${taglib_BINARY_DIR}/taglib>")
    target_compile_definitions(tag INTERFACE TAGLIB_STATIC)
    set(OKJ_TAGLIB_TARGET tag)
endif ()

# ---------------------------------------------------------------------------
# spdlog (and fmt)
# ---------------------------------------------------------------------------
if (NOT OKJ_FETCH_SPDLOG)
    find_package(spdlog 1.10 CONFIG QUIET)
endif ()
if (spdlog_FOUND)
    message(STATUS "Using system spdlog ${spdlog_VERSION}")
else ()
    message(STATUS "Building spdlog ${OKJ_SPDLOG_VERSION} from source")
    set(SPDLOG_BUILD_EXAMPLE OFF CACHE BOOL "" FORCE)
    set(SPDLOG_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(spdlog
            GIT_REPOSITORY https://github.com/gabime/spdlog.git
            GIT_TAG ${OKJ_SPDLOG_VERSION}
            GIT_SHALLOW TRUE
            EXCLUDE_FROM_ALL
            )
    FetchContent_MakeAvailable(spdlog)
endif ()

# ---------------------------------------------------------------------------
# miniz (bundled single file amalgamation)
# ---------------------------------------------------------------------------
add_library(okj_miniz STATIC src/miniz/miniz.c src/miniz/miniz.h)
target_include_directories(okj_miniz PUBLIC src/miniz)
set_target_properties(okj_miniz PROPERTIES POSITION_INDEPENDENT_CODE ON)
if (WIN32)
    target_compile_definitions(okj_miniz PUBLIC MINIZ_NO_TIME)
endif ()

# ---------------------------------------------------------------------------
# OpenKJ
# ---------------------------------------------------------------------------
set(SOURCE_FILES
        src/main.cpp
        src/dlgaddsong.cpp
        src/mediabackend.cpp
        src/mzarchive.cpp
        src/okjutil.h
        src/okjtypes.cpp
        src/dlgvideopreview.cpp
        src/mainwindow.cpp
        src/dbupdater.cpp
        src/directorymonitor.cpp
        src/dlgkeychange.cpp
        src/dlgdatabase.cpp
        src/dlgrequests.cpp
        src/dlgregularexport.cpp
        src/dlgregularimport.cpp
        src/dlgregularsingers.cpp
        src/dlgsettings.cpp
        src/dlgcdg.cpp
        src/okarchive.cpp
        src/models/tablemodelbreaksongs.cpp
        src/models/tablemodelcustomnamingpatterns.cpp
        src/models/tablemodelhistorysingers.cpp
        src/models/tablemodelhistorysongs.cpp
        src/models/tablemodelkaraokesongs.cpp
        src/models/tablemodelkaraokesourcedirs.cpp
        src/models/tablemodelplaylistsongs.cpp
        src/models/tablemodelqueuesongs.cpp
        src/models/tablemodelrequests.cpp
        src/models/tablemodelrotation.cpp
        src/models/tablemodelsongshopsongs.cpp
        src/tagreader.cpp
        src/bmdbupdatethread.cpp
        src/settings.cpp
        src/bmdbdialog.cpp
        src/dlgcustompatterns.cpp
        src/audiorecorder.cpp
        src/okjsongbookapi.cpp
        src/dlgdbupdate.cpp
        src/dlgbookcreator.cpp
        src/dlgeq.cpp
        src/audiofader.cpp
        src/customlineedit.cpp
        src/tickernew.cpp
        src/updatechecker.cpp
        src/videodisplay.cpp
        src/volslider.cpp
        src/dlgaddsinger.cpp
        src/songshop.cpp
        src/dlgsongshop.cpp
        src/simplecrypt.cpp
        src/dlgsongshoppurchase.cpp
        src/dlgsetpassword.cpp
        src/dlgpassword.cpp
        src/dlgpurchaseprogress.cpp
        src/karaokefileinfo.cpp
        src/karaokefilepatternresolver.cpp
        src/custompattern.cpp
        src/dlgeditsong.cpp
        src/soundfxbutton.cpp
        src/runguard/runguard.cpp
        src/durationlazyupdater.cpp
        src/idledetect.cpp
        src/mainwindow.h
        src/dlgaddsong.h
        src/dlgvideopreview.h
        src/mediabackend.h
        src/mzarchive.h
        src/okjutil.h
        src/okjtypes.h
        src/okjfmt.h
        src/dbupdater.h
        src/directorymonitor.h
        src/dlgkeychange.h
        src/dlgdatabase.h
        src/dlgrequests.h
        src/dlgregularexport.h
        src/dlgregularimport.h
        src/dlgregularsingers.h
        src/dlgsettings.h
        src/dlgcdg.h
        src/okarchive.h
        src/models/tablemodelbreaksongs.h
        src/models/tablemodelcustomnamingpatterns.h
        src/models/tablemodelhistorysingers.h
        src/models/tablemodelhistorysongs.h
        src/models/tablemodelkaraokesongs.h
        src/models/tablemodelkaraokesourcedirs.h
        src/models/tablemodelplaylistsongs.h
        src/models/tablemodelqueuesongs.h
        src/models/tablemodelrequests.h
        src/models/tablemodelrotation.h
        src/models/tablemodelsongshopsongs.h
        src/tagreader.h
        src/bmdbupdatethread.h
        src/settings.h
        src/bmdbdialog.h
        src/dlgcustompatterns.h
        src/audiorecorder.h
        src/okjsongbookapi.h
        src/dlgdbupdate.h
        src/dlgbookcreator.h
        src/dlgeq.h
        src/audiofader.h
        src/customlineedit.h
        src/tickernew.h
        src/updatechecker.h
        src/videodisplay.h
        src/volslider.h
        src/okjversion.h
        src/dlgaddsinger.h
        src/songshop.h
        src/dlgsongshop.h
        src/simplecrypt.h
        src/dlgsongshoppurchase.h
        src/dlgsetpassword.h
        src/dlgpassword.h
        src/dlgpurchaseprogress.h
        src/karaokefileinfo.h
        src/karaokefilepatternresolver.h
        src/custompattern.h
        src/dlgeditsong.h
        src/soundfxbutton.h
        src/runguard/runguard.h
        src/models/tableviewtooltipfilter.h
        src/durationlazyupdater.h
        src/idledetect.h
        src/mainwindow.ui
        src/dlgaddsong.ui
        src/dlgkeychange.ui
        src/dlgdatabase.ui
        src/dlgrequests.ui
        src/dlgregularexport.ui
        src/dlgregularimport.ui
        src/dlgregularsingers.ui
        src/dlgsettings.ui
        src/dlgcdg.ui
        src/bmdbdialog.ui
        src/dlgcustompatterns.ui
        src/dlgdbupdate.ui
        src/dlgbookcreator.ui
        src/dlgeq.ui
        src/dlgaddsinger.ui
        src/dlgsongshop.ui
        src/dlgsongshoppurchase.ui
        src/dlgsetpassword.ui
        src/dlgpassword.ui
        src/dlgpurchaseprogress.ui
        src/dlgeditsong.ui
        src/dlgvideopreview.ui
        src/resources.qrc
        src/softwarerendervideosink.cpp
        src/softwarerendervideosink.h
        src/cdg/cdgappsrc.cpp
        src/cdg/cdgappsrc.h
        src/cdg/cdgfilereader.cpp
        src/cdg/cdgfilereader.h
        src/cdg/cdgimageframe.cpp
        src/cdg/cdgimageframe.h
        src/cdg/libCDG.h
        src/gstreamer/gstreamerhelper.cpp
        src/gstreamer/gstreamerhelper.h
        )
qt_add_executable(openkj ${SOURCE_FILES})

target_include_directories(openkj PRIVATE src)

target_compile_definitions(openkj PRIVATE
        QT_DISABLE_DEPRECATED_BEFORE=0x050F00
        )

target_link_libraries(openkj PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Widgets
        Qt6::Sql
        Qt6::Network
        Qt6::Concurrent
        Qt6::Svg
        Qt6::PrintSupport
        PkgConfig::GSTREAMER
        ${OKJ_TAGLIB_TARGET}
        spdlog::spdlog
        okj_miniz
        )

if (WIN32)
    target_link_libraries(openkj PRIVATE winmm)
endif ()

# ---------------------------------------------------------------------------
# Linux / FreeBSD (also used for the snap)
# ---------------------------------------------------------------------------
if (UNIX AND NOT APPLE)
    install(TARGETS openkj RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
    install(FILES src/Icons/org.openkj.OpenKJ.svg
            DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
    install(FILES src/org.openkj.OpenKJ.desktop
            DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
    install(FILES src/org.openkj.OpenKJ.metainfo.xml
            DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo)
endif ()

# ---------------------------------------------------------------------------
# macOS app bundle
# ---------------------------------------------------------------------------
if (APPLE)
    set(openkj_ICON ${CMAKE_CURRENT_SOURCE_DIR}/src/Icons/OpenKJ.icns)
    set_source_files_properties(${openkj_ICON} PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")
    target_sources(openkj PRIVATE ${openkj_ICON})
    set_target_properties(openkj PROPERTIES
            MACOSX_BUNDLE TRUE
            MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/macos/Info.plist.in
            MACOSX_BUNDLE_GUI_IDENTIFIER org.openkj.openkj
            MACOSX_BUNDLE_BUNDLE_NAME OpenKJ
            MACOSX_BUNDLE_BUNDLE_VERSION ${sem_ver}
            MACOSX_BUNDLE_SHORT_VERSION_STRING ${sem_ver}
            MACOSX_BUNDLE_ICON_FILE OpenKJ.icns
            XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER org.openkj.openkj
            )
    if (BUNDLE_GSTREAMER)
        # Copy the GStreamer framework into the bundle and rewrite its install
        # names so the app is self contained (required for the Mac App Store).
        target_compile_definitions(openkj PRIVATE MAC_OVERRIDE_GST)
        set(_gst_fw "/Library/Frameworks/GStreamer.framework")
        set(_bundle_fw "$<TARGET_BUNDLE_CONTENT_DIR:openkj>/Frameworks/GStreamer.framework")
        add_custom_command(TARGET openkj POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_CONTENT_DIR:openkj>/Frameworks"
                COMMAND cp -pR "${_gst_fw}" "${_bundle_fw}"
                COMMAND osxrelocator "${_bundle_fw}/Versions/Current/lib" "${_gst_fw}/" "@executable_path/../Frameworks/GStreamer.framework/" -r
                COMMAND osxrelocator "${_bundle_fw}/Versions/Current/libexec" "${_gst_fw}/" "@executable_path/../../../../../../Frameworks/GStreamer.framework/" -r
                COMMAND osxrelocator "${_bundle_fw}/Versions/Current/bin" "${_gst_fw}/" "@executable_path/../../../../Frameworks/GStreamer.framework/" -r
                COMMAND osxrelocator "$<TARGET_BUNDLE_CONTENT_DIR:openkj>/MacOS" "${_gst_fw}/" "@executable_path/../Frameworks/GStreamer.framework/" -r
                USES_TERMINAL
                VERBATIM
                )
    endif ()
    install(TARGETS openkj BUNDLE DESTINATION .)
endif ()

# ---------------------------------------------------------------------------
# Windows
# ---------------------------------------------------------------------------
if (WIN32)
    target_sources(openkj PRIVATE src/appicon.rc)
    set_target_properties(openkj PROPERTIES WIN32_EXECUTABLE TRUE)
    install(TARGETS openkj RUNTIME DESTINATION .)
endif ()

# Qt runtime deployment (windeployqt / macdeployqt) for packaged builds:
#   cmake --install build --prefix <staging dir>
if (WIN32 OR APPLE)
    qt_generate_deploy_app_script(
            TARGET openkj
            OUTPUT_SCRIPT okj_deploy_script
            NO_UNSUPPORTED_PLATFORM_ERROR
    )
    install(SCRIPT ${okj_deploy_script})
endif ()
