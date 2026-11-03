import SwiftUI

@main
struct MacFreeApp: App {
    private var model: AppModel { .shared }

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 940, minHeight: 600)
        }
        .defaultSize(width: 1120, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Scan Again") { model.rescan() }
                    .keyboardShortcut("r")
                    .disabled(model.scanPath == nil)
                Button("Choose Another Location…") { model.reset() }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .pasteboard) {
                Button("Delete…") { model.requestDeleteFromKeyboard() }
                    .keyboardShortcut(.delete, modifiers: .command)
            }
        }
    }
}
