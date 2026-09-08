import SwiftUI
import AppKit
import Quartz
import UniformTypeIdentifiers

@main
struct ChuiFilesApp: App {
    @StateObject var workspace = Workspace()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Chui Files") {
            MainView(model: workspace)
                .frame(minWidth: 1140, minHeight: 620)
                .preferredColorScheme(workspace.appearance == "系统" ? nil : workspace.appearance == "浅色" ? .light : .dark)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in workspace.refresh() }
                .onAppear { AppDelegate.workspace = workspace }
        }
        .defaultSize(width: 1460, height: 850)
        .commands {
            CommandGroup(replacing: .appSettings) { Button("设置…") { workspace.showSettings = true }.keyboardShortcut(",") }
            CommandGroup(replacing: .newItem) {
                Button("新建标签页") { workspace.active.newTab(hidden: workspace.hidden) }.keyboardShortcut("t")
                Button("关闭当前标签页") { workspace.active.closeTab(workspace.active.tabIndex, hidden: workspace.hidden) }.keyboardShortcut("w")
                Divider()
                Button("新建文件夹") { workspace.create(directory: true) }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("新建文本文件") { workspace.create(directory: false) }
            }
            CommandGroup(replacing: .undoRedo) { Button("撤销上一次移动 / 重命名 / 删除") { workspace.undo() }.keyboardShortcut("z").disabled(workspace.busy || workspace.undoMoves.isEmpty) }
            CommandMenu("文件操作") {
                Button("复制到另一栏") { workspace.transfer(move: false) }.keyboardShortcut(KeyEquivalent("\u{F708}"), modifiers: [])
                Button("移动到另一栏") { workspace.transfer(move: true) }.keyboardShortcut(KeyEquivalent("\u{F709}"), modifiers: [])
                Button("复制文件到剪贴板") { workspace.clipboard() }.keyboardShortcut("c", modifiers: [.command, .shift])
                Button("粘贴文件") { workspace.paste() }.keyboardShortcut("v", modifiers: [.command, .shift])
                Button("移动粘贴") { workspace.paste(move: true) }.keyboardShortcut("v", modifiers: [.command, .option])
                Button("重命名") { workspace.rename() }
                Button("批量重命名…") { workspace.multiRename() }
                Button("移到废纸篓") { workspace.trash() }.keyboardShortcut(.delete, modifiers: .command)
                Divider()
                Button("压缩为 ZIP") { workspace.compress() }
                Button("解压 ZIP") { workspace.extract() }
                Button("编辑标签…") { workspace.tags() }
                Button("内置文本编辑器") { workspace.edit() }
                Button("比较 / 同步目录…") { workspace.compare() }
                Button("保存同步预设…") { workspace.saveSyncPreset() }
                Divider()
                Button("制作副本") { workspace.duplicate() }.keyboardShortcut("d")
                Button("在另一栏制作替身") { workspace.makeLink(alias: true) }
                Button("在另一栏制作符号链接") { workspace.makeLink(alias: false) }
                Button("计算 SHA-256 校验和") { workspace.checksums() }
                Button("比较左右选中文件") { workspace.fileCompare() }
                Button("计算文件夹大小") { workspace.calculateSize() }
                Button("修改权限…") { workspace.permissions() }
                Button("快速选择…") { workspace.quickSelect() }.keyboardShortcut("s", modifiers: [.command, .option])
                Button("反选") { workspace.active.selection = Set(workspace.active.visible.map(\.id)).subtracting(workspace.active.selection) }
                Button("在终端打开当前文件夹") { workspace.terminal() }
            }
            CommandMenu("前往") {
                Button("前往文件夹…") { workspace.goTo() }.keyboardShortcut("g", modifiers: [.command, .shift])
                Button("上一级") { workspace.navigate(workspace.active.folder.deletingLastPathComponent()) }.keyboardShortcut(.upArrow, modifiers: .command)
                Button("后退") { workspace.active.back(hidden: workspace.hidden) }.keyboardShortcut("[")
                Button("前进") { workspace.active.forward(hidden: workspace.hidden) }.keyboardShortcut("]")
                Button("选择文件夹…") { workspace.chooseFolder() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("递归搜索…") { workspace.search() }.keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("显示 / 隐藏隐藏文件") { workspace.toggleHidden() }.keyboardShortcut(".", modifiers: [.command, .shift])
                Button("显示 / 隐藏预览") { workspace.inspector.toggle() }.keyboardShortcut("i", modifiers: [.command, .option])
                Button("刷新") { workspace.refresh() }.keyboardShortcut("r")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var workspace: Workspace?
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.workspace?.busy == true { Self.workspace?.alert("文件操作尚未结束", "请等待当前操作完成，或取消后续项目后再退出。"); return .terminateCancel }
        return .terminateNow
    }
}

struct Tool: View {
    let icon: String
    let help: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 15, weight: .medium)).frame(width: 28, height: 28).foregroundStyle(active ? Theme.accent : Color.primary.opacity(0.8)) }
            .buttonStyle(.borderless).help(help).accessibilityLabel(help)
    }
}

