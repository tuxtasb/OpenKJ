[![Language grade: C/C++](https://img.shields.io/lgtm/grade/cpp/g/OpenKJ/OpenKJ.svg?logo=lgtm&logoWidth=18)](https://lgtm.com/projects/g/OpenKJ/OpenKJ/context:cpp)
[![Copr build status](https://copr.fedorainfracloud.org/coprs/openkj/OpenKJ-unstable/package/openkjtools/status_image/last_build.png)](https://copr.fedorainfracloud.org/coprs/openkj/OpenKJ-unstable/package/openkjtools/)
[![Windows Build](https://github.com/OpenKJ/OpenKJ/actions/workflows/windows-test.yml/badge.svg)](https://github.com/OpenKJ/OpenKJ/actions/workflows/windows-test.yml)
[![Test building on macOS](https://github.com/OpenKJ/OpenKJ/actions/workflows/macos-test.yml/badge.svg)](https://github.com/OpenKJ/OpenKJ/actions/workflows/macos-test.yml)

**Downloads**  
If you are looking for installers for Windows or macOS, please visit the Downloads section at https://openkj.org

Linux users can grab OpenKJ stable versions from flathub: https://flathub.org/apps/details/org.openkj.OpenKJ

If you would like to install Linux versions of the unstable builds, please refer to the OpenKJ documentation wiki.

Documentation can be found at https://docs.openkj.org

If you need help with OpenKJ, you can reach out to support@openkj.org via email.

OpenKJ
======

Cross-platform open source karaoke show hosting software.

OpenKJ is a fully featured karaoke hosting program.
A few features:
* Save/track/load regular singers
* Key changer
* Tempo control
* EQ
* End of track silence detection (after last CDG draw command)
* Rotation ticker on the CDG display
* Option to use a custom background or display a rotating slide show on the CDG output dialog while idle
* Fades break music in and out automatically when karaoke tracks start/end
* Remote request server integration allowing singers to look up and submit songs via the web or mobile apps
* Automatic performance recording
* Autoplay karaoke mode
* Lots of other little things

It currently handles media+g zip files (zip files containing an mp3, wav, or ogg file and a cdg file) and paired mp3 and cdg files.  I'll be adding others in the future if anyone expresses interest.  It also can play non-cdg based video files (mkv, mp4, mpg, avi) for both break music and karaoke.

Database entries for the songs are based on the file naming scheme.  I've included the common ones I've come across which should cover 90% of what's out there. Custom patterns can be also defined in the program using regular expressions.



**Requirements to build OpenKJ:**

* CMake 3.21 or newer and a C++20 compiler
* Qt 6.4 or newer (Core, Gui, Widgets, Sql, Network, Concurrent, Svg, PrintSupport)
* GStreamer 1.20 or newer (core + plugins-base development files)
* TagLib 1.12 or newer (2.x recommended)
* spdlog 1.10 or newer
* InfoZip `unzip` at runtime (for some zip archives)

If TagLib or spdlog are not installed they are downloaded and built automatically
(pass `-DOKJ_FETCH_TAGLIB=ON` / `-DOKJ_FETCH_SPDLOG=ON` to force this).

**Linux**

```
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

On Debian/Ubuntu the dependencies are `qt6-base-dev qt6-svg-dev libgl-dev libgstreamer1.0-dev
libgstreamer-plugins-base1.0-dev libtag-dev libspdlog-dev pkg-config ninja-build cmake`.

A snap can be built with `snapcraft pack` from the repository root (see `snap/snapcraft.yaml`).

**macOS**

Install Qt 6 and the official GStreamer framework (runtime + devel) from
https://gstreamer.freedesktop.org, or use Homebrew (`brew install qt gstreamer taglib spdlog`), then:

```
cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH="$(brew --prefix qt)"
cmake --build build
```

`-DBUNDLE_GSTREAMER=ON` copies the GStreamer framework into the app bundle.

**Windows**

Install Qt 6 (MSVC 2022 64-bit) and the GStreamer MSVC 64-bit installer (runtime + development
files) from https://gstreamer.freedesktop.org.  From a Visual Studio developer prompt:

```
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=C:\Qt\6.11.2\msvc2022_64
cmake --build build
```

GStreamer is located through the `GSTREAMER_1_0_ROOT_MSVC_X86_64` environment variable set by its
installer.  Installers can be found at https://openkj.org/ if you just want to run the software.
