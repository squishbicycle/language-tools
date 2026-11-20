#!/bin/sh
# Build SDict.app and install it to ~/Applications.
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/SDict.app"
rm -rf build && mkdir -p build/SDict.app/Contents/MacOS
swiftc -O -swift-version 5 main.swift -o build/SDict.app/Contents/MacOS/SDict
cp Info.plist build/SDict.app/Contents/
codesign --force --sign - build/SDict.app
pkill -x SDict || true
rm -rf "$APP"
mv build/SDict.app "$APP"
rmdir build
echo "Installed $APP"
