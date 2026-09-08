import AppKit
import SwiftUI

@MainActor
final class TodoReminderWindowController: NSObject, NSWindowDelegate {
    private let todoStore: TodoStore
    private var window: NSWindow?

    init(todoStore: TodoStore) {
        self.todoStore = todoStore
        super.init()
    }

    func show() {
        let rootView = TodoListView(todoStore: todoStore)
        let hostingController = NSHostingController(rootView: rootView)

        let window = self.window ?? NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "待办提醒"
        window.appearance = NSAppearance(named: .aqua)
        window.contentMinSize = NSSize(width: 460, height: 480)
        window.contentViewController = hostingController
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("TodoReminderWindow")
        if self.window == nil {
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window
        else { return }
        closingWindow.contentViewController = nil
    }
}