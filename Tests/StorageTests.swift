import Foundation

@main struct StorageTests {
    static func main() throws {
        var passed = 0
        func check(_ value: Bool, _ message: String) throws {
            guard value else { throw FileFailure.message("FAIL: " + message) }
            passed += 1; print("PASS: " + message)
        }
        let mounted = VolumeInfo.mounted()
        try check(!mounted.isEmpty, "读取当前实际挂载卷")
        try check(Set(mounted.map(\.id)).count == mounted.count, "设备列表无重复卷")
        for volume in mounted {
            try check(!volume.name.isEmpty && volume.name != "/", "设备使用卷名称：\(volume.name)")
            let output = try FileEngine.run("/bin/df", ["-k", volume.url.path])
            let columns = output.split(separator: "\n").last!.split(whereSeparator: { $0.isWhitespace })
            let total = Int64(columns[1])! * 1024, free = Int64(columns[3])! * 1024
            try check(volume.total == total, "\(volume.name) 总容量与 df 字节数一致")
            try check(abs((volume.available ?? -1) - free) < 256 * 1024 * 1024, "\(volume.name) 可用容量与 df 一致（允许采样期间变化）")
            print("VOLUME \(volume.name) | total=\(volume.totalText) | available=\(volume.availableText) | \(volume.url.path)")
        }
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let nested = try VolumeInfo.read(containing: current)
        try check(mounted.contains { $0.id == nested.id }, "子目录正确关联到设备卷")
        let missing = VolumeInfo(url: current, name: "missing", total: nil, available: nil, internalDisk: false)
        try check(missing.availableText == "暂不可读" && missing.availableFraction == nil, "读取失败不显示虚假的零容量")
        let zero = VolumeInfo(url: current, name: "empty", total: 0, available: 0, internalDisk: false)
        try check(zero.availableFraction == nil, "零总容量不除零")
        print("\(passed) 项存储信息测试通过。")
    }
}
