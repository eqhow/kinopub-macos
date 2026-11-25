#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

swift build -c release

APP="dist/Kinopub.app"
BIN=".build/release/Kinopub"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Kinopub"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

xattr -cr "$APP"
codesign --force --deep --sign - "$APP"

echo "Готово: $APP"
echo "Установка: cp -R \"$APP\" /Applications/   (или перетащите в «Программы»)"
