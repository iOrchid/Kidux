import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isQueryFocused: Bool

    private var filteredCommands: [CommandPaletteCommand] {
        CommandPaletteRegistry.filtered(query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "ui.CommandPaletteView.3b3b4717e6"), text: $query)
                    .textFieldStyle(.plain)
                    .focused($isQueryFocused)
                    .onChange(of: query) { _, _ in
                        selectedIndex = 0
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                        selectedIndex = 0
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            if filteredCommands.isEmpty {
                ContentUnavailableView(
                    String(localized: "ui.CommandPaletteView.e22e07c34b"),
                    systemImage: "magnifyingglass",
                    description: Text(String(localized: "ui.CommandPaletteView.8e28237855"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                    Button {
                        execute(command)
                        dismiss()
                    } label: {
                        commandRow(command)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                index == selectedIndex
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 520, height: 420)
        .focusable()
        .onKeyPress(.upArrow) {
            moveSelection(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(1)
            return .handled
        }
        .onKeyPress(.return) {
            activateSelection()
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onAppear {
            isQueryFocused = true
            selectedIndex = 0
        }
    }

    private func moveSelection(_ delta: Int) {
        let count = filteredCommands.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func activateSelection() {
        guard filteredCommands.indices.contains(selectedIndex) else { return }
        execute(filteredCommands[selectedIndex])
        dismiss()
    }

    private func commandRow(_ command: CommandPaletteCommand) -> some View {
        HStack(spacing: 12) {
            Image(systemName: command.systemImage)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.body.weight(.medium))
                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func execute(_ command: CommandPaletteCommand) {
        switch command.kind {
        case .navigate(let tab):
            viewModel.navigateTo(tab)
        case .scanUpdates:
            Task { await viewModel.checkForUpdates(force: true) }
        case .exportChecklist:
            viewModel.exportMigrationChecklist()
        case .openMigrationWizard:
            viewModel.openMigrationWizard()
        case .openDiscoverSearch:
            viewModel.openDiscoverSearch(query: query)
        }
    }
}

#Preview {
    CommandPaletteView()
        .environment(AppViewModel())
}