struct MainView: View {
    @ObservedObject var model: Workspace
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1").foregroundStyle(Theme.accent)
                Text("Chui Files").font(.system(size: 14, weight: .semibold))
                Text("本地工作空间").font(.system(size: 11)).foregroundStyle(Color(nsColor: Theme.secondaryText))
                Spacer()
                Tool(icon: "arrow.left.arrow.right", help: "切换当前面板", active: false) { model.activeLeft.toggle() }
                Tool(icon: "link", help: "联动浏览", active: model.linked) { model.linked.toggle() }
                Divider().frame(height: 18)
                Tool(icon: "arrow.clockwise", help: "刷新 ⌘R") { model.refresh() }
                Tool(icon: "folder.badge.plus", help: "新建文件夹 ⇧⌘N") { model.create(directory: true) }
                Tool(icon: "arrow.triangle.2.circlepath", help: "比较并同步当前栏到另一栏") { model.compare() }
                Tool(icon: "star", help: "收藏当前文件夹") { model.addFavorite() }
                Tool(icon: "eye.slash", help: "显示隐藏文件 ⇧⌘.", active: model.hidden) { model.toggleHidden() }
                Tool(icon: "sidebar.right", help: "预览面板", active: model.inspector) { model.inspector.toggle() }
                Tool(icon: "list.bullet.rectangle", help: "活动日志", active: model.showActivities) { model.showActivities.toggle() }
                Tool(icon: "slider.horizontal.3", help: "外观与偏好") { model.showSettings = true }
            }.padding(.horizontal, 16).frame(height: 47).background(Color(nsColor: Theme.toolbar))
            Divider()
            HSplitView {
                Sidebar(model: model).frame(width: 244)
                PaneView(pane: model.left, model: model, isLeft: true).frame(minWidth: 310, idealWidth: 500, maxWidth: .infinity)
                PaneView(pane: model.right, model: model, isLeft: false).frame(minWidth: 310, idealWidth: 500, maxWidth: .infinity)
                if model.inspector { Inspector(pane: model.activeLeft ? model.left : model.right, model: model).frame(width: 250) }
            }
            if model.showActivities { ActivityView(model: model).frame(height: 150) }
            Divider()
            HStack(spacing: 12) {
                if model.busy { ProgressView().controlSize(.small); Text("\(model.completed)/\(model.total)").monospacedDigit(); Button("取消后续") { model.cancellation.stop() }.buttonStyle(WorkbenchButtonStyle()).help("当前单个文件操作完成后停止") }
                else { Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.green) }
                Text(model.status).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(model.activeLeft ? "左栏操作" : "右栏操作").foregroundStyle(.primary)
                Picker("同名", selection: $model.conflict) { ForEach(Conflict.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 140).controlSize(.small)
            }.font(.system(size: 11)).foregroundStyle(Color(nsColor: Theme.secondaryText)).padding(.horizontal, 14).frame(height: 31)
        }
        .background(Color(nsColor: Theme.canvas).ignoresSafeArea())
        .background(MaterialView().ignoresSafeArea())
        .tint(Theme.accent)
        .sheet(isPresented: $model.showSync) { SyncView(model: model) }
        .sheet(isPresented: $model.showSearch) { SearchView(model: model) }
        .sheet(item: $model.editor) { EditorView(document: $0, model: model) }
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
    }
}

