import AppKit
import SwiftUI

@MainActor
final class WorkWindowController: NSObject, NSWindowDelegate {
    private let workStore: WorkSessionStore
    private let levelProvider: () -> Int
    private var window: NSWindow?

    init(workStore: WorkSessionStore, levelProvider: @escaping () -> Int) {
        self.workStore = workStore
        self.levelProvider = levelProvider
        super.init()
    }

    func show() {
        let rootView = WorkView(workStore: workStore, currentLevel: levelProvider())
        let hostingController = NSHostingController(rootView: rootView)

        let window = self.window ?? NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "去办公"
        window.appearance = NSAppearance(named: .aqua)
        window.contentMinSize = NSSize(width: 460, height: 420)
        window.contentViewController = hostingController
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("WorkSessionWindow")
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