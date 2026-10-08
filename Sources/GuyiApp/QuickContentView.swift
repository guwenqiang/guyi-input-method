import SwiftUI
import GuyiCore

struct QuickContentView: View {
    @ObservedObject private var store = QuickContentStore.shared
    @State private var number = 0
    @State private var title = ""
    @State private var text = ""
    @State private var message = ""
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Localizer.text("常用内容")).font(.title2.bold())
            HStack {
                ForEach(0..<10, id: \.self) { index in
                    Button(String(index)) { number = index; load() }
                        .buttonStyle(.bordered)
                        .tint(number == index ? .accentColor : .secondary)
                        .help(store.entry(index)?.title ?? Localizer.text("尚未添加内容"))
                }
            }.disabled(busy)
            TextField(Localizer.text("标题"), text: $title).disabled(busy)
            TextEditor(text: $text).font(.body).frame(minHeight: 130).disabled(busy)
            if let entry = store.entry(number), entry.kind != .text {
                Text(Localizer.text("已保存附件：") + entry.title).font(.caption)
            }
            HStack {
                Button(Localizer.text("保存文字")) {
                    do { try store.saveText(number: number, title: title, text: text); message = Localizer.text("已保存") }
                    catch { message = error.localizedDescription }
                }
                Button(Localizer.text("选择图片或文件…")) { importFile() }
                Button(Localizer.text("复制")) {
                    do { try store.copy(number); message = Localizer.text("已复制，可在目标应用粘贴。") }
                    catch { message = error.localizedDescription }
                }.disabled(store.entry(number) == nil)
                Button(Localizer.text("删除"), role: .destructive) {
                    do { try store.remove(number); load() } catch { message = error.localizedDescription }
                }.disabled(store.entry(number) == nil)
            }.disabled(busy)
            Text(Localizer.text("Control+Option+数字复制 · 加 Shift 请求粘贴 · 单个文件最多 10 MiB"))
                .font(.caption).foregroundStyle(.secondary)
            Text(Localizer.text("仅在 GuYi 输入上下文中使用。附件粘贴取决于目标应用；不发送回车。内容仅保存在本机，未加密。"))
                .font(.caption).foregroundStyle(.secondary)
            Text(message.isEmpty ? store.error : message).font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 580, height: 430).onAppear { load() }
    }
    private func load() {
        title = store.entry(number)?.title ?? ""
        text = store.entry(number)?.text ?? ""
        message = ""
    }
    private func importFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            busy = true
            let slot = number
            let label = title.isEmpty ? url.lastPathComponent : title
            Task { @MainActor in
                defer { busy = false }
                do { try await store.saveFile(number: slot, title: label, source: url); load(); message = Localizer.text("已保存") }
                catch { message = error.localizedDescription }
            }
        }
    }
}