struct Sidebar: View {
    @ObservedObject var model: Workspace
    let home = FileManager.default.homeDirectoryForCurrentUser
    func item(_ label: String, _ icon: String, _ url: URL) -> some View {
        Button { model.navigate(url) } label: {
            HStack(spacing: 8) { Image(systemName: icon).foregroundStyle(Theme.navigationIcon).frame(width: 17); Text(label).lineLimit(1); Spacer(minLength: 0) }.padding(.vertical, 6).padding(.horizontal, 8).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                heading("设备")
                DeviceList(model: model, pane: model.active)
                if !model.recents.isEmpty {
                    heading("最近的文件夹")
                    ForEach(model.recents.prefix(5), id: \.self) { path in item(URL(fileURLWithPath: path).lastPathComponent, "clock", URL(fileURLWithPath: path)) }
                }
                heading("收藏夹")
                item(home.lastPathComponent, "house", home)
                item("桌面", "menubar.dock.rectangle", home.appendingPathComponent("Desktop"))
                item("文稿", "doc", home.appendingPathComponent("Documents"))
                item("下载", "arrow.down.circle", home.appendingPathComponent("Downloads"))
                item("应用程序", "square.stack.3d.up", URL(fileURLWithPath: "/Applications"))
                item("图片", "photo", home.appendingPathComponent("Pictures"))
                ForEach(model.favorites, id: \.self) { path in
                    item(URL(fileURLWithPath: path).lastPathComponent, "folder", URL(fileURLWithPath: path))
                        .contextMenu { Button("移除收藏") { model.favorites.removeAll { $0 == path }; model.saveFavorites() } }
                }
                if !model.syncPresets.isEmpty {
                    heading("同步预设")
                    ForEach(model.syncPresets) { preset in
                        Button { model.openPreset(preset) } label: { Label(preset.name, systemImage: "arrow.triangle.2.circlepath").lineLimit(1).padding(8) }.buttonStyle(.plain)
                            .contextMenu { Button("移除预设") { model.syncPresets.removeAll { $0.id == preset.id }; model.persistSyncPresets() } }
                    }
                }
                heading("标签筛选 · 当前目录")
                ForEach(Array(zip(["红色", "橙色", "黄色", "绿色", "蓝色", "紫色", "灰色"], [Color.red, .orange, .yellow, .green, .blue, .purple, .gray])), id: \.0) { tag, color in
                    Button { model.active.filter = tag } label: { HStack(spacing: 10) { Circle().fill(color).frame(width: 8, height: 8); Text(tag); Spacer() }.padding(.vertical, 6).padding(.horizontal, 12) }.buttonStyle(.plain)
                }
                Spacer(minLength: 30)
                Button { model.chooseFolder() } label: { Label("打开文件夹…", systemImage: "folder.badge.plus").font(.system(size: 11)) }.buttonStyle(WorkbenchButtonStyle()).padding(8)
            }.font(.system(size: 12)).padding(8)
        }.background(Color(nsColor: Theme.panel).opacity(0.45))
    }
    func heading(_ title: String) -> some View { Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(nsColor: Theme.secondaryText)).padding(.top, 17).padding(.bottom, 5).padding(.leading, 8) }
}

