import SwiftUI

struct RoleCompareSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var leftRoleID: String = ""
    @State private var rightRoleID: String = ""

    private var roles: [RoleBundle] { viewModel.bundleManager.roles }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if roles.count < 2 {
                ContentUnavailableView(
                    String(localized: "ui.RoleCompareSheet.e146908a6e"),
                    systemImage: "person.2",
                    description: Text(String(localized: "ui.RoleCompareSheet.fea7917037"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                pickers
                Divider()
                compareContent
            }
        }
        .frame(width: 720, height: 560)
        .onAppear(perform: seedRoleSelection)
    }

    private func seedRoleSelection() {
        guard !roles.isEmpty else { return }
        if leftRoleID.isEmpty || !roles.contains(where: { $0.id == leftRoleID }) {
            leftRoleID = roles[0].id
        }
        if rightRoleID.isEmpty || !roles.contains(where: { $0.id == rightRoleID }) {
            rightRoleID = roles.count > 1 ? roles[1].id : roles[0].id
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "ui.RoleCompareSheet.323aa4c9c5"))
                    .font(.title2.bold())
                Text(String(localized: "ui.RoleCompareSheet.262f630ee9"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(String(localized: "ui.RoleCompareSheet.769d88e425")) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private var pickers: some View {
        HStack(spacing: 16) {
            rolePicker(String(localized: "ui.RoleCompareSheet.993b39c5e0"), selection: $leftRoleID)
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(.secondary)
            rolePicker(String(localized: "ui.RoleCompareSheet.e195043ec8"), selection: $rightRoleID)
        }
        .padding(16)
    }

    private func rolePicker(_ label: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(label, selection: selection) {
                ForEach(roles) { role in
                    Text(role.name).tag(role.id)
                }
            }
            .labelsHidden()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var compareContent: some View {
        if leftRoleID.isEmpty || rightRoleID.isEmpty {
            ContentUnavailableView(String(localized: "ui.RoleCompareSheet.93eed36fb3"), systemImage: "person.2")
        } else if leftRoleID == rightRoleID {
            ContentUnavailableView(String(localized: "ui.RoleCompareSheet.e83181681e"), systemImage: "arrow.triangle.2.circlepath")
        } else if let diff = RoleCompareDiff.compute(
            leftRoleID: leftRoleID,
            rightRoleID: rightRoleID,
            manager: viewModel.bundleManager
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    diffSection(
                        title: String(format: String(localized: "ui.RoleCompareSheet.fmt.2e2ce30a16"), locale: .current, "\(diff.leftRole.name)"),
                        systemImage: "a.circle.fill",
                        tools: diff.onlyLeft,
                        tint: .blue
                    )
                    diffSection(
                        title: String(format: String(localized: "ui.RoleCompareSheet.fmt.d72cf4f990"), locale: .current, "\(diff.rightRole.name)"),
                        systemImage: "b.circle.fill",
                        tools: diff.onlyRight,
                        tint: .orange
                    )
                    diffSection(
                        title: String(format: String(localized: "ui.RoleCompareSheet.fmt.c8e559dd74"), locale: .current, "\(diff.shared.count)"),
                        systemImage: "checkmark.circle.fill",
                        tools: diff.shared,
                        tint: .green
                    )
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView(String(localized: "ui.RoleCompareSheet.6e53c7f883"), systemImage: "exclamationmark.triangle")
        }
    }

    private func diffSection(title: String, systemImage: String, tools: [DevTool], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)

            if tools.isEmpty {
                Text(String(localized: "ui.RoleCompareSheet.d81bb206a8"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(tools) { tool in
                        HStack(spacing: 10) {
                            ToolIconView(tool: tool, size: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tool.name).font(.subheadline)
                                Text(tool.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            SourceBadge(source: tool.source)
                        }
                        .padding(.vertical, 8)
                        if tool.id != tools.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

private struct RoleCompareDiff {
    let leftRole: RoleBundle
    let rightRole: RoleBundle
    let onlyLeft: [DevTool]
    let onlyRight: [DevTool]
    let shared: [DevTool]

    static func compute(
        leftRoleID: String,
        rightRoleID: String,
        manager: BundleManager
    ) -> RoleCompareDiff? {
        guard let leftRole = manager.roles.first(where: { $0.id == leftRoleID }),
              let rightRole = manager.roles.first(where: { $0.id == rightRoleID }) else {
            return nil
        }

        let leftIDs = manager.toolIDs(forRoleID: leftRoleID)
        let rightIDs = manager.toolIDs(forRoleID: rightRoleID)

        let leftTools = manager.resolveTools(for: leftRole).map(\.tool)
        let rightTools = manager.resolveTools(for: rightRole).map(\.tool)
        var toolMap: [String: DevTool] = [:]
        for tool in leftTools + rightTools {
            toolMap[tool.id] = tool
        }

        func sortedTools(from ids: Set<String>) -> [DevTool] {
            ids.compactMap { toolMap[$0] }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        let sharedIDs = leftIDs.intersection(rightIDs)
        let onlyLeftIDs = leftIDs.subtracting(rightIDs)
        let onlyRightIDs = rightIDs.subtracting(leftIDs)

        return RoleCompareDiff(
            leftRole: leftRole,
            rightRole: rightRole,
            onlyLeft: sortedTools(from: onlyLeftIDs),
            onlyRight: sortedTools(from: onlyRightIDs),
            shared: sortedTools(from: sharedIDs)
        )
    }
}
