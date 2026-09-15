import SwiftUI

struct DeviceList: View {
    @ObservedObject var model: Workspace
    @ObservedObject var pane: Pane
    var body: some View {
        ForEach(model.volumes) { volume in
            Button { model.navigate(volume.url) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Image(systemName: volume.symbol).foregroundStyle(Theme.navigationIcon).frame(width: 18)
                        Text(volume.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 3)
                        Text("总 \(volume.totalText)").font(.system(size: 11)).monospacedDigit().foregroundStyle(Color(nsColor: Theme.secondaryText))
                    }
                    HStack {
                        Text("可用 \(volume.availableText)").monospacedDigit()
                        Spacer()
                        if let fraction = volume.availableFraction { Text("\(Int(((1 - fraction) * 100).rounded()))% 已用").monospacedDigit().foregroundStyle(Color(nsColor: Theme.secondaryText)) }
                    }.font(.system(size: 11)).padding(.leading, 25)
                    if let fraction = volume.availableFraction {
                        GeometryReader { geometry in
                            Capsule().fill(Color.primary.opacity(0.09))
                            Capsule().fill(fraction < 0.1 ? Color.orange : Theme.navigationIcon)
                                .frame(width: geometry.size.width * (1 - fraction))
                        }.frame(height: 3).padding(.leading, 25).accessibilityHidden(true)
                    }
                }.padding(.horizontal, 8).padding(.vertical, 9)
                    .background(pane.volume?.id == volume.id ? Color.primary.opacity(0.10) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .help("\(volume.name)\n挂载点：\(volume.url.path)\n总容量：\(volume.totalText)\n可用：\(volume.availableText)\n实色表示已用比例，空白表示剩余比例。每 15 秒刷新。APFS 可用空间可能由多个卷共享，不等于目录占用。")
                .accessibilityLabel("\(volume.name)，总容量 \(volume.totalText)，可用容量 \(volume.availableText)")
        }
    }
}

struct FolderHeading: View {
    @ObservedObject var pane: Pane
    @ObservedObject var model: Workspace
    let isLeft: Bool
    var crumbs: [BreadcrumbItem] { BreadcrumbItem.path(to: pane.folder, volume: pane.volume) }
    func crumb(_ item: BreadcrumbItem) -> some View {
        Button { model.activeLeft = isLeft; model.navigate(item.url, pane: pane) } label: {
            Text(item.title).lineLimit(1)
        }.buttonStyle(.plain).foregroundStyle(.primary).help("前往 \(item.url.path)")
            .accessibilityLabel("前往 \(item.title)")
    }
    var separator: some View { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color(nsColor: Theme.secondaryText)) }
    var summary: String {
        let count: String
        if pane.error != nil { count = "目录读取失败" }
        else if pane.loading && pane.entries.isEmpty { count = "正在读取…" }
        else { count = "\(pane.entries.count) 个项目" + (pane.filter.isEmpty ? "" : " · 匹配 \(pane.visible.count) 项") }
        return count + "，" + (pane.volume?.availableText ?? "容量暂不可读") + (pane.volume == nil ? "" : " 可用")
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: pane.volume?.symbol ?? "externaldrive")
                .font(.system(size: 30, weight: .regular)).foregroundStyle(Color.primary.opacity(0.75)).frame(width: 34)
                .accessibilityLabel(pane.volume?.name ?? "所在磁盘")
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { separator }
                            crumb(item).fixedSize()
                        }
                    }
                    HStack(spacing: 5) {
                        if let first = crumbs.first { crumb(first).fixedSize() }
                        if crumbs.count > 2 {
                            separator
                            Menu("…") { ForEach(crumbs.dropFirst().dropLast()) { item in
                                Button(item.title) { model.activeLeft = isLeft; model.navigate(item.url, pane: pane) }
                            } }.menuStyle(.borderlessButton).frame(width: 24).help("中间目录")
                        }
                        if crumbs.count > 1, let last = crumbs.last { separator; crumb(last).truncationMode(.middle) }
                    }
                }.font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
                Text(summary).font(.system(size: 11)).foregroundStyle(Color(nsColor: Theme.secondaryText)).lineLimit(1).monospacedDigit()
            }
            Spacer(minLength: 0)
            Button { model.activeLeft = isLeft; model.goTo() } label: {
                Image(systemName: "square.and.pencil").font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.secondaryText))
            }.buttonStyle(.plain).help("输入路径 ⇧⌘G").accessibilityLabel("输入路径")
            if pane.loading { ProgressView().controlSize(.mini) }
        }.padding(.horizontal, 12).frame(height: 57).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: Theme.toolbar))
    }
}
