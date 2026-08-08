import SwiftUI

struct RoleSelectionView: View {
    @Environment(AppViewModel.self) private var viewModel
    @FocusState private var focusedRoleID: String?
    @State private var showRoleCompare = false

    private var settings: AppSettings { viewModel.settings }

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private var groupedRoles: [(RoleGroup, [RoleBundle])] {
        RoleGroup.allCases.compactMap { group in
            let roles = viewModel.bundleManager.roles.filter { $0.group == group }
            return roles.isEmpty ? nil : (group, roles)
        }
    }

    private var allRolesFlat: [RoleBundle] {
        groupedRoles.flatMap(\.1)
    }

    var body: some View {
        ClassicPageScaffold(
            title: String(localized: "roles.select_title"),
            subtitle: settings.allowMultipleRoles
                ? String(format: String(localized: "ui.RoleSelectionView.fmt.5957506eeb"), locale: .current, "\(viewModel.selectedRoles.count)")
                : String(localized: "ui.RoleSelectionView.fab3c6defb"),
            headerTrailing: {
                HStack(spacing: 8) {
                    Button {
                        showRoleCompare = true
                    } label: {
                        Label(String(localized: "ui.RoleSelectionView.14ec46eef2"), systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.bordered)

                    Text(String(format: String(localized: "ui.RoleSelectionView.fmt.312ab66d06"), locale: .current, "\(viewModel.bundleManager.roles.count)"))
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.subtleFill, in: Capsule())
                }
            },
            content: { roleSelectionBody }
        )
        .sheet(isPresented: $showRoleCompare) {
            RoleCompareSheet()
                .environment(viewModel)
        }
    }

