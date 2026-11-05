#!/bin/sh
# Builds Holler.app into ./build. Pass --install to copy it to /Applications.
set -e
cd "$(dirname "$0")"

swift build -c release --product Holler
BIN_DIR="$(swift build -c release --show-bin-path)"

APP=build/Holler.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Holler" "$APP/Contents/MacOS/Holler"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# FluidAudio's resource bundles, if this build has any.
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
cp LICENSE "$APP/Contents/Resources/"

# Accessibility and Microphone grants are keyed to the signature. An ad-hoc signature
# changes with every build, so macOS would silently drop the grants after each rebuild.
# A self-signed code signing certificate keeps them: Gutter's "Gutter Dev" works, or
# set LOCAL_SIGN_NAME to another one's name.
LOCAL_SIGN_NAME=${LOCAL_SIGN_NAME:-Gutter Dev}
LOCAL_ID=$(security find-identity -p codesigning 2>/dev/null \
    | awk -v name="\"$LOCAL_SIGN_NAME\"" 'index($0, name) { print $2; exit }' || true)
if [ -n "$LOCAL_ID" ]; then
    codesign --force --sign "$LOCAL_ID" "$APP"
    echo "Signed with \"$LOCAL_SIGN_NAME\""
else
    codesign --force --sign - "$APP"
    echo "Ad-hoc signed: grant Accessibility again after every rebuild"
fi
echo "Built $APP"

if [ "$1" = "--install" ]; then
    osascript -e 'quit app "Holler"' 2>/dev/null || true
    rm -rf /Applications/Holler.app
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/Holler.app"
fi
