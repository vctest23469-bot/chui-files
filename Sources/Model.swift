import SwiftUI
import AppKit

final class Pane: ObservableObject {
    @Published var folder: URL
    @Published var entries: [Entry] = []
    @Published var selection: Set<String> = []
    @Published var filter = ""
    @Published var searching = false
    @Published var searchQuery = ""
    @Published var searchResults: [Entry] = []
    @Published var searchRunning = false
    @Published var searchError: String?
    @Published var searchFocus = UUID()
    var searchGeneration = UUID()
    var pendingSearch: DispatchWorkItem?
    func endSearch() {
        pendingSearch?.cancel(); pendingSearch = nil
        searchGeneration = UUID(); searching = false; searchRunning = false
        searchQuery = ""; searchResults = []; searchError = nil; selection = []
        calculateFolderSizes(entries)
    }
    @Published var loading = false
    @Published var error: String?
    @Published var volume: VolumeInfo?
    @Published var tabs: [URL]
    @Published var tabIndex = 0
    @Published var grid = false
    @Published var sort = "名称"
    @Published var ascending = true
    @Published var foldersFirst = UserDefaults.standard.bool(forKey: "foldersFirst")
    var history: [URL] = []
    var future: [URL] = []
    var generation = UUID()
    var watcher: DispatchSourceFileSystemObject?
    var refreshWork: DispatchWorkItem?
    var watchedPath = ""
    var watchedHidden = false
    let key: String
    init(key: String, fallback: URL) {
        self.key = key
        let saved = UserDefaults.standard.stringArray(forKey: key + "Tabs") ?? []
        var initial = saved.map { URL(fileURLWithPath: $0) }.filter { (try? FileEngine.entry($0).directory) == true }
        if initial.isEmpty { initial = [fallback] }
        tabs = initial
        folder = initial[0]
    }
    @Published var folderSizes: [String: Int64] = [:]
    @Published var sizeErrors: Set<String> = []
    @Published var sizeRevision = 0
    private var sizeCancellation = Cancellation()
    private static let sizeQueue = DispatchQueue(label: "chui.folder-sizes", qos: .utility)
    func sizeText(_ entry: Entry) -> String {
        guard entry.directory else { return entry.sizeText }
        if entry.symlink { return "链接" }
        if sizeErrors.contains(entry.id) { return "无法完整读取" }
        guard let bytes = folderSizes[entry.id] else { return "计算中…" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    func calculateFolderSizes(_ files: [Entry]) {
        sizeCancellation.stop(); sizeCancellation = Cancellation()
        let cancellation = sizeCancellation
        folderSizes = [:]; sizeErrors = []; sizeRevision += 1
        Self.sizeQueue.async { [weak self] in
            for entry in files where entry.directory && !entry.symlink {
                if cancellation.cancelled { return }
                let result = Result { try FileEngine.folderBytes(entry.url, cancelled: { cancellation.cancelled }) }
                DispatchQueue.main.async { [weak self] in
                    guard let self, !cancellation.cancelled else { return }
                    switch result {
                    case .success(let bytes): self.folderSizes[entry.id] = bytes
                    case .failure: self.sizeErrors.insert(entry.id)
                    }
                    self.sizeRevision += 1
                }
            }
        }
    }
    var visible: [Entry] {
        (searching && !searchQuery.isEmpty ? searchResults : entries).filter { filter.isEmpty || $0.name.localizedStandardContains(filter) || $0.tags.contains(where: { $0.localizedStandardContains(filter) }) }.sorted {
            EntryOrder.precedes($0, $1, key: sort, ascending: ascending, foldersFirst: foldersFirst, sizes: folderSizes)
        }
    }
    var selected: [Entry] { visible.filter { selection.contains($0.id) } }
    func load(hidden: Bool) {
        watch(hidden: hidden)
        let token = UUID(); generation = token
        let url = folder
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let volume = try? VolumeInfo.read(containing: url)
            let result = Result { try FileEngine.list(url, hidden: hidden) }
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                self.loading = false
                self.volume = volume
                switch result {
                case .success(let files): self.entries = files; self.error = nil; if !self.searching { self.calculateFolderSizes(files) }; if !self.searching { self.selection.formIntersection(Set(files.map(\.id))) }
                case .failure(let error): self.entries = []; self.error = error.localizedDescription
                }
            }
        }
    }
    func go(_ url: URL, hidden: Bool, record: Bool = true) {
        sizeCancellation.stop()
        endSearch()
        if record && url != folder { history.append(folder); future = [] }
        folder = url.standardizedFileURL; tabs[tabIndex] = folder
        filter = ""; selection = []; entries = []; volume = nil
        save(); load(hidden: hidden)
    }
    func back(hidden: Bool) { if let last = history.popLast() { future.append(folder); go(last, hidden: hidden, record: false) } }
    func forward(hidden: Bool) { if let next = future.popLast() { history.append(folder); go(next, hidden: hidden, record: false) } }
    func newTab(hidden: Bool) { tabs.append(folder); tabIndex = tabs.count - 1; save() }
    func closeTab(_ index: Int, hidden: Bool) {
        guard tabs.count > 1 else { return }
        tabs.remove(at: index)
        if index < tabIndex { tabIndex -= 1 } else if index == tabIndex { tabIndex = min(index, tabs.count - 1) }
        go(tabs[tabIndex], hidden: hidden, record: false)
    }
    func selectTab(_ index: Int, hidden: Bool) { tabIndex = index; history = []; future = []; go(tabs[index], hidden: hidden, record: false) }
    func save() { UserDefaults.standard.set(tabs.map(\.path), forKey: key + "Tabs") }
    func watch(hidden: Bool) {
        watchedHidden = hidden
        guard watchedPath != folder.path else { return }
        watcher?.cancel(); watchedPath = folder.path
        let descriptor = Darwin.open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { watchedPath = ""; return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            self?.refreshWork?.cancel()
            let work = DispatchWorkItem { [weak self] in guard let self else { return }; self.load(hidden: self.watchedHidden) }
            self?.refreshWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
        source.setCancelHandler { Darwin.close(descriptor) }; source.resume(); watcher = source
    }
    deinit { sizeCancellation.stop(); watcher?.cancel(); refreshWork?.cancel() }
}

struct Activity: Identifiable {
    let id = UUID()
    let date = Date()
    let message: String
    let failed: Bool
}

final class Cancellation {
    private let lock = NSLock()
    private var stopped = false
    func stop() { lock.lock(); stopped = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

final class Workspace: ObservableObject {
    @Published var volumes: [VolumeInfo] = []
    let left = Pane(key: "left", fallback: FileManager.default.homeDirectoryForCurrentUser)
    let right = Pane(key: "right", fallback: URL(fileURLWithPath: "/Volumes"))
    @Published var activeLeft = true
    @Published var foldersFirst = UserDefaults.standard.bool(forKey: "foldersFirst") {
        didSet {
            UserDefaults.standard.set(foldersFirst, forKey: "foldersFirst")
            left.foldersFirst = foldersFirst; right.foldersFirst = foldersFirst
        }
    }
    @Published var hidden = UserDefaults.standard.bool(forKey: "hidden")
    @Published var inspector = true
    @Published var showActivities = false
    @Published var activities: [Activity] = []
    @Published var status = "就绪"
    @Published var busy = false
    @Published var transferDetail = ""
    @Published var transferFraction: Double?
    @Published var completed = 0
    @Published var total = 0
    @Published var favorites: [String] = UserDefaults.standard.stringArray(forKey: "favorites") ?? []
    @Published var recents: [String] = UserDefaults.standard.stringArray(forKey: "recents") ?? []
    @Published var differences: [Difference] = []
    @Published var showSync = false
    @Published var syncDescription = ""
    @Published var syncMode = "当前 → 另一栏"
    @Published var syncExclusions = UserDefaults.standard.string(forKey: "syncExclusions") ?? ".DS_Store"
    @Published var conflict = Conflict.skip
    @Published var linked = false
    @Published var editor: EditorDocument?
    @Published var appearance = UserDefaults.standard.string(forKey: "appearance") ?? "系统"
    @Published var accent = UserDefaults.standard.string(forKey: "accent") ?? "系统蓝"
    @Published var showSettings = false
    @Published var syncPresets = (UserDefaults.standard.data(forKey: "syncPresets").flatMap { try? JSONDecoder().decode([SyncPreset].self, from: $0) }) ?? []
    var cancellation = Cancellation()
    @Published var undoMoves: [(URL, URL)] = []
    var monitor: Any?
    private var volumeTimer: Timer?
    private var volumeObservers: [NSObjectProtocol] = []
    private var volumesLoading = false
    var active: Pane { activeLeft ? left : right }
    var other: Pane { activeLeft ? right : left }

    init() {
        refresh()
        volumeTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refreshVolumes() }
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            volumeObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshVolumes() })
        }
    }
    deinit { volumeTimer?.invalidate(); for observer in volumeObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
    func refresh() {
        left.load(hidden: hidden); right.load(hidden: hidden); refreshVolumes()
        for pane in [left, right] where pane.searching && !pane.searchQuery.isEmpty { runSearch(in: pane) }
    }
    func refreshVolumes() {
        guard !volumesLoading else { return }
        volumesLoading = true
        let leftPath = left.folder, rightPath = right.folder
        DispatchQueue.global(qos: .utility).async {
            let volumes = VolumeInfo.mounted()
            let l = try? VolumeInfo.read(containing: leftPath), r = try? VolumeInfo.read(containing: rightPath)
            DispatchQueue.main.async {
                self.volumes = volumes; self.volumesLoading = false
                if self.left.folder == leftPath { self.left.volume = l }
                if self.right.folder == rightPath { self.right.volume = r }
            }
        }
    }
    func log(_ message: String, failed: Bool = false) {
        status = message; activities.insert(Activity(message: message, failed: failed), at: 0)
        if activities.count > 500 { activities.removeLast() }
    }
    func report(_ error: Error) { log(error.localizedDescription, failed: true); alert("操作未完成", error.localizedDescription) }
    func alert(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message; alert.runModal()
    }
    func confirm(_ title: String, _ message: String, button: String = "继续") -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: button); alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
    func prompt(_ title: String, value: String = "", detail: String = "") -> String? {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        let input = NSTextField(string: value); input.frame = NSRect(x: 0, y: 0, width: 380, height: 25)
        alert.accessoryView = input; alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = input
        return alert.runModal() == .alertFirstButtonReturn ? input.stringValue : nil
    }
    func navigate(_ url: URL, pane: Pane? = nil) {
        (pane ?? active).go(url, hidden: hidden)
        recents.removeAll { $0 == url.path }; recents.insert(url.path, at: 0); recents = Array(recents.prefix(8))
        UserDefaults.standard.set(recents, forKey: "recents")
    }
    func open(_ entry: Entry, pane: Pane) {
        activeLeft = pane === left
        let isFolder = entry.directory || (entry.symlink && (try? FileEngine.entry(FileEngine.canonical(entry.url)).directory) == true)
        if isFolder && entry.url.pathExtension.lowercased() != "app" {
            if linked {
                let paired = other.folder.appendingPathComponent(entry.name)
                if (try? FileEngine.entry(paired).directory) == true { other.go(paired, hidden: hidden) }
            }
            navigate(entry.url, pane: pane)
        } else { NSWorkspace.shared.open(entry.url) }
    }
    func goTo() {
        if let path = prompt("前往文件夹", value: active.folder.path) {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            if (try? FileEngine.entry(url).directory) == true { navigate(url) }
            else { alert("无法打开", "该路径不是可访问的文件夹。") }
        }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { navigate(url) }
    }
    func addFavorite() {
        let path = active.folder.path
        if !favorites.contains(path) { favorites.append(path); saveFavorites() }
    }
    func saveFavorites() { UserDefaults.standard.set(favorites, forKey: "favorites") }
    func toggleHidden() { hidden.toggle(); UserDefaults.standard.set(hidden, forKey: "hidden"); refresh() }

    func batch(_ title: String, items: [URL], action: @escaping (URL) throws -> String) {
        guard !busy, !items.isEmpty else { return }
        transferFraction = nil; transferDetail = ""
        busy = true; total = items.count; completed = 0; status = title
        cancellation = Cancellation(); let token = cancellation
        DispatchQueue.global(qos: .userInitiated).async {
            var succeeded = 0, failures = 0
            for (index, url) in items.enumerated() {
                if token.cancelled { break }
                do {
                    let message = try action(url); succeeded += 1
                    DispatchQueue.main.async { self.log(message); self.completed = index + 1 }
                } catch {
                    failures += 1; let message = "\(url.lastPathComponent)：\(error.localizedDescription)"
                    DispatchQueue.main.async { self.log(message, failed: true); self.completed = index + 1 }
                }
            }
            let summary = "\(title)：处理 \(succeeded) 项，失败 \(failures) 项" + (token.cancelled ? "（已取消后续项目）" : "")
            DispatchQueue.main.async { self.busy = false; self.transferFraction = nil; self.transferDetail = ""; self.log(summary, failed: failures > 0); self.refresh(); if failures > 0 { self.showActivities = true } }
        }
    }
    func transfer(move: Bool, urls: [URL]? = nil, target: URL? = nil) {
        let sources = urls ?? active.selected.map(\.url), destination = target ?? other.folder, policy = conflict
        guard !sources.isEmpty, !busy else { return }
        if move && !confirm("移动 \(sources.count) 个项目？", "目标：\(destination.path)\n同名处理：\(policy.rawValue)", button: "移动") { return }
        batch(move ? "移动" : "复制", items: sources) { url in
            let start = Date(); var lastUpdate = Date.distantPast
            DispatchQueue.main.async { self.transferDetail = "正在准备：" + url.lastPathComponent; self.transferFraction = nil }
            if let result = try FileEngine.transferWithProgress(url, to: destination, move: move, conflict: policy, progress: { bytes, total in
                let now = Date()
                guard now.timeIntervalSince(lastUpdate) >= 0.15 || bytes == total else { return }
                lastUpdate = now
                let elapsed = max(0.01, now.timeIntervalSince(start)), speed = Double(bytes) / elapsed
                let format: (Int64) -> String = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                let eta = speed > 0 ? " · 约剩 \(Int(Double(max(0, total - bytes)) / speed)) 秒" : ""
                let detail = "\(url.lastPathComponent) · \(format(bytes)) / \(format(total)) · \(format(Int64(speed)))/秒" + eta
                DispatchQueue.main.async { self.transferFraction = total > 0 ? Double(bytes) / Double(total) : nil; self.transferDetail = detail }
            }) {
                if move { DispatchQueue.main.async { self.undoMoves.append((result, url)) } }
                return "\(move ? "已移动" : "已复制")：\(url.lastPathComponent) → \(result.path)"
            }
            return "跳过同名项目：\(url.lastPathComponent)"
        }
    }
    func trash() {
        let sources = active.selected.map(\.url)
        guard !sources.isEmpty, !busy, confirm("移到废纸篓？", "共 \(sources.count) 项。可通过撤销或系统废纸篓恢复。", button: "移到废纸篓") else { return }
        batch("移到废纸篓", items: sources) { url in
            var result: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &result)
            if let result { DispatchQueue.main.async { self.undoMoves.append((result as URL, url)) } }
            return "已移到废纸篓：\(url.lastPathComponent)"
        }
    }
    func undo() {
        guard !busy, let pair = undoMoves.last else { return }
        do {
            guard !FileEngine.exists(pair.1) else { throw FileFailure.message("原路径已被占用，无法撤销。") }
            try FileManager.default.moveItem(at: pair.0, to: pair.1); undoMoves.removeLast(); log("已恢复：\(pair.1.lastPathComponent)"); refresh()
        } catch { report(error) }
    }
    func create(directory: Bool) {
        guard !busy, let name = prompt(directory ? "新建文件夹" : "新建文件", value: directory ? "未命名文件夹" : "未命名.txt") else { return }
        do { try FileEngine.create(in: active.folder, name: name, directory: directory); log("已新建：\(name)"); refresh() } catch { report(error) }
    }
    func rename() {
        guard !busy, let first = active.selected.first, active.selected.count == 1,
              let name = prompt("重命名", value: first.name) else { return }
        do { try FileEngine.rename(first.url, name: name); undoMoves.append((first.url.deletingLastPathComponent().appendingPathComponent(name), first.url)); log("已重命名：\(name)"); refresh() } catch { report(error) }
    }
    func multiRename() {
        let sources = active.selected
        guard !busy, !sources.isEmpty, let pattern = prompt("批量重命名", value: "文件-{n}", detail: "{name} 原名（不含扩展名），{n} 从 1 开始，{ext} 扩展名。未写 {ext} 时自动保留扩展名。") else { return }
        let pairs = sources.enumerated().map { index, entry -> (URL, String) in
            let ext = entry.directory ? "" : entry.url.pathExtension
            let name = ext.isEmpty ? entry.name : entry.url.deletingPathExtension().lastPathComponent
            var result = pattern.replacingOccurrences(of: "{name}", with: name).replacingOccurrences(of: "{n}", with: String(index + 1)).replacingOccurrences(of: "{ext}", with: ext)
            if !pattern.contains("{ext}") && !ext.isEmpty { result += "." + ext }
            return (entry.url, result)
        }
        do {
            for pair in pairs { try FileEngine.validName(pair.1); if pair.0.lastPathComponent != pair.1 && FileEngine.exists(pair.0.deletingLastPathComponent().appendingPathComponent(pair.1)) { throw FileFailure.message("名称冲突：\(pair.1)") } }
            guard Set(pairs.map { $0.1.lowercased() }).count == pairs.count else { throw FileFailure.message("新名称重复。") }
            let preview = pairs.prefix(15).map { "\($0.0.lastPathComponent) → \($0.1)" }.joined(separator: "\n")
            guard confirm("预览 \(pairs.count) 项重命名", preview, button: "执行重命名") else { return }
            batch("批量重命名", items: pairs.map { $0.0 }) { url in
                let name = pairs.first { $0.0 == url }!.1
                try FileEngine.rename(url, name: name)
                DispatchQueue.main.async { self.undoMoves.append((url.deletingLastPathComponent().appendingPathComponent(name), url)) }
                return "已重命名：\(name)"
            }
        } catch { report(error) }
    }
    func clipboard() { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(active.selected.map { $0.url as NSURL }) }
    func paste(move: Bool = false) {
        let urls = (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        transfer(move: move, urls: urls, target: active.folder)
    }
    func copyPaths() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(active.selected.map { $0.url.path }.joined(separator: "\n"), forType: .string) }
    func compress() {
        let sources = active.selected.map(\.url), folder = active.folder
        guard !sources.isEmpty else { return }
        batch("压缩", items: [folder]) { _ in let target = try FileEngine.compress(sources, in: folder); return "已压缩：\(target.lastPathComponent)" }
    }
    func extract() { batch("解压", items: active.selected.map(\.url)) { "已解压：\(try FileEngine.extract($0).lastPathComponent)" } }
    func tags() {
        let sources = active.selected.map(\.url)
        guard !sources.isEmpty, let tags = prompt("编辑标签", value: active.selected.first?.tags.joined(separator: ", ") ?? "", detail: "用英文逗号分隔，留空清除。将应用到全部选中项目。") else { return }
        let names = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        batch("标签", items: sources) { url in try (url as NSURL).setResourceValue(names, forKey: .tagNamesKey); return "已更新标签：\(url.lastPathComponent)" }
    }
    func edit() {
        guard let item = active.selected.first, !item.directory else { return }
        do {
            guard item.size < 2_000_000 else { throw FileFailure.message("内置编辑器仅支持 2 MB 以内的 UTF-8 文本。") }
            let text = try String(contentsOf: item.url, encoding: .utf8)
            editor = EditorDocument(url: item.url, text: text, date: item.modified)
        } catch { report(error) }
    }
    func compare() {
        guard !busy else { return }
        let source = syncMode == "另一栏 → 当前" ? other.folder : active.folder
        let target = syncMode == "另一栏 → 当前" ? active.folder : other.folder
        let includeHidden = hidden, mode = syncMode
        let excludes = syncExclusions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        UserDefaults.standard.set(syncExclusions, forKey: "syncExclusions")
        syncDescription = "\(source.path)  \(mode.hasPrefix("双向") ? "↔" : "→")  \(target.path)"; busy = true; status = "正在比较目录…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () throws -> [Difference] in
                let forward = try FileEngine.compare(source, target, hidden: includeHidden, excluding: excludes)
                guard mode.hasPrefix("双向") else { return forward }
                let backward = try FileEngine.compare(target, source, hidden: includeHidden, excluding: excludes)
                var merged = forward.filter { diff in diff.targetDate == nil || diff.kind != "内容待更新" || diff.sourceDate > (diff.targetDate ?? .distantPast) }
                for diff in backward where diff.targetDate == nil || (diff.kind == "内容待更新" && diff.sourceDate > (diff.targetDate ?? .distantPast)) {
                    if !merged.contains(where: { $0.relative == diff.relative }) { merged.append(diff) }
                }
                for diff in forward where diff.kind == "内容待更新" && diff.sourceDate == diff.targetDate {
                    merged.append(Difference(relative: diff.relative, source: diff.source, destination: diff.destination, kind: "两侧冲突", sourceSize: diff.sourceSize, sourceDate: diff.sourceDate, targetSize: diff.targetSize, targetDate: diff.targetDate))
                }
                return merged.sorted { $0.relative < $1.relative }
            }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let diff): self.differences = diff; self.showSync = true; self.log("比较完成：\(diff.count) 项差异")
                case .failure(let error): self.report(error)
                }
            }
        }
    }
    func sync(_ selected: Set<String>) {
        let plan = differences.filter { selected.contains($0.id) }
        guard !plan.isEmpty, confirm("同步 \(plan.count) 项？", "更新项的旧文件将进入废纸篓。不删除目标独有文件。", button: "同步") else { return }
        showSync = false
        batch("同步", items: plan.map(\.source)) { url in
            let diff = plan.first { $0.source == url }!; try FileEngine.synchronize(diff); return "已同步：\(diff.relative)"
        }
    }
    func search() {
        active.searching = true; active.filter = ""; active.searchFocus = UUID()
    }
    func scheduleSearch(in pane: Pane) {
        pane.pendingSearch?.cancel(); pane.searchGeneration = UUID()
        pane.searchResults = []; pane.searchError = nil; pane.selection = []
        guard pane.searching, !pane.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pane.searchRunning = false; return
        }
        pane.searchRunning = true
        let work = DispatchWorkItem { [weak self, weak pane] in
            guard let self, let pane, pane.searching else { return }
            self.runSearch(in: pane)
        }
        pane.pendingSearch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    func runSearch(in pane: Pane) {
        pane.pendingSearch?.cancel(); pane.pendingSearch = nil

        let query = pane.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = pane.folder, includeHidden = hidden, token = UUID()
        pane.searchGeneration = token; pane.searchResults = []; pane.searchError = nil; pane.selection = []
        guard !query.isEmpty else { pane.searchRunning = false; return }
        pane.searchRunning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try FileEngine.tree(root, hidden: includeHidden).values.filter { item in
                    if query.hasPrefix("内容:") {
                        let term = String(query.dropFirst(3))
                        guard !term.isEmpty, !item.directory, !item.symlink, item.size <= 10_000_000 else { return false }
                        return (try? String(contentsOf: item.url, encoding: .utf8).localizedStandardContains(term)) ?? false
                    }
                    return item.name.localizedStandardContains(query)
                }.sorted { $0.url.path < $1.url.path }
            }
            DispatchQueue.main.async {
                guard pane.searchGeneration == token, pane.searching, pane.folder == root else { return }
                pane.searchRunning = false
                switch result { case .success(let files): pane.searchResults = files; pane.calculateFolderSizes(files)
                case .failure(let error): pane.searchError = error.localizedDescription }
            }
        }
    }

}

struct EditorDocument: Identifiable { let id = UUID(); let url: URL; var text: String; let date: Date }
