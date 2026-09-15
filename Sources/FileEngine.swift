import Foundation
import Darwin

struct Entry: Identifiable, Hashable {
    let url: URL
    let name: String
    let directory: Bool
    let symlink: Bool
    let size: Int64
    let modified: Date
    let tags: [String]
    var id: String { url.path }
    var sizeText: String { directory ? "—" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

enum EntryOrder {
    static func precedes(_ a: Entry, _ b: Entry, key: String, ascending: Bool, foldersFirst: Bool = false, sizes: [String: Int64] = [:]) -> Bool {
        if foldersFirst && a.directory != b.directory { return a.directory }
        var order: ComparisonResult = .orderedSame
        if key == "大小" {
            let x = a.directory ? sizes[a.id] : a.size, y = b.directory ? sizes[b.id] : b.size
            // Unknown sizes stay at the end in either direction.
            if x == nil && y != nil { return false }; if x != nil && y == nil { return true }
            if let x, let y, x != y { order = x < y ? .orderedAscending : .orderedDescending }
        } else if key == "修改时间", a.modified != b.modified {
            order = a.modified < b.modified ? .orderedAscending : .orderedDescending
        }
        if order == .orderedSame { order = a.name.localizedStandardCompare(b.name) }
        if order == .orderedSame { order = a.id.compare(b.id) }
        return order == (ascending ? .orderedAscending : .orderedDescending)
    }
}

enum FileFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

enum Conflict: String, CaseIterable { case skip = "跳过", keepBoth = "保留两份" }

struct Difference: Identifiable {
    let relative: String
    let source: URL
    let destination: URL
    let kind: String
    let sourceSize: Int64
    let sourceDate: Date
    let targetSize: Int64?
    let targetDate: Date?
    var id: String { relative }
}

enum FileEngine {
    static let fm = FileManager.default
    static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .tagNamesKey]
    static func canonical(_ url: URL) -> URL {
        guard let path = realpath(url.path, nil) else { return url.resolvingSymlinksInPath() }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path))
    }

    static func entry(_ url: URL) throws -> Entry {
        let v = try url.resourceValues(forKeys: keys)
        return Entry(url: url, name: url.lastPathComponent, directory: v.isDirectory == true,
                     symlink: v.isSymbolicLink == true, size: Int64(v.fileSize ?? 0),
                     modified: v.contentModificationDate ?? .distantPast, tags: v.tagNames ?? [])
    }

    static func list(_ folder: URL, hidden: Bool) throws -> [Entry] {
        try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: hidden ? [] : [.skipsHiddenFiles]).map { try entry($0) }
    }

    static func validName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.contains("\0") else {
            throw FileFailure.message("名称不能为空，也不能包含 /、: 或路径跳转。")
        }
    }

    static func exists(_ url: URL) -> Bool { (try? fm.attributesOfItem(atPath: url.path)) != nil }

    static func unique(_ url: URL) -> URL {
        if !exists(url) { return url }
        let ext = url.pathExtension
        let base = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var i = 2
        while true {
            let name = "\(base) \(i)" + (ext.isEmpty ? "" : ".\(ext)")
            let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
            if !exists(candidate) { return candidate }
            i += 1
        }
    }

    static func validateTransfer(_ source: URL, _ destination: URL) throws {
        let src = canonical(source).path
        let dst = canonical(destination.deletingLastPathComponent()).appendingPathComponent(destination.lastPathComponent).path
        guard src != "/", dst != src, !dst.hasPrefix(src + "/") else {
            throw FileFailure.message("不能把项目复制或移动到自身或其子目录：\(source.lastPathComponent)")
        }
    }

    @discardableResult static func transfer(_ source: URL, to folder: URL, move: Bool, conflict: Conflict) throws -> URL? {
        var target = folder.appendingPathComponent(source.lastPathComponent)
        try validateTransfer(source, target)
        if exists(target) {
            if conflict == .skip { return nil }
            target = unique(target)
        }
        // FileManager refuses an existing destination; no implicit overwrite.
        if move { try fm.moveItem(at: source, to: target) }
        else { try fm.copyItem(at: source, to: target) }
        return target
    }

    static func rename(_ source: URL, name: String) throws {
        try validName(name)
        let target = source.deletingLastPathComponent().appendingPathComponent(name)
        if target == source { return }
        guard !exists(target) else { throw FileFailure.message("已存在同名项目：\(name)") }
        try fm.moveItem(at: source, to: target)
    }

    static func create(in folder: URL, name: String, directory: Bool) throws {
        try validName(name)
        let target = folder.appendingPathComponent(name)
        guard !exists(target) else { throw FileFailure.message("已存在同名项目。") }
        if directory { try fm.createDirectory(at: target, withIntermediateDirectories: false) }
        else { try Data().write(to: target, options: .withoutOverwriting) }
    }

    static func run(_ executable: String, _ args: [String], cwd: URL? = nil) throws -> String {
        let p = Process(), output = Pipe()
        p.executableURL = URL(fileURLWithPath: executable); p.arguments = args
        p.currentDirectoryURL = cwd; p.standardOutput = output; p.standardError = output
        try p.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard p.terminationStatus == 0 else { throw FileFailure.message(String(text.prefix(2000))) }
        return text
    }

    static func compress(_ sources: [URL], in folder: URL) throws -> URL {
        guard !sources.isEmpty else { throw FileFailure.message("请先选择项目。") }
        let target = unique(folder.appendingPathComponent(sources.count == 1 ? sources[0].lastPathComponent + ".zip" : "归档.zip"))
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let zip = staging.appendingPathComponent("archive.zip")
        _ = try run("/usr/bin/zip", ["-qry", zip.path, "--"] + sources.map { "./" + $0.lastPathComponent }, cwd: folder)
        try fm.moveItem(at: zip, to: target)
        return target
    }

    static func extract(_ source: URL) throws -> URL {
        guard source.pathExtension.lowercased() == "zip" else { throw FileFailure.message("当前支持 ZIP 解压。") }
        let paths = try run("/usr/bin/unzip", ["-Z1", source.path]).split(separator: "\n")
        guard paths.allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") }) else {
            throw FileFailure.message("压缩包包含不安全的路径，已拒绝解压。")
        }
        let listing = try run("/usr/bin/zipinfo", ["-l", source.path])
        guard !listing.split(separator: "\n").contains(where: { $0.hasPrefix("l") }) else {
            throw FileFailure.message("此压缩包包含符号链接，暂不支持安全解压。")
        }
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        _ = try run("/usr/bin/ditto", ["-x", "-k", source.path, staging.path])
        let target = unique(source.deletingPathExtension())
        try fm.moveItem(at: staging, to: target)
        return target
    }

    // Logical file bytes, including hidden files; never follow symbolic links.
    static func folderBytes(_ root: URL, cancelled: () -> Bool = { false }) throws -> Int64 {
        var failure: Error?
        guard let scan = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], options: [], errorHandler: { _, error in failure = error; return false }) else {
            throw FileFailure.message("无法读取文件夹")
        }
        var total: Int64 = 0
        for case let url as URL in scan {
            if cancelled() { throw FileFailure.message("计算已取消") }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true { scan.skipDescendants(); continue }
            if values.isDirectory != true { total += Int64(values.fileSize ?? 0) }
        }
        if let failure { throw failure }
        return total
    }
    static func tree(_ root: URL, hidden: Bool) throws -> [String: Entry] {
        var result: [String: Entry] = [:]
        var scanError: Error?
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: hidden ? [] : [.skipsHiddenFiles], errorHandler: { _, error in scanError = error; return false }) else {
            throw FileFailure.message("无法扫描目录：\(root.path)")
        }
        for case let url as URL in enumerator {
            let item = try entry(url)
            if item.symlink { enumerator.skipDescendants() }
            result[String(url.path.dropFirst(root.path.count + (root.path == "/" ? 0 : 1)))] = item
        }
        if let error = scanError { throw error }
        return result
    }

    static func isExcluded(_ relative: String, patterns: [String]) -> Bool {
        let parts = relative.split(separator: "/").map(String.init)
        return patterns.contains { pattern in
            parts.contains { fnmatch(pattern, $0, 0) == 0 } || fnmatch(pattern, relative, 0) == 0
        }
    }

    static func compare(_ source: URL, _ target: URL, hidden: Bool, excluding: [String] = []) throws -> [Difference] {
        let source = canonical(source)
        let target = canonical(target)
        try validateTransfer(source, target)
        try validateTransfer(target, source)
        let left = try tree(source, hidden: hidden), right = try tree(target, hidden: hidden)
        return left.keys.sorted().compactMap { path in
            if isExcluded(path, patterns: excluding) { return nil }
            let l = left[path]!, r = right[path]
            let kind: String
            if l.symlink || r?.symlink == true { kind = "跳过链接" }
            else if r == nil { kind = l.directory ? "新增目录" : "新增文件" }
            else if l.directory != r!.directory { kind = "类型冲突" }
            else if l.directory { return nil }
            else if l.size != r!.size || abs(l.modified.timeIntervalSince(r!.modified)) > 1 { kind = "内容待更新" }
            else { return nil }
            return Difference(relative: path, source: l.url, destination: target.appendingPathComponent(path), kind: kind, sourceSize: l.size, sourceDate: l.modified, targetSize: r?.size, targetDate: r?.modified)
        }
    }

    static func synchronize(_ diff: Difference) throws {
        guard diff.kind != "跳过链接", !diff.kind.contains("冲突") else { throw FileFailure.message("需手动处理：\(diff.relative)") }
        let src = try entry(diff.source)
        guard src.size == diff.sourceSize, src.modified == diff.sourceDate, !src.symlink else { throw FileFailure.message("源文件已变化，请重新比较：\(diff.relative)") }
        if let previousDate = diff.targetDate {
            let current = try entry(diff.destination)
            guard current.modified == previousDate, current.size == diff.targetSize, !current.symlink else { throw FileFailure.message("目标已变化，请重新比较：\(diff.relative)") }
        } else if exists(diff.destination) { throw FileFailure.message("目标已出现同名项目，请重新比较。") }
        // Verify every existing parent, preventing a changed parent from redirecting writes via symlinks.
        var parentPath = diff.destination.deletingLastPathComponent().path
        while parentPath != "/" && !parentPath.isEmpty {
            if let attrs = try? fm.attributesOfItem(atPath: parentPath), attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                throw FileFailure.message("目标父目录包含符号链接。")
            }
            let next = (parentPath as NSString).deletingLastPathComponent
            guard next != parentPath else { throw FileFailure.message("无法解析目标父路径。") }
            parentPath = next
        }
        try fm.createDirectory(at: diff.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if src.directory {
            try fm.createDirectory(at: diff.destination, withIntermediateDirectories: false)
            return
        }
        let staging = diff.destination.deletingLastPathComponent().appendingPathComponent(".chui-" + UUID().uuidString)
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: diff.source, to: staging)
        if exists(diff.destination) {
            var trashed: NSURL?
            try fm.trashItem(at: diff.destination, resultingItemURL: &trashed)
            do { try fm.moveItem(at: staging, to: diff.destination) }
            catch {
                if let old = trashed { try? fm.moveItem(at: old as URL, to: diff.destination) }
                throw error
            }
        } else { try fm.moveItem(at: staging, to: diff.destination) }
    }
}