struct PaneView: View {
    @ObservedObject var pane: Pane
    @ObservedObject var model: Workspace
    let isLeft: Bool
    var active: Bool { model.activeLeft == isLeft }
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(active ? Theme.accent : Color.clear).frame(height: 3)
            HStack(spacing: 2) {
                Tool(icon: "chevron.left", help: "后退") { pane.back(hidden: model.hidden) }.disabled(pane.history.isEmpty)
                Tool(icon: "chevron.right", help: "前进") { pane.forward(hidden: model.hidden) }.disabled(pane.future.isEmpty)
                Tool(icon: "arrow.up", help: "上一级") { pane.go(pane.folder.deletingLastPathComponent(), hidden: model.hidden) }
                Spacer()
                Tool(icon: "magnifyingglass", help: "递归搜索") { model.activeLeft = isLeft; model.search() }
                Tool(icon: pane.grid ? "list.bullet" : "square.grid.2x2", help: "切换列表 / 图标视图") { pane.grid.toggle() }
                Tool(icon: "plus", help: "新标签页") { pane.newTab(hidden: model.hidden) }
            }.padding(.horizontal, 6).frame(height: 36)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(Array(pane.tabs.enumerated()), id: \.offset) { index, url in
                        HStack(spacing: 7) {
                            Button { pane.selectTab(index, hidden: model.hidden) } label: { Label(url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent, systemImage: "folder").lineLimit(1) }.buttonStyle(.plain)
                            if pane.tabs.count > 1 { Button { pane.closeTab(index, hidden: model.hidden) } label: { Image(systemName: "xmark").font(.system(size: 8)) }.buttonStyle(.plain) }
                        }.font(.system(size: 11)).padding(.horizontal, 12).frame(height: 29).background(index == pane.tabIndex ? Color.primary.opacity(0.09) : .clear)
                    }
                }
            }.background(Color(nsColor: Theme.toolbar))
            FolderHeading(pane: pane, model: model, isLeft: isLeft)
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Color(nsColor: Theme.secondaryText))
                TextField("按名称或标签过滤", text: $pane.filter).textFieldStyle(.plain)
                if !pane.filter.isEmpty { Button { pane.filter = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            }.font(.system(size: 11)).padding(.horizontal, 12).frame(height: 29).background(Color.primary.opacity(0.035))
            Divider()
            if let error = pane.error {
                VStack(spacing: 12) { Image(systemName: "exclamationmark.folder").font(.largeTitle); Text("无法读取文件夹").font(.headline); Text(error).font(.caption).multilineTextAlignment(.center); Button("重新选择文件夹") { model.activeLeft = isLeft; model.chooseFolder() } }.foregroundStyle(Color(nsColor: Theme.secondaryText)).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pane.grid { grid }
            else { FileTable(pane: pane, model: model, isLeft: isLeft) }
            Divider()
            HStack {
                Text("\(pane.visible.count) 个项目" + (pane.selection.isEmpty ? "" : " · 已选 \(pane.selected.count) 项"))
                Spacer()
                Text((pane.volume?.availableText ?? "暂不可读") + " 可用")
            }.font(.system(size: 10)).foregroundStyle(Color(nsColor: Theme.secondaryText)).padding(.horizontal, 12).frame(height: 27)
            HStack(spacing: 12) {
                Button(isLeft ? "复制 →" : "← 复制") { model.activeLeft = isLeft; model.transfer(move: false) }
                Button(isLeft ? "移动 →" : "← 移动") { model.activeLeft = isLeft; model.transfer(move: true) }
                Spacer()
                Button { model.activeLeft = isLeft; model.trash() } label: { Image(systemName: "trash") }.help("移到废纸篓")
            }.buttonStyle(WorkbenchButtonStyle()).padding(.horizontal, 12).frame(height: 38).disabled(model.busy || pane.selected.isEmpty)
        }
        .background(Color(nsColor: Theme.panel))
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { model.activeLeft = isLeft })

        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            let destination = pane.folder
            let group = DispatchGroup(), lock = NSLock(); var urls: [URL] = []
            for provider in providers {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    if let url { lock.lock(); urls.append(url); lock.unlock() }
                }
            }
            group.notify(queue: .main) { model.transfer(move: false, urls: urls, target: destination) }
            return true
        }
    }
    var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95))], spacing: 12) {
                ForEach(pane.visible) { item in
                    VStack(spacing: 8) { Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 44, height: 44); Text(item.name).font(.system(size: 11)).lineLimit(2).multilineTextAlignment(.center).frame(height: 30) }
                        .frame(maxWidth: .infinity).padding(7).background(pane.selection.contains(item.id) ? Theme.accent.opacity(0.23) : .clear).clipShape(RoundedRectangle(cornerRadius: 5))
                        .onTapGesture(count: 2) { model.open(item, pane: pane) }
                        .onTapGesture { if NSEvent.modifierFlags.contains(.command) { if pane.selection.contains(item.id) { pane.selection.remove(item.id) } else { pane.selection.insert(item.id) } } else { pane.selection = [item.id] } }
                        .onDrag { NSItemProvider(object: item.url as NSURL) }
                        .contextMenu { fileMenu(model: model) { pane.selection = [item.id]; model.activeLeft = isLeft } }
                }
            }.padding(12)
        }
    }
}

