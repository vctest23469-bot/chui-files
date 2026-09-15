#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/Chui\ Files.app/Contents/MacOS build/Chui\ Files.app/Contents/Resources
xcrun swift -module-cache-path /tmp/chui-swift-cache scripts/icon.swift build/AppIcon.iconset
python3 scripts/pack-icon.py build/AppIcon.iconset 'build/Chui Files.app/Contents/Resources/AppIcon.icns'
mkdir -p build/bin
for cpu_arch in arm64 x86_64; do
    xcrun swiftc -swift-version 5 -target "${cpu_arch}-apple-macos14.0" -O -module-cache-path /tmp/chui-swift-cache Sources/*.swift -o "build/bin/ChuiFiles-${cpu_arch}" -framework SwiftUI -framework AppKit -framework Quartz
done
xcrun lipo -create build/bin/ChuiFiles-arm64 build/bin/ChuiFiles-x86_64 -output 'build/Chui Files.app/Contents/MacOS/ChuiFiles'
cat > 'build/Chui Files.app/Contents/Info.plist' <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ChuiFiles</string>
<key>CFBundleIdentifier</key><string>com.chui.files</string>
<key>CFBundleName</key><string>Chui Files</string>
<key>CFBundleDisplayName</key><string>Chui Files</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.9</string>
<key>CFBundleVersion</key><string>10</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
cp LICENSE 'build/Chui Files.app/Contents/Resources/LICENSE'
codesign --force --deep --sign - 'build/Chui Files.app'
echo '构建完成：build/Chui Files.app'
