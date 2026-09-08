import SwiftUI

struct WorkView: View {
    @ObservedObject var workStore: WorkSessionStore
    let currentLevel: Int

    var body: some View {
        VStack(spacing: 16) {
            header

            if let project = workStore.activeProject {
                activePanel(project: project)
            } else {
                projectGrid
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workStore.isWorking ? "正在办公" : "去办公")
                    .font(.title2.weight(.semibold))
                Text(workStore.isWorking
                     ? "收益加倍但别忘了喂我吃东西"
                     : "选择一个项目开始办公 · 当前等级 Lv.\(currentLevel)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "laptopcomputer")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
        }
    }

    private var projectGrid: some View {
        VStack(spacing: 10) {
            ForEach(WorkCatalog.projects) { project in
                projectRow(project)
            }
        }
    }

    private func projectRow(_ project: WorkProject) -> some View {
        let isUnlocked = currentLevel >= project.requiredLevel
        return HStack(spacing: 14) {
            Image(systemName: project.iconSystemSymbol)
                .font(.system(size: 22, weight: .regular))
                .frame(width: 36, height: 36)
                .foregroundStyle(isUnlocked ? Color.accentColor : Color.secondary.opacity(0.6))
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill((isUnlocked ? Color.accentColor : Color.secondary).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(project.displayName)
                        .font(.headline)
                    if !isUnlocked {
                        Text("Lv.\(project.requiredLevel) 解锁")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.secondary.opacity(0.18))
                            )
                            .foregroundStyle(.secondary)
                    }
                }
                Text(project.multiplierSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(isUnlocked ? "开始" : "未解锁") {
                if workStore.start(project, currentLevel: currentLevel) {
                    // session state is published; window stays open to show status
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!isUnlocked)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func activePanel(project: WorkProject) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: project.iconSystemSymbol)
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.displayName)
                        .font(.title3.weight(.semibold))
                    Text(project.multiplierSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.12))
            )

            Button(role: .destructive) {
                workStore.stop()
            } label: {
                Label("停止办公", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}