// NSTableView supplies real macOS range selection, keyboard navigation, and file dragging.
struct FileTable: NSViewRepresentable {
    @ObservedObject var pane: Pane
    let model: Workspace
    let isLeft: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(), table = NativeTable(frame: NSRect(x: 0, y: 0, width: 480, height: 400))
        table.autoresizingMask = [.width]
        table.owner = context.coordinator
        scroll.drawsBackground = false; table.backgroundColor = .clear; table.style = .plain; table.rowHeight = 25; table.intercellSpacing = NSSize(width: 10, height: 0)
        table.allowsMultipleSelection = true; table.usesAlternatingRowBackgroundColors = false
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        for (id, title, width) in [("name", "名称", 260.0), ("size", "大小", 78.0), ("date", "修改时间", 140.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width; column.minWidth = id == "name" ? 140 : 60
            table.addTableColumn(column)
        }
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.openRow)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator; coordinator.parent = self
        let rows = pane.visible
        if rows != coordinator.rows { coordinator.rows = rows; coordinator.updating = true; coordinator.table?.reloadData(); coordinator.updating = false }
        let indexes = IndexSet(rows.enumerated().filter { pane.selection.contains($0.element.id) }.map(\.offset))
        if coordinator.table?.selectedRowIndexes != indexes { coordinator.updating = true; coordinator.table?.selectRowIndexes(indexes, byExtendingSelection: false); coordinator.updating = false }
    }
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FileTable
        var rows: [Entry] = []
        weak var table: NSTableView?
        var updating = false
        init(_ parent: FileTable) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let entry = rows[row]
            let field = NSTextField(labelWithString: "")
            field.font = .systemFont(ofSize: 12); field.lineBreakMode = .byTruncatingMiddle
            if tableColumn?.identifier.rawValue == "name" {
                let image = NSImageView(image: NSWorkspace.shared.icon(forFile: entry.url.path)); image.imageScaling = .scaleProportionallyDown
                image.translatesAutoresizingMaskIntoConstraints = false; image.widthAnchor.constraint(equalToConstant: 17).isActive = true; image.heightAnchor.constraint(equalToConstant: 17).isActive = true
                field.stringValue = entry.name + (entry.symlink ? " ↗" : "")
                let stack = NSStackView(views: [image, field]); stack.spacing = 7; stack.alignment = .centerY
                stack.toolTip = entry.url.path + (entry.tags.isEmpty ? "" : "\n标签：" + entry.tags.joined(separator: ", "))
                return stack
            }
            field.textColor = Theme.secondaryText
            if tableColumn?.identifier.rawValue == "size" { field.stringValue = entry.sizeText; field.alignment = .right }
            else { field.stringValue = entry.modified.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute()) }
            return field
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            parent.model.activeLeft = parent.isLeft
            parent.pane.selection = Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
        }
        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            let sort = tableColumn.title
            if parent.pane.sort == sort { parent.pane.ascending.toggle() } else { parent.pane.sort = sort; parent.pane.ascending = true }
        }
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? { rows[row].url as NSURL }
        @objc func openRow() {
            guard let table, rows.indices.contains(table.clickedRow) else { return }
            parent.model.open(rows[table.clickedRow], pane: parent.pane)
        }
        @objc func menuAction(_ sender: NSMenuItem) {
            let m = parent.model; m.activeLeft = parent.isLeft
            switch sender.tag {
            case 0: if let first = parent.pane.selected.first { m.open(first, pane: parent.pane) }
            case 1: m.transfer(move: false)
            case 2: m.transfer(move: true)
            case 3: m.rename()
            case 4: m.multiRename()
            case 5: m.trash()
            case 6: m.compress()
            case 7: m.extract()
            case 8: m.tags()
            case 9: m.copyPaths()
            case 10: NSWorkspace.shared.activateFileViewerSelecting(parent.pane.selected.map(\.url))
            case 11: m.edit()
            default: break
            }
        }
    }
}

