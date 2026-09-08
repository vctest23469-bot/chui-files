import SwiftUI
import AppKit
import CryptoKit

enum Theme {
    static var accent: Color {
        switch UserDefaults.standard.string(forKey: "accent") {
        case "橙色": return .orange
        case "绿色": return .green
        case "紫色": return .purple
        default: return Color(nsColor: .systemBlue)
        }
    }
    // Bound material brightness so desktop content cannot wash out text.
    static let canvas = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 0.94)
            : NSColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 0.96)
    }
    static let secondaryText = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.78, alpha: 1) : NSColor(white: 0.32, alpha: 1)
    }
    static var navigationIcon: Color { Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.55, green: 0.80, blue: 1, alpha: 1)
            : NSColor(red: 0.04, green: 0.34, blue: 0.63, alpha: 1)
    }) }
    static let panel = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 1, alpha: 0.45)
    }
    static let toolbar = NSColor(name: nil) { appearance in
        NSColor(white: 1, alpha: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.03 : 0.2)
    }
}

struct MaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView { let view = WindowMaterial(); view.material = .popover; view.blendingMode = .behindWindow; view.state = .active; return view }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct WorkbenchButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var enabled
    @Environment(\.colorScheme) var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(enabled ? Color.primary : Color.secondary)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(scheme == .dark ? Color.black.opacity(configuration.isPressed ? 0.65 : (enabled ? 0.50 : 0.18)) : Color.white.opacity(configuration.isPressed ? 0.5 : 0.85))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(enabled ? 0.18 : 0.07), lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 5))
    }
}

final class WindowMaterial: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.titlebarAppearsTransparent = true
    }
}

struct SettingsView: View {
    @ObservedObject var model: Workspace
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.accent); Text("外观与偏好").font(.title2.bold()); Spacer() }
            VStack(alignment: .leading, spacing: 8) {
                Text("主题").font(.headline)
                Text("沿用 Chui Eve 的原生材质、浅深色和系统外观逻辑。").font(.caption).foregroundStyle(.secondary)
                Picker("外观", selection: $model.appearance) { ForEach(["系统", "浅色", "深色"], id: \.self) { Text($0 == "系统" ? "跟随系统" : $0).tag($0) } }.pickerStyle(.segmented)
                    .onChange(of: model.appearance) { _, value in UserDefaults.standard.set(value, forKey: "appearance") }
            }
            Picker("强调色", selection: $model.accent) { ForEach(["系统蓝", "橙色", "绿色", "紫色"], id: \.self) { Text($0).tag($0) } }
                .onChange(of: model.accent) { _, value in UserDefaults.standard.set(value, forKey: "accent") }
            Divider()
            Toggle("显示隐藏文件", isOn: Binding(get: { model.hidden }, set: { _ in model.toggleHidden() }))
            Toggle("左右文件夹联动浏览", isOn: $model.linked)
            Picker("复制 / 移动遇到同名", selection: $model.conflict) { ForEach(Conflict.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Text("目录变更自动刷新。删除进入废纸篓；同步前显示差异。文件操作期间可取消后续项目。").font(.caption).foregroundStyle(.secondary)
            HStack { Text("Chui Files · 本地专用").font(.caption).foregroundStyle(.secondary); Spacer(); Button("完成") { model.showSettings = false }.buttonStyle(.borderedProminent) }
        }.padding(28).frame(width: 480).tint(Theme.accent)
    }
}

