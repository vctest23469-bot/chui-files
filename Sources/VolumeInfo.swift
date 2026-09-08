import Foundation

struct BreadcrumbItem: Identifiable, Equatable {
    let title: String
    let url: URL
    var id: String { url.path }
    static func path(to folder: URL, volume: VolumeInfo?) -> [BreadcrumbItem] {
        let folder = folder.standardizedFileURL
        let root = volume?.url ?? URL(fileURLWithPath: "/")
        let prefix = root.path == "/" ? "/" : root.path + "/"
        guard folder.path == root.path || folder.path.hasPrefix(prefix) else {
            return path(to: folder, volume: nil)
        }
        var result = [BreadcrumbItem(title: volume?.name ?? "根目录", url: root)]
        if folder.path == root.path { return result }
        var current = root
        for part in folder.path.dropFirst(prefix.count).split(separator: "/") {
            current.appendPathComponent(String(part))
            result.append(BreadcrumbItem(title: String(part), url: current))
        }
        return result
    }
}

struct VolumeInfo: Identifiable, Equatable {
    let url: URL
    let name: String
    let total: Int64?
    let available: Int64?
    let internalDisk: Bool
    var id: String { url.path }
    var symbol: String { internalDisk ? "internaldrive" : "externaldrive" }
    var totalText: String { Self.capacity(total) }
    var availableText: String { Self.capacity(available) }
    var availableFraction: Double? {
        guard let total, total > 0, let available else { return nil }
        return min(1, max(0, Double(available) / Double(total)))
    }
    static func capacity(_ bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return "暂不可读" }
        let f = ByteCountFormatter()
        f.countStyle = .decimal; f.allowedUnits = [.useGB, .useTB]; f.includesUnit = true
        return f.string(fromByteCount: bytes)
    }
    static let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeURLKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsInternalKey, .volumeIsLocalKey]
    static func read(containing folder: URL) throws -> VolumeInfo {
        let values = try folder.resourceValues(forKeys: keys)
        guard let volume = values.volume else { throw FileFailure.message("无法确定所在磁盘。") }
        return VolumeInfo(url: volume, name: values.volumeName ?? FileManager.default.displayName(atPath: volume.path),
                          total: values.volumeTotalCapacity.map(Int64.init), available: values.volumeAvailableCapacity.map(Int64.init),
                          internalDisk: values.volumeIsInternal ?? false)
    }
    static func mounted() -> [VolumeInfo] {
        var urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        // Disk Arbitration can be unavailable in restricted processes. Verify mount roots
        // through filesystem metadata rather than treating every /Volumes folder as a disk.
        if urls.isEmpty {
            let candidates = [URL(fileURLWithPath: "/")] + ((try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            urls = candidates.filter { url in
                guard let info = try? read(containing: url) else { return false }
                return FileEngine.canonical(url).path == FileEngine.canonical(info.url).path
            }
        }
        var seen = Set<String>()
        return urls.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) != false,
                  let info = try? read(containing: url), seen.insert(info.id).inserted else { return nil }
            return info
        }.sorted { a, b in
            if a.url.path == "/" { return true }
            if b.url.path == "/" { return false }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
