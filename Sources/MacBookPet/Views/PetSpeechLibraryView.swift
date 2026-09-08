import SwiftUI

/// Editor for per-pet speech line pools. Lives inside the customization window
/// behind the `.speechLibrary` sidebar target.
///
/// The view buffers new-line input in local `@State` per pet so each keystroke
/// doesn't write to disk. Lines are committed to the store only on Add/Delete.
struct PetSpeechLibraryView: View {
    @ObservedObject var speechStore: PetSpeechLineStore
    @ObservedObject var languageSettings: LanguageSettings

    /// Per-pet draft text for the "add a new line" field. Keyed by petID.
    @State private var drafts: [String: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                ForEach(PetCatalog.pets) { pet in
                    petCard(pet: pet)
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("台词库")
                .font(.title2)
                .fontWeight(.semibold)
            Text("点击宠物时，会从对应台词池里随机抽一条显示。留空或关闭开关就不显示。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func petCard(pet: PetDefinition) -> some View {
        let config = speechStore.configs[pet.id] ?? PetSpeechConfig()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: sidebarIcon(for: pet.visualKind))
                    .foregroundStyle(.secondary)
                Text(petDisplayName(pet))
                    .font(.headline)
                Spacer()
                Toggle("启用", isOn: enabledBinding(petID: pet.id, current: config))
                    .toggleStyle(.switch)
                    .labelsHidden()
                Text("启用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if config.lines.isEmpty {
                Text("还没有台词。在下面输入一条，按 + 添加。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(config.lines.enumerated()), id: \.offset) { index, line in
                        lineRow(petID: pet.id, index: index, text: line)
                    }
                }
            }

            addLineRow(petID: pet.id)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func lineRow(petID: String, index: Int, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "quote.bubble")
                .foregroundStyle(.tertiary)
                .font(.caption)
            Text(text)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer()
            Button {
                deleteLine(petID: petID, at: index)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除这条台词")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private func addLineRow(petID: String) -> some View {
        HStack(spacing: 8) {
            TextField("新台词…", text: draftBinding(petID: petID))
                .textFieldStyle(.roundedBorder)
                .onSubmit { addLine(petID: petID) }
            Button {
                addLine(petID: petID)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled((drafts[petID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("加入台词池")
        }
    }

    // MARK: - Mutations

    private func addLine(petID: String) {
        let raw = (drafts[petID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        var current = speechStore.configs[petID] ?? PetSpeechConfig()
        current.lines.append(raw)
        speechStore.setLines(current.lines, for: petID)
        drafts[petID] = ""
    }

    private func deleteLine(petID: String, at index: Int) {
        guard var current = speechStore.configs[petID] else { return }
        guard index >= 0, index < current.lines.count else { return }
        current.lines.remove(at: index)
        speechStore.setLines(current.lines, for: petID)
    }

    // MARK: - Bindings

    private func enabledBinding(petID: String, current: PetSpeechConfig) -> Binding<Bool> {
        Binding(
            get: { current.enabled },
            set: { speechStore.setEnabled($0, for: petID) }
        )
    }

    private func draftBinding(petID: String) -> Binding<String> {
        Binding(
            get: { drafts[petID] ?? "" },
            set: { drafts[petID] = $0 }
        )
    }

    // MARK: - Helpers

    private func petDisplayName(_ pet: PetDefinition) -> String {
        languageSettings.petName(pet.name)
    }

    private func sidebarIcon(for visualKind: PetVisualKind) -> String {
        switch visualKind {
        case .cube: "square.fill"
        case .frog: "leaf.fill"
        case .cat: "pawprint.fill"
        case .dog: "dog.fill"
        case .cookie: "circle.fill"
        }
    }
}
