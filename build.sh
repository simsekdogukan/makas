#!/bin/bash
set -e

APP_NAME="Makas"
TARGET_DIR="/Applications/${APP_NAME}.app"

echo "🔨 Derleniyor..."
swiftc -O main.swift -o "${APP_NAME}"

echo "📦 Uygulama paketi oluşturuluyor..."
pkill -9 "${APP_NAME}" 2>/dev/null || true
rm -rf "${TARGET_DIR}"
mkdir -p "${TARGET_DIR}/Contents/MacOS"
mkdir -p "${TARGET_DIR}/Contents/Resources"

mv "${APP_NAME}" "${TARGET_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${TARGET_DIR}/Contents/MacOS/${APP_NAME}"

cat << 'PLIST' > "${TARGET_DIR}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Makas</string>
    <key>CFBundleIdentifier</key>
    <string>com.antigravity.makas</string>
    <key>CFBundleName</key>
    <string>Makas</string>
    <key>CFBundleDisplayName</key>
    <string>Makas</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "✍️ İmzalanıyor..."
codesign --force --deep --sign - "${TARGET_DIR}"

echo "🚀 Başlatılıyor..."
open "${TARGET_DIR}"
echo "✅ ${APP_NAME} başarıyla kuruldu ve başlatıldı!"
