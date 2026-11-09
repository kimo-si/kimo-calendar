#!/bin/bash
set -euo pipefail

PROJECT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIRECTORY="$PROJECT_DIRECTORY/dist/Kimo 日历.app"
cd "$PROJECT_DIRECTORY"

# 编译经过优化的原生可执行文件。
swift build --configuration release
BINARY_DIRECTORY="$(swift build --configuration release --show-bin-path)"
mkdir -p "$APP_DIRECTORY/Contents/MacOS" "$APP_DIRECTORY/Contents/Resources"
cp "$BINARY_DIRECTORY/KimoCalendar" "$APP_DIRECTORY/Contents/MacOS/KimoCalendar.new"
mv -f "$APP_DIRECTORY/Contents/MacOS/KimoCalendar.new" "$APP_DIRECTORY/Contents/MacOS/KimoCalendar"
cp "$PROJECT_DIRECTORY/assets/Info.plist" "$APP_DIRECTORY/Contents/Info.plist"

# 保持 Swift Package 资源包名称，供 Bundle.module 在应用内定位。
for RESOURCE_BUNDLE in "$BINARY_DIRECTORY"/*.bundle; do
    [ -d "$RESOURCE_BUNDLE" ] || continue
    ditto "$RESOURCE_BUNDLE" "$APP_DIRECTORY/Contents/Resources/$(basename "$RESOURCE_BUNDLE")"
done

# 生成应用图标后执行本地签名，成品可直接在当前 Mac 打开。
swiftc -O "$PROJECT_DIRECTORY/Sources/KimoCalendar/App/CalendarIconRenderer.swift" \
    "$PROJECT_DIRECTORY/scripts/make-icon.swift" -o "$PROJECT_DIRECTORY/.build/make-icon"
"$PROJECT_DIRECTORY/.build/make-icon" "$PROJECT_DIRECTORY/.build/AppIcon.iconset"
iconutil --convert icns "$PROJECT_DIRECTORY/.build/AppIcon.iconset" --output "$APP_DIRECTORY/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP_DIRECTORY"
codesign --verify --deep --strict "$APP_DIRECTORY"
printf '\n已生成：%s\n' "$APP_DIRECTORY"
