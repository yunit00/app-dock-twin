import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: DockModel
    var body: some View {
        Form {
            Section("Расположение") {
                Picker("Край экрана", selection: $model.preferences.edge) {
                    ForEach(DockEdge.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Монитор", selection: $model.preferences.screenID) {
                    Text("Основной").tag("main")
                    ForEach(NSScreen.screens, id: \.dockID) { Text($0.localizedName).tag($0.dockID) }
                }
                Toggle("Автоматически скрывать", isOn: $model.preferences.autoHide)
            }
            Section("Внешний вид") {
                Slider(value: $model.preferences.iconSize, in: 28...80, step: 1) {
                    Text("Размер иконок · \(Int(model.preferences.iconSize))")
                }
                Slider(value: $model.preferences.magnification, in: 1...2, step: 0.05) {
                    Text("Увеличение · \(model.preferences.magnification, specifier: "%.2f")×")
                }
                Toggle("Показывать запущенные приложения", isOn: $model.preferences.showRunning)
            }
            Section("Содержимое") {
                Button("Добавить приложения, файлы или папки…") { model.chooseItems() }
                Text("Перетащите объект из Finder на панель. Чтобы изменить порядок, перетащите иконку на другую. Удаление доступно в контекстном меню.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 470, height: 430)
    }
}

struct FolderView: View {
    let url: URL
    let open: (URL) -> Void
    @State private var children: [URL] = []
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(FileManager.default.displayName(atPath: url.path)).font(.headline)
                Spacer()
                Button("В Finder") { open(url) }
            }
            Divider()
            if let error {
                Text(error).foregroundStyle(.secondary)
            } else if children.isEmpty {
                Text("Папка пуста").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84))], spacing: 16) {
                        ForEach(children, id: \.self) { child in
                            Button { open(child) } label: {
                                VStack(spacing: 6) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: child.path))
                                        .resizable().scaledToFit().frame(width: 48, height: 48)
                                    Text(FileManager.default.displayName(atPath: child.path))
                                        .font(.system(size: 11)).lineLimit(2).frame(height: 28)
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(.plain)
                            .help(child.lastPathComponent)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 380, height: 360)
        .task {
            do {
                children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            } catch { self.error = error.localizedDescription }
        }
    }
}

extension NSScreen {
    var dockID: String { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? localizedName }
}