extension Workspace {
    func duplicate() {
        let items = active.selected.map(\.url)
        batch("制作副本", items: items) { source in
            let target = FileEngine.unique(source)
            try FileManager.default.copyItem(at: source, to: target)
            return "已制作副本：\(target.lastPathComponent)"
        }
    }
    func makeLink(alias: Bool) {
        let items = active.selected.map(\.url), destination = other.folder
        batch(alias ? "制作替身" : "制作符号链接", items: items) { source in
            let target = FileEngine.unique(destination.appendingPathComponent(source.lastPathComponent + (alias ? " 替身" : " 链接")))
            if alias {
                let data = try source.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                try URL.writeBookmarkData(data, to: target)
            } else { try FileManager.default.createSymbolicLink(at: target, withDestinationURL: source) }
            return "已创建：\(target.path)"
        }
    }
    func checksums() {
        let items = active.selected.filter { !$0.directory }.map(\.url)
        showActivities = true
        batch("SHA-256", items: items) { url in
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            var hash = SHA256()
            while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
            return "SHA-256  \(hash.finalize().map { String(format: "%02x", $0) }.joined())  \(url.path)"
        }
    }
    func calculateSize() {
        let items = active.selected.map(\.url)
        showActivities = true
        batch("计算大小", items: items) { url in
            let entry = try FileEngine.entry(url)
            let size = entry.directory && !entry.symlink ? try FileEngine.tree(url, hidden: true).values.filter { !$0.directory }.reduce(Int64(0)) { $0 + $1.size } : entry.size
            return "\(url.lastPathComponent)：\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))（\(size) 字节）"
        }
    }
    func quickSelect() {
        guard let pattern = prompt("快速选择", value: "*.pdf", detail: "通配符：* 匹配任意字符，? 匹配一个字符。仅在当前过滤结果中选择。") else { return }
        let regex = "^" + NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".") + "$"
        guard let expression = try? NSRegularExpression(pattern: regex, options: .caseInsensitive) else { return }
        active.selection = Set(active.visible.filter { expression.firstMatch(in: $0.name, range: NSRange($0.name.startIndex..., in: $0.name)) != nil }.map(\.id))
    }
    func permissions() {
        let items = active.selected.map(\.url)
        guard !items.isEmpty, let value = prompt("修改 POSIX 权限", value: "644", detail: "输入三位八进制权限；仅修改选中项目，不递归。符号链接不处理。"), value.count == 3, let mode = Int(value, radix: 8) else { return }
        guard confirm("应用权限 \(value)？", "将修改 \(items.count) 项。目录通常需要执行权限（例如 755）才能进入。", button: "应用") else { return }
        batch("修改权限", items: items) { url in
            guard try !FileEngine.entry(url).symlink else { throw FileFailure.message("跳过符号链接。") }
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
            return "权限已更新：\(url.lastPathComponent) → \(value)"
        }
    }
    func fileCompare() {
        guard let l = left.selected.first, let r = right.selected.first, !l.directory, !r.directory else { alert("选择两个文件", "请在左右栏各选择一个文件。"); return }
        batch("比较文件", items: [l.url]) { _ in
            let same = FileManager.default.contentsEqual(atPath: l.url.path, andPath: r.url.path)
            return "\(l.name) ↔ \(r.name)：\(same ? "内容完全相同" : "内容不同")"
        }
        showActivities = true
    }
    func terminal() {
        let url = active.folder
        NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration())
    }
    func saveSyncPreset() {
        guard let name = prompt("保存同步预设", value: active.folder.lastPathComponent + " → " + other.folder.lastPathComponent) else { return }
        syncPresets.append(SyncPreset(name: name, source: active.folder.path, target: other.folder.path, hidden: hidden))
        persistSyncPresets()
    }
    func persistSyncPresets() { if let data = try? JSONEncoder().encode(syncPresets) { UserDefaults.standard.set(data, forKey: "syncPresets") } }
    func openPreset(_ preset: SyncPreset) {
        left.go(URL(fileURLWithPath: preset.source), hidden: preset.hidden)
        right.go(URL(fileURLWithPath: preset.target), hidden: preset.hidden)
        activeLeft = true; hidden = preset.hidden; compare()
    }
}

struct SyncPreset: Codable, Identifiable {
    var id = UUID()
    let name: String
    let source: String
    let target: String
    let hidden: Bool
}