    @ViewBuilder
    private var roleSelectionBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(groupedRoles, id: \.0.id) { group, roles in
                        VStack(alignment: .leading, spacing: 14) {
                            Label(group.title, systemImage: group.icon)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 28)

                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(roles) { role in
                                    let previewTools = Array(
                                        viewModel.bundleManager.resolveTools(for: role).prefix(10).map(\.tool)
                                    )
                                    RoleCard(
                                        role: role,
                                        isSelected: viewModel.selectedRoles.contains(role.id),
                                        isFocused: focusedRoleID == role.id,
                                        selectionMode: settings.allowMultipleRoles ? .multiple : .single,
                                        toolCount: viewModel.bundleManager.resolveTools(for: role).count,
                                        previewTools: previewTools,
                                        onTap: {
                                            viewModel.toggleRole(role.id)
                                        },
                                        onDoubleTap: {
                                            if !viewModel.selectedRoles.contains(role.id) {
                                                viewModel.toggleRole(role.id)
                                            }
                                            viewModel.proceedToBundleDetail()
                                        }
                                    )
                                    .focusable()
                                    .focused($focusedRoleID, equals: role.id)
                                }
                            }
                            .padding(.horizontal, 28)
                        }
                    }
                }
                .padding(.vertical, 24)
            }
            .focusable()
            // 不在 onAppear 自动聚焦首卡，避免切到岗位页时「选中框」闪到学生/入门。
            // 仅当用户用方向键导航时，moveFocus 再建立焦点。
            .onKeyPress(.upArrow) {
                moveFocus(by: -columnCount)
                return .handled
            }
            .onKeyPress(.downArrow) {
                moveFocus(by: columnCount)
                return .handled
            }
            .onKeyPress(.leftArrow) {
                moveFocus(by: -1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                moveFocus(by: 1)
                return .handled
            }
            .onKeyPress(.return) {
                activateFocusedRole(openDetail: true)
                return .handled
            }
            .onKeyPress(.space) {
                activateFocusedRole(openDetail: false)
                return .handled
            }

            Divider()
            footer
        }
    }

    private var columnCount: Int { columns.count }

    private func moveFocus(by offset: Int) {
        guard !allRolesFlat.isEmpty else { return }
        let currentIndex = focusedRoleID.flatMap { id in
            allRolesFlat.firstIndex(where: { $0.id == id })
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), allRolesFlat.count - 1)
        focusedRoleID = allRolesFlat[nextIndex].id
    }

    private func activateFocusedRole(openDetail: Bool) {
        guard let id = focusedRoleID else { return }
        if !viewModel.selectedRoles.contains(id) {
            viewModel.toggleRole(id)
        }
        if openDetail {
            viewModel.proceedToBundleDetail()
        }
    }

    private var footer: some View {
        HStack {
            Button(String(localized: "ui.RoleSelectionView.5a1367058c")) {
                viewModel.selectedTab = .home
                viewModel.currentScreen = .welcome
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Text(viewModel.selectedRoleName ?? String(localized: "ui.RoleSelectionView.63447c9c3c"))
                .foregroundStyle(.secondary)

            Button(String(localized: "ui.RoleSelectionView.388167a9d0")) {
                viewModel.proceedToBundleDetail()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedRoles.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }
}

struct RoleCard: View {
    enum SelectionMode {
        case single
        case multiple
    }

    let role: RoleBundle
    let isSelected: Bool
    var isFocused: Bool = false
    let selectionMode: SelectionMode
    let toolCount: Int
    var previewTools: [DevTool] = []
    let onTap: () -> Void
    var onDoubleTap: (() -> Void)?

    @State private var previewHovered = false
    @State private var previewPinned = false

    private var showPreview: Bool { previewHovered || previewPinned }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: role.icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(
                        isSelected ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(Color.accentColor.opacity(0.1)),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                Spacer()
                selectionIndicator
            }

            Text(role.name)
                .font(.headline)
                .foregroundStyle(isSelected ? .white : .primary)

            Text(role.description)
                .font(.caption)
                .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: 32, alignment: .topLeading)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text(String(format: String(localized: "ui.RoleSelectionView.fmt.746986869c"), locale: .current, "\(toolCount)"))
                    .font(.caption.bold())
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : Color.accentColor)
                if !previewTools.isEmpty {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                        .help(String(localized: "ui.RoleSelectionView.2925656601"))
                        .contentShape(Rectangle())
                        .padding(4)
                        .onTapGesture {
                            previewPinned.toggle()
                        }
                        .onHover { previewHovered = $0 }
                        .popover(isPresented: previewPresented, arrowEdge: .bottom) {
                            rolePreviewPopover
                        }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
        .background { cardBackground }
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                    .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
        .focusEffectDisabled()
        .animation(nil, value: isSelected)
        .animation(nil, value: isFocused)
        .onTapGesture(perform: onTap)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onDoubleTap?()
            }
        )
    }

    private var previewPresented: Binding<Bool> {
        Binding(
            get: { showPreview },
            set: { isPresented in
                if !isPresented {
                    previewPinned = false
                    previewHovered = false
                }
            }
        )
    }

    private var rolePreviewPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(format: String(localized: "ui.RoleSelectionView.fmt.c9db56cddc"), locale: .current, "\(previewTools.count)"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(previewTools) { tool in
                HStack(spacing: 8) {
                    ToolIconView(tool: tool, size: 20)
                    Text(tool.name)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            if toolCount > previewTools.count {
                Text(String(format: String(localized: "ui.RoleSelectionView.fmt.3db5c2cf95"), locale: .current, "\(toolCount - previewTools.count)"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(width: 240, alignment: .leading)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .fill(AppTheme.accentGradient)
        } else {
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .fill(.background)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                        .stroke(AppTheme.cardStroke)
                )
        }
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        switch selectionMode {
        case .single:
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? .white : .secondary)
                .font(.title3)
        case .multiple:
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(isSelected ? .white : .secondary)
                .font(.title3)
        }
    }
}

/// 岗位安装流程：选岗 → 清单 → 安装 → 完成
struct RolesFlowView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        Group {
            switch viewModel.currentScreen {
            case .welcome, .roleSelection:
                RoleSelectionView()
            case .bundleDetail:
                BundleDetailView()
            case .installation:
                InstallationProgressView()
            case .complete:
                CompletionView()
            }
        }
        .animation(nil, value: viewModel.currentScreen)
    }
}

#Preview {
    RoleSelectionView()
        .environment(AppViewModel())
        .frame(width: 1000, height: 700)
}
