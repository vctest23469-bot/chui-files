import Foundation
@main struct FolderBytesTests {
 static func main() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let empty = try FileEngine.folderBytes(root); assert(empty == 0)
  try Data(repeating: 1, count: 123).write(to: root.appendingPathComponent(".hidden"))
  let nested = root.appendingPathComponent("中文")
  try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
  try Data(repeating: 2, count: 456).write(to: nested.appendingPathComponent("test"))
  try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
  let bytes = try FileEngine.folderBytes(root)
  guard bytes == 579 else { fatalError("wrong bytes: \(bytes)") }
  do { _ = try FileEngine.folderBytes(root, cancelled: { true }); fatalError("cancel ignored") } catch {}
  print("PASS: empty, nested, hidden, symlink loop, cancellation")
 }
}
