import AppKit
import SwiftUI

/// 番茄钟窗口控制器。照 TodoReminderWindowController 模式做独立小窗。
@MainActor
final class PomodoroWindowController: NSObject, NSWindowDelegate {
    private let pomodoroStore: PomodoroStore
    private let todoStore: TodoStore
    private var window: NSWindow?
    private var linkedTodoID: UUID?
    @Published var linkedTodoTitle: String?

    init(pomodoroStore: PomodoroStore, todoStore: TodoStore) {
        self.pomodoroStore = pomodoroStore
        self.todoStore = todoStore
        super.init()
        pomodoroStore.onFocusComplete = { [weak self] in
            self?.onFocusCompleted()
        }
    }

    func show() {
        let rootView = PomodoroView(
            store: pomodoroStore,
            linkedTodoTitle: linkedTodoTitle,
            onPickTodo: { [weak self] in self?.pickTodo() },
            onClearTodo: { [weak self] in self?.clearTodo() }
        )
        let hostingController = NSHostingController(rootView: rootView)

        let window = self.window ?? NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "🍅 番茄钟"
        window.appearance = NSAppearance(named: .aqua)
        window.contentMinSize = NSSize(width: 340, height: 480)
        window.contentViewController = hostingController
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.setFrameAutosaveName("PomodoroWindow")
        if self.window == nil {
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// 从 todo 列表里弹一个 picker 选一个作为"专注目标"
    private func pickTodo() {
        let alert = NSAlert()
        alert.messageText = "选一个要专注的待办"
        let pending = todoStore.pendingTasks().prefix(8)
        if pending.isEmpty {
            alert.informativeText = "（暂无未完成待办）"
            alert.runModal()
            return
        }
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        for task in pending {
            popup.addItem(withTitle: task.title)
        }
        alert.accessoryView = popup
        alert.addButton(withTitle: "专注这个")
        alert.addButton(withTitle: "取消")
        let result = alert.runModal()
        if result == .alertFirstButtonReturn, let title = popup.titleOfSelectedItem {
            linkedTodoTitle = title
            linkedTodoID = pending.first(where: { $0.title == title })?.id
        } else {
            linkedTodoTitle = nil
            linkedTodoID = nil
        }
        show() // 刷新视图让 × 按钮出现
    }

    private func clearTodo() {
        linkedTodoTitle = nil
        linkedTodoID = nil
        show() // 刷新视图让 × 按钮消失
    }

    private func onFocusCompleted() {
        // 番茄完成 → 触发 Cube 庆祝
        // 通知通过 PetMotionState（在 App 启动时已绑好）
        // 这里只处理：标记 todo 完成 + 系统通知
        if let id = linkedTodoID {
            todoStore.toggleDone(id: id)
        }
        linkedTodoID = nil
        linkedTodoTitle = nil
        show()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window
        else { return }
        closingWindow.contentViewController = nil
    }
}