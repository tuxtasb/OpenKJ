#!/bin/bash
# Build a standalone, signed OpenKJ DMG from a Homebrew-based build.
#
# Prereqs: brew install cmake ninja pkgconf qt@5 gstreamer
# Build first (from repo root):
#   cmake -DSPDLOG_USE_BUNDLED=true -DCMAKE_BUILD_TYPE=Release -DBUILDONLY=1 \
#         -DCMAKE_OSX_DEPLOYMENT_TARGET=<macOS of brew bottles> \
#         "-DCMAKE_CXX_FLAGS=-DFMT_CONSTEVAL= -DMAC_OVERRIDE_GST" . -B build-macos -G Ninja
#   ninja -C build-macos
# For key change (the "pitch" element), build the SoundTouch plugin Homebrew doesn't ship:
#   macos/build-soundtouch-plugin.sh build-macos/soundtouch
#   export EXTRA_PLUGIN_DIR=build-macos/soundtouch/plugins
#
# Usage: macos/package-dmg.sh "Developer ID Application: NAME (TEAMID)" [build-dir]
set -euo pipefail

IDENTITY="${1:?signing identity required}"
BUILD_DIR="${2:-build-macos}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BREW="$(brew --prefix)"
QT="$(brew --prefix qt@5)"
GST="$(brew --prefix gstreamer)"

VER=$(sed -n 's/#define OKJ_VERSION_STRING "\(.*\)"/\1/p' "$REPO/src/okjversion.h")
ARCH=$(uname -m)
OUT="$REPO/$BUILD_DIR/dist"
STAGE="$OUT/stage"
APP="$STAGE/OpenKJ.app"
DMG="$OUT/OpenKJ-${VER}-macos-${ARCH}.dmg"

# Plugins needed by OpenKJ's pipelines (see mediabackend.cpp) plus decoders for common karaoke formats.
PLUGINS="coreelements app audioconvert audioresample audiorate autodetect osxaudio playback
typefindfunctions volume level audiofx replaygain lame ogg vorbis wavenc wavparse videoconvertscale
opengl osxvideo equalizer isomp4 matroska avi flac mpg123 audioparsers id3demux apetag libav
applemedia videoparsersbad videorate deinterlace pbtypes rawparse subparse soundtouch"

echo "==> Staging OpenKJ ${VER} (${ARCH})"
rm -rf "$OUT"; mkdir -p "$STAGE"
ditto "$REPO/$BUILD_DIR/openkj.app" "$APP"

echo "==> Info.plist"
PB=/usr/libexec/PlistBuddy
# Homebrew bottles are built per major macOS release; require that major version.
MINOS=$(vtool -show-build "$GST/lib/libgstreamer-1.0.0.dylib" | awk '/minos/{split($2,v,"."); print v[1]".0"; exit}')
$PB -c "Add :LSMinimumSystemVersion string $MINOS" "$APP/Contents/Info.plist"
$PB -c "Set :CFBundleShortVersionString $VER" "$APP/Contents/Info.plist"
$PB -c "Add :NSMicrophoneUsageDescription string 'OpenKJ records karaoke performances from your audio input.'" "$APP/Contents/Info.plist"
$PB -c "Add :NSHighResolutionCapable bool true" "$APP/Contents/Info.plist"

echo "==> Qt (macdeployqt)"
"$QT/bin/macdeployqt" "$APP" -always-overwrite

echo "==> GStreamer"
GFW="$APP/Contents/Frameworks/GStreamer.framework"
GV="$GFW/Versions/1.0"
mkdir -p "$GV/lib/gstreamer-1.0" "$GV/libexec/gstreamer-1.0" "$GV/lib/gio/modules" "$GV/Resources"
ln -s 1.0 "$GFW/Versions/Current"
ln -s Versions/Current/Resources "$GFW/Resources"
cat > "$GV/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.openkj.gstreamer</string>
<key>CFBundleName</key><string>GStreamer</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>$(pkg-config --modversion gstreamer-1.0)</string>
<key>CFBundleVersion</key><string>$(pkg-config --modversion gstreamer-1.0)</string>
</dict></plist>
EOF
# EXTRA_PLUGIN_DIR: optional dir of separately built plugins (e.g. libgstsoundtouch.dylib, which
# Homebrew doesn't ship -- see macos/build-soundtouch-plugin.sh). Searched before Homebrew.
for p in $PLUGINS; do
  f=""
  for d in ${EXTRA_PLUGIN_DIR:-} "$BREW/lib/gstreamer-1.0"; do
    [ -e "$d/libgst$p.dylib" ] && { f="$d/libgst$p.dylib"; break; }
  done
  if [ -n "$f" ]; then cp "$f" "$GV/lib/gstreamer-1.0/"; else echo "    WARNING: plugin '$p' not available, skipping"; fi
done
cp "$GST/libexec/gstreamer-1.0/gst-plugin-scanner" "$GV/libexec/gstreamer-1.0/"

echo "==> Bundling dylib dependencies"
python3 -I "$REPO/macos/bundle_deps.py" "$APP" "$BREW/lib"

echo "==> Checking for leftover external references"
LEAK=0
while IFS= read -r -d '' f; do
  if file -b "$f" | grep -q Mach-O; then
    if otool -L "$f" | tail -n +2 | grep -E "$BREW|/usr/local/" ; then echo "    in $f"; LEAK=1; fi
  fi
done < <(find "$APP" -type f -print0)
[ $LEAK -eq 0 ] || { echo "External references remain"; exit 1; }

echo "==> Signing"
SIGN=(codesign --force --timestamp --options runtime -s "$IDENTITY")
# Inside-out: loose Mach-O files first, then framework bundles, then the app.
while IFS= read -r -d '' f; do
  if file -b "$f" | grep -q Mach-O; then "${SIGN[@]}" "$f" >/dev/null; fi
done < <(find "$APP/Contents/Frameworks" "$APP/Contents/PlugIns" -type f -print0)
for fw in "$APP"/Contents/Frameworks/*.framework; do "${SIGN[@]}" "$fw"; done
"${SIGN[@]}" --entitlements "$REPO/macos/openkj.entitlements" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Creating DMG"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "OpenKJ ${VER}" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG"
codesign --force --timestamp -s "$IDENTITY" "$DMG"
codesign --verify --verbose=2 "$DMG"
rm -rf "$STAGE"
echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