final class NativeTable: NSTableView {
    weak var owner: FileTable.Coordinator?
    override func mouseDown(with event: NSEvent) { if let o = owner { o.parent.model.activeLeft = o.parent.isLeft }; super.mouseDown(with: event) }
    override func keyDown(with event: NSEvent) {
        guard let owner else { super.keyDown(with: event); return }
        let m = owner.parent.model; m.activeLeft = owner.parent.isLeft
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" { m.clipboard(); return }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" { m.paste(move: event.modifierFlags.contains(.option)); return }
        if event.keyCode == 36 { m.rename(); return }
        if event.keyCode == 49 { m.inspector.toggle(); return }
        if event.keyCode == 48 { m.activeLeft.toggle(); window?.makeFirstResponder(nil); return }
        if event.keyCode == 125 && event.modifierFlags.contains(.command), let first = owner.parent.pane.selected.first { m.open(first, pane: owner.parent.pane); return }
        super.keyDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let owner else { return nil }
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        if !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        owner.parent.model.activeLeft = owner.parent.isLeft
        let menu = NSMenu()
        for (index, title) in ["打开", "复制到另一栏", "移动到另一栏", "重命名…", "批量重命名…", "移到废纸篓…", "压缩为 ZIP", "解压 ZIP", "编辑标签…", "复制路径", "在 Finder 中显示", "编辑文本"].enumerated() {
            let item = NSMenuItem(title: title, action: #selector(FileTable.Coordinator.menuAction(_:)), keyEquivalent: "")
            item.tag = index; item.target = owner; menu.addItem(item)
        }
        return menu
    }
}

@ViewBuilder func fileMenu(model: Workspace, select: @escaping () -> Void) -> some View {
    Button("复制到另一栏") { select(); model.transfer(move: false) }
    Button("移动到另一栏") { select(); model.transfer(move: true) }
    Button("重命名…") { select(); model.rename() }
    Button("批量重命名…") { select(); model.multiRename() }
    Button("压缩为 ZIP") { select(); model.compress() }
    Button("解压 ZIP") { select(); model.extract() }
    Button("编辑标签…") { select(); model.tags() }
    Button("在 Finder 中显示") { select(); NSWorkspace.shared.activateFileViewerSelecting(model.active.selected.map(\.url)) }
    Divider()
    Button("移到废纸篓…") { select(); model.trash() }
}

struct Inspector: View {
    @ObservedObject var pane: Pane
    @ObservedObject var model: Workspace
    var body: some View {
        VStack(spacing: 0) {
            HStack { Label("预览与信息", systemImage: "info.circle").foregroundStyle(.primary); Spacer() }.font(.system(size: 12, weight: .medium)).padding(14)
            Divider()
            if let item = pane.selected.first {
                if !item.directory { QuickPreview(url: item.url).frame(minHeight: 160, maxHeight: .infinity).id(item.id + String(item.modified.timeIntervalSince1970)) }
                else { Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 76, height: 76).padding(.top, 36); Spacer().frame(height: 24) }
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.name).font(.system(size: 14, weight: .semibold)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    info("类型", item.symlink ? "符号链接" : item.directory ? "文件夹" : item.url.pathExtension.uppercased() + " 文件")
                    info("大小", item.sizeText)
                    info("修改", item.modified.formatted(date: .abbreviated, time: .shortened))
                    info("标签", item.tags.isEmpty ? "无" : item.tags.joined(separator: "、"))
                    Text(item.url.path).font(.system(size: 10)).foregroundStyle(Color(nsColor: Theme.secondaryText)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    HStack { Button("打开") { model.open(item, pane: pane) }; if !item.directory { Button("编辑文本") { model.edit() } } }.buttonStyle(WorkbenchButtonStyle()).controlSize(.small)
                    if pane.selected.count > 1 { Text("已选择 \(pane.selected.count) 项 · 预览第一项").font(.caption).foregroundStyle(Color(nsColor: Theme.secondaryText)) }
                }.padding(16)
                if item.directory { Spacer() }
            } else {
                Spacer()
                Image(systemName: "doc.viewfinder").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(Color(nsColor: Theme.secondaryText))
                Text("选择文件以预览").font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.secondaryText)).padding(.top, 12)
                Text("图片、PDF、音视频及文档").font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 3)
                Spacer()
            }
        }.background(Color(nsColor: Theme.panel))
    }
    func info(_ key: String, _ value: String) -> some View { HStack(alignment: .top) { Text(key).foregroundStyle(Color(nsColor: Theme.secondaryText)).frame(width: 34, alignment: .leading); Text(value).textSelection(.enabled); Spacer(minLength: 0) }.font(.system(size: 11)) }
}

