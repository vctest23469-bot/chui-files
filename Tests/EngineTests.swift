import Foundation
import Darwin

@main struct EngineTests {
    static func main() throws {
        setbuf(stdout, nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("chui-files-tests-" + UUID().uuidString)
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var passed = 0
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw FileFailure.message("FAIL: " + message) }
            passed += 1; print("PASS: " + message)
        }
        func rejects(_ message: String, _ operation: () throws -> Void) throws {
            do { try operation() } catch { passed += 1; print("PASS: " + message); return }
            throw FileFailure.message("FAIL: " + message)
        }
        try FileEngine.create(in: a, name: "中文 空格.txt", directory: false)
        let file = a.appendingPathComponent("中文 空格.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        try FileEngine.create(in: a, name: ".hidden", directory: false)
        try check(try FileEngine.list(a, hidden: false).count == 1, "隐藏文件默认排除")
        try check(try FileEngine.list(a, hidden: true).count == 2, "隐藏文件开关")
        try rejects("拒绝路径穿越名称") { try FileEngine.create(in: a, name: "../escape", directory: false) }
        try rejects("拒绝空名称") { try FileEngine.validName("") }
        try rejects("拒绝复制到自身") { _ = try FileEngine.transfer(file, to: a, move: false, conflict: .skip) }
        let child = a.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        try rejects("拒绝复制目录到其子目录") { _ = try FileEngine.transfer(a, to: child, move: false, conflict: .skip) }
        let copied = try FileEngine.transfer(file, to: b, move: false, conflict: .skip)!
        try check(try String(contentsOf: copied, encoding: .utf8) == "original", "复制保留中文和空格文件名及内容")
        try check(try FileEngine.transfer(file, to: b, move: false, conflict: .skip) == nil, "冲突跳过不覆盖")
        try check(try FileEngine.transfer(file, to: b, move: false, conflict: .keepBoth)?.lastPathComponent == "中文 空格 2.txt", "冲突保留两份")
        try rejects("创建文件不会覆盖已有内容") { try FileEngine.create(in: b, name: "中文 空格.txt", directory: false) }
        try FileEngine.rename(copied, name: "renamed.txt")
        try check(FileEngine.exists(b.appendingPathComponent("renamed.txt")) && !FileEngine.exists(copied), "重命名移动原文件")
        let moved = try FileEngine.transfer(b.appendingPathComponent("renamed.txt"), to: a, move: true, conflict: .skip)!
        try check(FileEngine.exists(moved) && !FileEngine.exists(b.appendingPathComponent("renamed.txt")), "移动后原路径消失")
        let zip = try FileEngine.compress([file, moved], in: a)
        let extracted = try FileEngine.extract(zip)
        try check(try String(contentsOf: extracted.appendingPathComponent(file.lastPathComponent), encoding: .utf8) == "original", "ZIP 多文件压缩解压真实往返")
        let symlink = a.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: b)
        let linkedZip = try FileEngine.compress([symlink], in: a)
        try rejects("拒绝解压含符号链接的 ZIP") { _ = try FileEngine.extract(linkedZip) }
        let syncSource = root.appendingPathComponent("source"), syncTarget = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: syncSource.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: syncTarget, withIntermediateDirectories: true)
        try "sync value".write(to: syncSource.appendingPathComponent("nested/file.txt"), atomically: true, encoding: .utf8)
        try "keep me".write(to: syncTarget.appendingPathComponent("only-target.txt"), atomically: true, encoding: .utf8)
        let plan = try FileEngine.compare(syncSource, syncTarget, hidden: false)
        try check(plan.count == 2, "递归比较识别新增目录与文件")
        for difference in plan { try FileEngine.synchronize(difference) }
        try check(try String(contentsOf: syncTarget.appendingPathComponent("nested/file.txt"), encoding: .utf8) == "sync value", "同步真实复制子目录内容")
        try check(FileEngine.exists(syncTarget.appendingPathComponent("only-target.txt")), "同步保留目标独有文件")
        try check(try FileEngine.compare(syncSource, syncTarget, hidden: false).isEmpty, "同步后比较收敛")
        try "updated source".write(to: syncSource.appendingPathComponent("nested/file.txt"), atomically: true, encoding: .utf8)
        let stale = try FileEngine.compare(syncSource, syncTarget, hidden: false)
        try "external changed target".write(to: syncTarget.appendingPathComponent("nested/file.txt"), atomically: true, encoding: .utf8)
        try rejects("同步拒绝使用过期差异覆盖外部修改") { try FileEngine.synchronize(stale[0]) }
        try rejects("同步拒绝重叠根目录") { _ = try FileEngine.compare(syncSource, syncSource.appendingPathComponent("nested"), hidden: false) }
        try check(FileEngine.isExcluded("node_modules/package/index.js", patterns: ["node_modules"]), "同步排除目录及其后代")
        try check(FileEngine.isExcluded("nested/cache.tmp", patterns: ["*.tmp"]), "同步排除通配符匹配")
        try check(!FileEngine.isExcluded("nested/cache.txt", patterns: ["*.tmp"]), "同步排除不误匹配普通文件")
        try check(try FileEngine.compare(syncSource, syncTarget, hidden: false, excluding: ["nested"]).isEmpty, "排除规则实际作用于差异计划")
        try rejects("禁止复制根目录到其后代") { try FileEngine.validateTransfer(URL(fileURLWithPath: "/"), root.appendingPathComponent("root-copy")) }
        print("\n\(passed) 项文件安全与功能测试全部通过。")
    }
}
