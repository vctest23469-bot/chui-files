import Foundation
@main struct SortingTests {
 static func main() {
  func item(_ name: String, _ directory: Bool, _ time: Double) -> Entry {
   Entry(url: URL(fileURLWithPath: "/test/" + name), name: name, directory: directory, symlink: false, size: 10, modified: Date(timeIntervalSince1970: time), tags: [])
  }
  let oldFolder = item("folder", true, 1), newFile = item("file", false, 3), middleFolder = item("middle", true, 2)
  let all = [oldFolder, newFile, middleFolder]
  func sorted(_ ascending: Bool, _ first: Bool = false) -> [String] {
   all.sorted { EntryOrder.precedes($0, $1, key: "修改时间", ascending: ascending, foldersFirst: first) }.map(\.name)
  }
  precondition(sorted(false) == ["file", "middle", "folder"])
  precondition(sorted(true) == ["folder", "middle", "file"])
  precondition(sorted(false, true) == ["middle", "folder", "file"])
  precondition(!EntryOrder.precedes(newFile, newFile, key: "名称", ascending: false))
  precondition(EntryOrder.precedes(newFile, oldFolder, key: "大小", ascending: false, sizes: [oldFolder.id: 5]))
  precondition(EntryOrder.precedes(newFile, oldFolder, key: "大小", ascending: true))
  print("PASS: mixed ascending/descending, folders first, equal items, calculated and unknown sizes")
 }
}
