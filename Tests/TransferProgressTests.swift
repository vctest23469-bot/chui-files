import Foundation
import Darwin
@main struct TransferProgressTests {
 static func main() throws {
  let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try fm.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? fm.removeItem(at: root) }
  let src = root.appendingPathComponent("src"), dst = root.appendingPathComponent("dst")
  try fm.createDirectory(at: src, withIntermediateDirectories: true); try fm.createDirectory(at: dst, withIntermediateDirectories: true)
  let data = Data(repeating: 97, count: 8 * 1024 * 1024), file = src.appendingPathComponent("大文件.bin")
  try data.write(to: file)
  var samples: [Int64] = []
  let result = try FileEngine.transferWithProgress(file, to: dst, move: false, conflict: .skip) { bytes, total in
   precondition(total == data.count); samples.append(bytes)
  }!
  let actual = try Data(contentsOf: result); precondition(actual == data)
  precondition(samples.first == 0 && samples.last == Int64(data.count))
  precondition(samples.contains { $0 > 0 && $0 < data.count })
  let skipped = try FileEngine.transferWithProgress(file, to: dst, move: false, conflict: .skip) { _, _ in fatalError("skip callback") }
  precondition(skipped == nil)
  let nested = src.appendingPathComponent("nested"); try fm.createDirectory(at: nested, withIntermediateDirectories: true)
  try Data([1,2,3]).write(to: nested.appendingPathComponent(".hidden"))
  try fm.createSymbolicLink(at: nested.appendingPathComponent("loop"), withDestinationURL: nested)
  let folder = try FileEngine.transferWithProgress(nested, to: dst, move: false, conflict: .skip) { _, _ in }!
  let count = try FileEngine.folderBytes(folder); precondition(count == 3)
  let link = try fm.destinationOfSymbolicLink(atPath: folder.appendingPathComponent("loop").path); precondition(link == nested.path)
  let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/move-test-" + UUID().uuidString)
  try fm.createDirectory(at: local, withIntermediateDirectories: true)
  defer { try? fm.removeItem(at: local) }
  let moveSource = local.appendingPathComponent("move.bin")
  try data.write(to: moveSource)
  var sourceStat = stat(), destinationStat = stat()
  precondition(lstat(moveSource.path, &sourceStat) == 0 && stat(dst.path, &destinationStat) == 0)
  let isCrossVolume = sourceStat.st_dev != destinationStat.st_dev
  var movedBytes: Int64 = -1
  let moved = try FileEngine.transferWithProgress(moveSource, to: dst, move: true, conflict: .skip) { bytes, _ in movedBytes = bytes }!
  let movedData = try Data(contentsOf: moved)
  precondition(movedData == data && !fm.fileExists(atPath: moveSource.path))
  precondition(movedBytes == (isCrossVolume ? Int64(data.count) : 0))
  print(isCrossVolume ? "PASS: cross-volume move and source removal" : "PASS: same-volume rename and source removal; cross-volume move not exercised")
  print("PASS: incremental bytes, exact data, conflict skip, hidden files, symlink, directory copy")
 }
}
