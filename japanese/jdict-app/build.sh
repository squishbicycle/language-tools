#!/bin/sh
# Build JDict.app and install it to ~/Applications.
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/JDict.app"
rm -rf build && mkdir -p build/JDict.app/Contents/MacOS
swiftc -O -swift-version 5 main.swift -o build/JDict.app/Contents/MacOS/JDict
cp Info.plist build/JDict.app/Contents/
codesign --force --sign - build/JDict.app
pkill -x JDict || true
rm -rf "$APP"
mv build/JDict.app "$APP"
rmdir build
echo "Installed $APP"
