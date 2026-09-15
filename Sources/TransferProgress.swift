import Foundation
import Darwin

final class CopyProgressContext {
    let report: (Int64) -> Void
    init(_ report: @escaping (Int64) -> Void) { self.report = report }
}

private let copyProgressCallback: copyfile_callback_t = { what, stage, state, _, _, context in
    guard what == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS, let context, let state else { return COPYFILE_CONTINUE }
    var bytes: off_t = 0
    copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &bytes)
    Unmanaged<CopyProgressContext>.fromOpaque(context).takeUnretainedValue().report(Int64(bytes))
    return COPYFILE_CONTINUE
}

extension FileEngine {
    static func transferWithProgress(_ source: URL, to folder: URL, move: Bool, conflict: Conflict, progress: @escaping (Int64, Int64) -> Void) throws -> URL? {
        var target = folder.appendingPathComponent(source.lastPathComponent)
        try validateTransfer(source, target)
        if exists(target) { if conflict == .skip { return nil }; target = unique(target) }
        var srcStat = stat(), dstStat = stat()
        if move, lstat(source.path, &srcStat) == 0, stat(folder.path, &dstStat) == 0, srcStat.st_dev == dstStat.st_dev {
            try fm.moveItem(at: source, to: target); progress(0, 0); return target
        }
        let rootEntry = try entry(source)
        let total = rootEntry.directory && !rootEntry.symlink ? try folderBytes(source) : rootEntry.size
        progress(0, total)
        let staging = folder.appendingPathComponent(".chui-transfer-" + UUID().uuidString)
        defer { try? fm.removeItem(at: staging) }
        var completed: Int64 = 0
        func copy(_ src: URL, _ dst: URL) throws {
            let item = try entry(src)
            if item.directory && !item.symlink {
                try fm.createDirectory(at: dst, withIntermediateDirectories: false)
                for child in try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil) {
                    try copy(child, dst.appendingPathComponent(child.lastPathComponent))
                }
                guard copyfile(src.path, dst.path, nil, copyfile_flags_t(COPYFILE_METADATA | COPYFILE_NOFOLLOW)) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            } else {
                guard let state = copyfile_state_alloc() else { throw POSIXError(.ENOMEM) }
                defer { copyfile_state_free(state) }
                let base = completed
                let context = CopyProgressContext { bytes in progress(min(total, base + bytes), total) }
                copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(context).toOpaque())
                copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(copyProgressCallback, to: UnsafeRawPointer.self))
                let result = withExtendedLifetime(context) { copyfile(src.path, dst.path, state, copyfile_flags_t(COPYFILE_ALL | COPYFILE_NOFOLLOW | COPYFILE_EXCL)) }
                guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                if !item.symlink { completed += item.size }
                progress(min(completed, total), total)
            }
        }
        try copy(source, staging)
        // Publish only a complete copy; FileManager refuses a racing destination.
        try fm.moveItem(at: staging, to: target)
        if move { try fm.removeItem(at: source) }
        progress(total, total)
        return target
    }
}
