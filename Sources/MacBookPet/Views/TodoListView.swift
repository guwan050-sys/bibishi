import SwiftUI

struct TodoListView: View {
    @ObservedObject var todoStore: TodoStore
    @State private var newTitle: String = ""
    @State private var newDueDate: Date = Date().addingTimeInterval(60 * 60)
    @State private var newLeadTime: TodoTask.LeadTime = .none
    @State private var newRepeatRule: TodoTask.RepeatRule = .none
    @State private var includeReminder: Bool = true
    @State private var editingTaskID: UUID?
    @State private var editingTitle: String = ""
    @State private var viewFilter: TodoStore.ViewFilter = .today

    var body: some View {
        VStack(spacing: 12) {
            header
            viewFilterPicker
            quickAddCard
            listCard
            footer
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 560)
        .background(
            Image(nsImage: petMenuBackground)
                .resizable()
                .interpolation(.high)
        )
    }

    private var header: some View {
        HStack {
            Text("📝 待办提醒")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PetMenuCardPalette.cocoa)
            Spacer()
            Text("\(todoStore.pendingTasks().count) 项进行中")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PetMenuCardPalette.cocoa.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(PetMenuCardPalette.softCoral.opacity(0.5), in: Capsule())
        }
        .padding(.horizontal, 4)
    }

    private var viewFilterPicker: some View {
        Picker("", selection: $viewFilter) {
            ForEach(TodoStore.ViewFilter.allCases) { filter in
                Text(filter.label).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var quickAddCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("想做的事情…", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(PetMenuCardPalette.cocoa)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(PetMenuCardPalette.bisque.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onSubmit(commitQuickAdd)
                Button(action: commitQuickAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(PetMenuCardPalette.coral)
                }
                .buttonStyle(.plain)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(newTitle.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }

            HStack(spacing: 10) {
                Toggle(isOn: $includeReminder) {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 10))
                        Text("提醒我")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                }
                .toggleStyle(.checkbox)

                if includeReminder {
                    DatePicker(
                        "",
                        selection: $newDueDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }
                Spacer()
            }

            if includeReminder {
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10))
                            .foregroundStyle(PetMenuCardPalette.cocoa.opacity(0.6))
                        Text("提前")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(PetMenuCardPalette.cocoa.opacity(0.6))
                        Picker("", selection: $newLeadTime) {
                            ForEach(TodoTask.LeadTime.allCases, id: \.self) { lt in
                                Text(lt == .none ? "不提前" : "\(lt.rawValue) 分钟").tag(lt)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 110)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                            .foregroundStyle(PetMenuCardPalette.cocoa.opacity(0.6))
                        Text("循环")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(PetMenuCardPalette.cocoa.opacity(0.6))
                        Picker("", selection: $newRepeatRule) {
                            ForEach(TodoTask.RepeatRule.allCases, id: \.self) { r in
                                Text(r.label).tag(r)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 110)
                    }
                }
            }
        }
        .padding(14)
        .petMenuCardSurface(isHovering: false)
    }

    private var listCard: some View {
        let visibleTasks = todoStore.tasks(for: viewFilter)
        return Group {
            if visibleTasks.isEmpty {
                VStack(spacing: 10) {
                    Text(emptyEmoji)
                        .font(.system(size: 42))
                    Text(emptyTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(PetMenuCardPalette.cocoa)
                    Text(emptySubtitle)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(PetMenuCardPalette.cocoa.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .petMenuCardSurface(isHovering: false)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visibleTasks) { task in
                            row(for: task)
                        }
                    }
                    .padding(12)
                }
                .petMenuCardSurface(isHovering: false)
            }
        }
    }

    private var emptyEmoji: String {
        switch viewFilter {
        case .today: return "☀️"
        case .all: return "🎉"
        case .done: return "📭"
        }
    }

    private var emptyTitle: String {
        switch viewFilter {
        case .today: return "今天没有待办"
        case .all: return "没有进行中的待办"
        case .done: return "还没有完成过任何待办"
        }
    }

    private var emptySubtitle: String {
        switch viewFilter {
        case .today: return "在上面的输入框里添加一件想做的事"
        case .all: return "切换到「今天」看今天到期的，或者加一件新事"
        case .done: return "完成一条待办后会出现在这里"
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            // 提示音开关：放 footer 左下，独立一行不抢视线
            Toggle(isOn: $todoStore.soundEnabled) {
                HStack(spacing: 4) {
                    Image(systemName: todoStore.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 10))
                    Text("提示音")
                        .font(.system(size: 11, design: .rounded))
                }
            }
            .toggleStyle(.checkbox)
            .foregroundStyle(PetMenuCardPalette.cocoa.opacity(0.65))

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text("到时间会发送系统通知 + 桌宠气泡")
                    .font(.system(size: 11, design: .rounded))
            }
            .foregroundStyle(PetMenuCardPalette.cocoa.opacity(0.55))
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func row(for task: TodoTask) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    todoStore.toggleDone(id: task.id)
                }
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(task.isDone ? PetMenuCardPalette.coral : PetMenuCardPalette.cocoa.opacity(0.4))
                    .symbolEffect(.bounce, value: task.isDone)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                if editingTaskID == task.id {
                    HStack {
                        TextField("标题", text: $editingTitle)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { commitEdit(of: task) }
                        Button("保存") { commitEdit(of: task) }
                            .buttonStyle(PetMenuRaisedButtonStyle(isCompact: true))
                        Button("取消") { editingTaskID = nil }
                            .buttonStyle(.borderless)
                    }
                } else {
                    Text(task.title)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .strikethrough(task.isDone, color: PetMenuCardPalette.cocoa.opacity(0.5))
                        .foregroundStyle(task.isDone ? PetMenuCardPalette.cocoa.opacity(0.5) : PetMenuCardPalette.cocoa)
                }

                if let due = task.dueDate {
                    HStack(spacing: 5) {
                        Image(systemName: task.isOverdue ? "exclamationmark.bell.fill" : "bell.fill")
                            .font(.system(size: 10))
                        Text(Self.dueText(for: due, leadMinutes: task.leadTime.rawValue, overdue: task.isOverdue))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                        if task.repeatRule != .none {
                            Image(systemName: repeatSymbol(for: task.repeatRule))
                                .font(.system(size: 9))
                                .foregroundStyle(PetMenuCardPalette.cocoa.opacity(0.5))
                        }
                    }
                    .foregroundStyle(task.isOverdue ? PetMenuCardPalette.coral : PetMenuCardPalette.cocoa.opacity(0.65))
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    editingTaskID = task.id
                    editingTitle = task.title
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(PetMenuCardPalette.cocoa.opacity(0.6))
                }
                .buttonStyle(.borderless)
                .disabled(task.isDone)

                Button {
                    todoStore.remove(id: task.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(PetMenuCardPalette.coral.opacity(0.7))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            PetMenuCardPalette.bisque.opacity(task.isDone ? 0.3 : 0.6),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .opacity(task.isDone ? 0.7 : 1)
    }

    private func repeatSymbol(for rule: TodoTask.RepeatRule) -> String {
        switch rule {
        case .none: return ""
        case .daily: return "arrow.triangle.2.circlepath"
        case .weekly: return "calendar.badge.clock"
        case .weekdays: return "briefcase.fill"
        }
    }

    private func commitQuickAdd() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = TodoTask(
            title: trimmed,
            dueDate: includeReminder ? newDueDate : nil,
            leadTime: includeReminder ? newLeadTime : .none,
            repeatRule: includeReminder ? newRepeatRule : .none
        )
        todoStore.add(task)
        newTitle = ""
        newDueDate = Date().addingTimeInterval(60 * 60)
        newLeadTime = .none
        newRepeatRule = .none
    }

    private func commitEdit(of task: TodoTask) {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = task
        updated.title = trimmed
        todoStore.update(updated)
        editingTaskID = nil
    }

    private static func dueText(for date: Date, leadMinutes: Int, overdue: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        let lead = leadMinutes > 0 ? " 提前 \(leadMinutes)min" : ""
        let prefix = overdue ? "已过期" : "提醒"
        return "\(prefix) \(formatter.string(from: date))\(lead)"
    }

    @MainActor
    private var petMenuBackground: NSImage {
        guard let url = PetResourceURLCache.url(named: "PetMenuBackground", withExtension: "jpg") else {
            return NSImage()
        }
        return PetImportedImageCache.image(for: url) ?? NSImage()
    }
}
