#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
zsh scripts/build.sh
app_path='build/Chui Files.app'
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
dmg_path="build/Chui-Files-${version}-universal.dmg"
stage_dir=$(mktemp -d /tmp/chui-files-package.XXXXXX)
trap 'rm -rf "$stage_dir"' EXIT
ditto "$app_path" "$stage_dir/Chui Files.app"
ln -s /Applications "$stage_dir/Applications"
cp "$app_path/Contents/Resources/AppIcon.icns" "$stage_dir/.VolumeIcon.icns"
xcrun SetFile -a C "$stage_dir"
rw_path="${stage_dir}.dmg"
mount_dir=$(mktemp -d /tmp/chui-files-icon.XXXXXX)
trap 'hdiutil detach "$mount_dir" >/dev/null 2>&1 || true; rm -rf "$stage_dir" "$rw_path"; rmdir "$mount_dir" 2>/dev/null || true' EXIT
hdiutil create -volname "Chui Files ${version}" -srcfolder "$stage_dir" -ov -format UDRW "$rw_path"
hdiutil attach "$rw_path" -nobrowse -mountpoint "$mount_dir"
xcrun SetFile -a C "$mount_dir"
hdiutil detach "$mount_dir"
hdiutil convert "$rw_path" -format UDZO -ov -o "$dmg_path"
# 为 Finder 中的 DMG 文件设置与应用一致的自定义图标。
cat > "$stage_dir/set-icon.swift" <<'SWIFT'
import AppKit
let args = CommandLine.arguments
guard let icon = NSImage(contentsOfFile: args[1]),
      NSWorkspace.shared.setIcon(icon, forFile: args[2], options: []) else {
    fatalError("无法设置 DMG 图标")
}
SWIFT
xcrun swift -module-cache-path /tmp/chui-swift-cache "$stage_dir/set-icon.swift" "$app_path/Contents/Resources/AppIcon.icns" "$dmg_path"
hdiutil verify "$dmg_path"
shasum -a 256 "$dmg_path"
echo "安装包：$dmg_path"