struct QuickPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { let view = QLPreviewView(frame: .zero, style: .normal)!; view.autostarts = false; view.previewItem = url as NSURL; return view }
    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }
}

struct ActivityView: View {
    @ObservedObject var model: Workspace
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack { Text("活动日志").fontWeight(.medium); Spacer(); Button("清空") { model.activities = [] }; Button { model.showActivities = false } label: { Image(systemName: "xmark") } }.font(.system(size: 11)).buttonStyle(WorkbenchButtonStyle()).padding(10)
            ScrollView { LazyVStack(alignment: .leading, spacing: 6) { ForEach(model.activities) { event in HStack(alignment: .top) { Text(event.date.formatted(date: .omitted, time: .standard)).monospacedDigit().foregroundStyle(Color(nsColor: Theme.secondaryText)); Text(event.message).foregroundStyle(event.failed ? Color.red : Color.primary).textSelection(.enabled) }.font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading) } }.padding(.horizontal, 12) }
        }.background(Color(nsColor: Theme.toolbar))
    }
}

struct SyncView: View {
    @ObservedObject var model: Workspace
    @State var selected: Set<String> = []
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("目录比较与同步").font(.title2.bold())
            Text(model.syncDescription).font(.system(size: 11)).textSelection(.enabled)
            Text("按大小与修改时间比较 · 双向同步以较新文件为准 · 旧版本进废纸篓 · 保留目标独有文件").font(.caption).foregroundStyle(Color(nsColor: Theme.secondaryText))
            HStack {
                Picker("方向", selection: $model.syncMode) { ForEach(["当前 → 另一栏", "另一栏 → 当前", "双向（较新优先）"], id: \.self) { Text($0).tag($0) } }.frame(width: 240)
                TextField("排除：*.tmp,node_modules", text: $model.syncExclusions)
                Button("重新比较") { selected = []; model.compare() }.disabled(model.busy)
            }
            List(model.differences) { diff in HStack { Toggle("", isOn: Binding(get: { selected.contains(diff.id) }, set: { if $0 { selected.insert(diff.id) } else { selected.remove(diff.id) } })).labelsHidden().disabled(diff.kind == "跳过链接" || diff.kind.contains("冲突")); Text(diff.relative).lineLimit(1).help(diff.source.path + " → " + diff.destination.path); Spacer(); Text(diff.kind).foregroundStyle(diff.kind.contains("冲突") ? .red : .orange).font(.caption) } }
            HStack { Text("\(model.differences.count) 项差异 · 已选 \(selected.count) 项").foregroundStyle(Color(nsColor: Theme.secondaryText)); Spacer(); Button("关闭") { model.showSync = false }; Button("同步选中项目") { model.sync(selected) }.buttonStyle(.borderedProminent).disabled(selected.isEmpty) }
        }.padding(24).frame(width: 780, height: 520)
        .onAppear { selectSafe() }
        .onChange(of: model.differences.map { $0.id + $0.kind + $0.source.path }) { _, _ in selectSafe() }
        .onChange(of: model.syncMode) { _, _ in selected = []; model.compare() }
        .onChange(of: model.syncExclusions) { _, _ in selected = [] }
    }
    func selectSafe() { selected = Set(model.differences.filter { $0.kind != "跳过链接" && !$0.kind.contains("冲突") }.map(\.id)) }
}

