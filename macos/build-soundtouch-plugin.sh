#!/bin/bash
# Build GStreamer's SoundTouch plugin (provides the "pitch" element used for key change),
# which Homebrew's gstreamer formula does not include. Matches the installed GStreamer version.
#
# Prereqs: brew install gstreamer sound-touch meson ninja pkgconf
# Usage:   macos/build-soundtouch-plugin.sh <work-dir>
# Output:  <work-dir>/plugins/libgstsoundtouch.dylib  (pass <work-dir>/plugins as EXTRA_PLUGIN_DIR)
set -euo pipefail

WORK="$(mkdir -p "${1:?work dir required}" && cd "$1" && pwd)"
VER=$(pkg-config --modversion gstreamer-1.0)
TARBALL="gst-plugins-bad-$VER.tar.xz"
URL="https://gstreamer.freedesktop.org/src/gst-plugins-bad"

cd "$WORK"
if [ ! -f "$TARBALL" ]; then
  curl -fsSLO "$URL/$TARBALL"
  curl -fsSLO "$URL/$TARBALL.sha256sum"
fi
shasum -a 256 -c "$TARBALL.sha256sum"
rm -rf src build && mkdir src && tar -xf "$TARBALL" -C src

meson setup build "src/gst-plugins-bad-$VER" --buildtype=release \
  -Dauto_features=disabled -Dsoundtouch=enabled \
  -Dexamples=disabled -Dtests=disabled -Dtools=disabled -Dintrospection=disabled -Dnls=disabled
ninja -C build ext/soundtouch/libgstsoundtouch.dylib

mkdir -p plugins
cp build/ext/soundtouch/libgstsoundtouch.dylib plugins/
otool -L plugins/libgstsoundtouch.dylib
echo "Built $WORK/plugins/libgstsoundtouch.dylib"
