import SwiftUI

/// 番茄钟视图。基于 Timeato 的 PomodoroTimerView 思路：
/// 圆形进度 + 大数字 + 按钮，但换了手账配色（PetMenuCardPalette）+ SF Symbols 图标按钮。
struct PomodoroView: View {
    @ObservedObject var store: PomodoroStore
    var linkedTodoTitle: String? = nil
    var onPickTodo: (() -> Void)? = nil
    var onClearTodo: (() -> Void)? = nil

    var body: some View {
        // TimelineView 每秒触发 body 重算，让倒计时实时跳
        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
            content(at: timeline.date)
        }
    }

    private func content(at date: Date) -> some View {
        VStack(spacing: 14) {
            phasePicker
            progressCircle(at: date)
            linkedTodoRow
            controls
            durationEditor
            footer
        }
        .padding(20)
        .frame(width: 320)
        .background(
            ZStack {
                Image(nsImage: petMenuBackground)
                    .resizable()
                    .interpolation(.high)
                phaseTint
            }
        )
    }

    /// 专注 = 蜜桃色调，休息 = 浅绿色调
    @ViewBuilder
    private var phaseTint: some View {
        switch store.currentPhase {
        case .focus:
            PetMenuCardPalette.softCoral.opacity(0.35)
        case .breakTime:
            Color.green.opacity(0.25)
        }
    }

    private var phasePicker: some View {
        Picker("", selection: phaseBinding) {
            Label("专注", systemImage: "target").tag(PomodoroStore.Phase.focus)
            Label("休息", systemImage: "leaf.fill").tag(PomodoroStore.Phase.breakTime)
        }
        .pickerStyle(.segmented)
    }

    private var phaseBinding: Binding<PomodoroStore.Phase> {
        Binding(
            get: { store.currentPhase },
            set: { newPhase in
                if !store.isRunning && !store.isPaused {
                    store.switchPhase(to: newPhase)
                }
            }
        )
    }

    private var linkedTodoRow: some View {
        Group {
            if let title = linkedTodoTitle, store.currentPhase == .focus {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 11))
                        .foregroundStyle(PetMenuCardPalette.coral)
                    Text(title)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(PetMenuCardPalette.cocoa.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    if let onClearTodo {
                        Button(action: onClearTodo) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(PetMenuCardPalette.cocoa.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(PetMenuCardPalette.softCoral.opacity(0.3))
                )
            }
        }
    }

    private var phaseBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: store.currentPhase == .focus ? "target" : "leaf.fill")
                .font(.system(size: 11, weight: .bold))
            Text(store.currentPhase == .focus ? "专注中" : "休息中")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(PetMenuCardPalette.cocoa)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(
                store.currentPhase == .focus
                    ? PetMenuCardPalette.softCoral.opacity(0.55)
                    : Color.green.opacity(0.3)
            )
        )
    }

    private func progressCircle(at date: Date) -> some View {
        ZStack {
            Circle()
                .stroke(PetMenuCardPalette.bisque, lineWidth: 12)
            Circle()
                .trim(from: 0, to: progressAt(at: date))
                .stroke(
                    store.currentPhase == .focus
                        ? PetMenuCardPalette.coral
                        : Color.green.opacity(0.7),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: store.progress)

            VStack(spacing: 4) {
                Text(timeText(at: date))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PetMenuCardPalette.cocoa)
            }
        }
        .frame(width: 200, height: 200)
    }

    private func progressAt(at date: Date) -> Double {
        switch store.state {
        case .running(_, let endDate, let total):
            let elapsed = total - endDate.timeIntervalSince(date)
            return min(1, max(0, elapsed / total))
        case .paused(_, let elapsed, let total):
            return min(1, max(0, elapsed / total))
        case .notRunning:
            return 0
        }
    }

    private func timeText(at date: Date) -> String {
        let remaining: Int
        switch store.state {
        case .running(_, let endDate, _):
            remaining = max(0, Int(endDate.timeIntervalSince(date).rounded(.up)))
        case .paused(_, let elapsed, let total):
            remaining = max(0, Int((total - elapsed).rounded(.up)))
        case .notRunning(let phase):
            remaining = (phase == .focus ? store.focusMinutes : store.breakMinutes) * 60
        }
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            if let onPickTodo, store.currentPhase == .focus && !store.isRunning {
                Button(action: onPickTodo) {
                    Image(systemName: "checklist")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PetMenuCardPalette.cocoa)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(PetMenuCardPalette.bisque))
                }
                .buttonStyle(.plain)
            }

            Button(action: toggle) {
                Image(systemName: primarySymbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(PetMenuCardPalette.coral))
                    .shadow(color: PetMenuCardPalette.coral.opacity(0.4), radius: 6, y: 2)
            }
            .buttonStyle(.plain)

            Button(action: store.stop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PetMenuCardPalette.cocoa)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(PetMenuCardPalette.bisque))
            }
            .buttonStyle(.plain)
            .disabled(!store.isRunning && !store.isPaused)
            .opacity((!store.isRunning && !store.isPaused) ? 0.4 : 1)
        }
    }

    private var primarySymbol: String {
        if store.isPaused { return "play.fill" }
        if store.isRunning { return "pause.fill" }
        return "play.fill"
    }

    private func toggle() {
        if store.isRunning {
            store.pause()
        } else {
            store.start()
        }
    }

    private var durationEditor: some View {
        VStack(spacing: 8) {
            durationRow(
                icon: "target",
                label: "专注",
                value: $store.focusMinutes,
                range: 1...120
            )
            durationRow(
                icon: "leaf.fill",
                label: "休息",
                value: $store.breakMinutes,
                range: 1...30
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PetMenuCardPalette.bisque.opacity(0.5))
        )
    }

    private func durationRow(icon: String, label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(PetMenuCardPalette.cocoa.opacity(0.7))
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(PetMenuCardPalette.cocoa)
            Spacer()
            Stepper(value: value, in: range, step: 1) {
                Text("\(value.wrappedValue) 分钟")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PetMenuCardPalette.cocoa)
            }
            .labelsHidden()
        }
    }

    private var footer: some View {
        Text("完成时 Cube 会自动庆祝 🎉")
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(PetMenuCardPalette.cocoa.opacity(0.55))
    }

    @MainActor
    private var petMenuBackground: NSImage {
        guard let url = PetResourceURLCache.url(named: "PetMenuBackground", withExtension: "jpg") else {
            return NSImage()
        }
        return PetImportedImageCache.image(for: url) ?? NSImage()
    }
}