struct EditorView: View {
    let document: EditorDocument
    @ObservedObject var model: Workspace
    @State var text = ""
    var body: some View {
        VStack(spacing: 12) {
            HStack { Text(document.url.lastPathComponent).font(.headline); Spacer(); Text("UTF-8").foregroundStyle(Color(nsColor: Theme.secondaryText)) }
            TextEditor(text: $text).font(.system(size: 13, design: .monospaced)).border(Color.secondary.opacity(0.2))
            HStack { Text("⌘S 保存").font(.caption).foregroundStyle(Color(nsColor: Theme.secondaryText)); Spacer(); Button("取消") { if text == document.text || model.confirm("放弃未保存修改？", document.url.lastPathComponent, button: "放弃") { model.editor = nil } }; Button("保存") { save() }.keyboardShortcut("s").buttonStyle(.borderedProminent) }
        }.padding(20).frame(width: 800, height: 580).onAppear { text = document.text }
    }
    func save() {
        do {
            let current = try FileEngine.entry(document.url)
            guard current.modified == document.date, !current.symlink else { throw FileFailure.message("文件已在外部修改或是符号链接，请关闭后重新打开。") }
            try text.write(to: document.url, atomically: true, encoding: .utf8)
            model.log("已保存：\(document.url.lastPathComponent)"); model.editor = nil; model.refresh()
        } catch { model.report(error) }
    }
}

struct SearchView: View {
    @ObservedObject var model: Workspace
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("搜索结果").font(.title2.bold()); Spacer(); if model.searchRunning { ProgressView().controlSize(.small) }; Text("\(model.searchResults.count) 项") }
            if let error = model.searchError { Text(error).foregroundStyle(.red).font(.caption) }
            List(model.searchResults) { item in Button { model.navigate(item.url.deletingLastPathComponent()); model.showSearch = false } label: { HStack { Image(systemName: item.directory ? "folder.fill" : "doc").foregroundStyle(Theme.accent); VStack(alignment: .leading) { Text(item.name); Text(item.url.path).font(.caption).foregroundStyle(Color(nsColor: Theme.secondaryText)) }; Spacer(); Image(systemName: "arrow.up.forward") } }.buttonStyle(.plain) }
            HStack { Text("点击结果，打开所在目录").font(.caption).foregroundStyle(Color(nsColor: Theme.secondaryText)); Spacer(); Button("关闭") { model.showSearch = false } }
        }.padding(24).frame(width: 780, height: 540)
    }
}
