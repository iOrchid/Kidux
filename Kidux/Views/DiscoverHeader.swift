import SwiftUI

/// 发现页工具栏：与「已安装」同构 —— chrome 单行 segmented，accessory 固定高度筛选/搜索。
struct DiscoverHeader: View {
    @Environment(AppViewModel.self) private var viewModel
    @Binding var selectedCategory: ToolCategory

    var body: some View {
        VStack(spacing: 0) {
            modePickerBar
            filterSearchBar
            if viewModel.discoverMode == .builtin {
                categoryChipBar
            }
            if viewModel.discoverMode == .builtin, viewModel.discoverNLSummary != nil {
                nlSummaryBanner
            }
            if viewModel.discoverMode == .builtin, let speechStatus = viewModel.discoverSpeechStatus {
                Text(speechStatus)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.pageHorizontalPadding)
                    .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Chrome（对齐 InstalledAppsView.scopePickerBar）

    private var modePickerBar: some View {
        Picker(String(localized: "ui.DiscoverHeader.e146ad754c"), selection: Binding(
            get: { viewModel.discoverMode },
            set: { viewModel.setDiscoverMode($0) }
        )) {
            ForEach(DiscoverCatalogMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .frame(height: DiscoverChromeLayout.modePickerHeight)
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .animation(nil, value: viewModel.discoverMode)
    }

    // MARK: - Accessory：搜索 + 范围/来源 / Homebrew 窗口

    private var filterSearchBar: some View {
        HStack(spacing: 10) {
            searchField

            if viewModel.discoverMode == .builtin {
                filterMenu(
                    title: String(localized: "ui.DiscoverHeader.df011658"),
                    selectionTitle: viewModel.discoverScopeFilter.title
                ) {
                    ForEach(DiscoverScopeFilter.allCases) { scope in
                        Button {
                            viewModel.discoverScopeFilter = scope
                        } label: {
                            if viewModel.discoverScopeFilter == scope {
                                Label(scope.title, systemImage: "checkmark")
                            } else {
                                Text(scope.title)
                            }
                        }
                    }
                }

                filterMenu(
                    title: String(localized: "ui.DiscoverHeader.26ca20b1"),
                    selectionTitle: viewModel.discoverSourceFilter.shortTitle
                ) {
                    ForEach(DiscoverSourceFilter.allCases) { filter in
                        Button {
                            viewModel.discoverSourceFilter = filter
                        } label: {
                            if viewModel.discoverSourceFilter == filter {
                                Label(filter.title, systemImage: "checkmark")
                            } else {
                                Text(filter.title)
                            }
                        }
                    }
                }

                if viewModel.discoverScopeFilter == .role {
                    rolePicker
                }
            }

            if viewModel.discoverMode == .homebrew {
                trendingWindowPicker
            }

            Spacer(minLength: 0)
        }
        .frame(height: DiscoverChromeLayout.filterBarHeight)
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .clipped()
    }

    private var trendingWindowPicker: some View {
        HStack(spacing: 8) {
            Text(String(localized: "ui.DiscoverHeader.34422bb99b"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()

            Picker(String(localized: "ui.DiscoverHeader.34422bb99b"), selection: Binding(
                get: { viewModel.settings.trendingWindowDays },
                set: { newValue in
                    let oldValue = viewModel.settings.trendingWindowDays
                    guard oldValue != newValue else { return }
                    DiagnosticsEventLog.record("ui.trending_window_changed", fields: [
                        "from": "\(oldValue.rawValue)",
                        "to": "\(newValue.rawValue)"
                    ])
                    viewModel.settings.trendingWindowDays = newValue
                    viewModel.scheduleBrewTrendingLoad(
                        force: false,
                        debounceNanoseconds: 700_000_000
                    )
                }
            )) {
                ForEach(TrendingWindowDays.allCases) { window in
                    Text(window.shortTitle).tag(window)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 268)
            .labelsHidden()
        }
        .help(String(localized: "ui.DiscoverHeader.7c160bedbc"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: String(localized: "ui.DiscoverHeader.fmt.2e0b17dcd4"), locale: .current, "\(viewModel.settings.trendingWindowDays.displayName)"))
    }

    private func filterMenu<Content: View>(
        title: String,
        selectionTitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text("\(title)：\(selectionTitle)")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(title)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)

            TextField(searchPlaceholder, text: Binding(
                get: { viewModel.discoverSearchText },
                set: { viewModel.updateDiscoverSearch($0) }
            ))
            .textFieldStyle(.plain)
            .onSubmit {
                if CatalogNLFilterService.looksLikeNaturalLanguage(viewModel.discoverSearchText) {
                    Task { await viewModel.applyDiscoverNaturalLanguageFilter() }
                }
            }

            if viewModel.discoverMode == .builtin {
                Button {
                    viewModel.toggleDiscoverSpeechInput()
                } label: {
                    Image(systemName: viewModel.isDiscoverSpeechListening ? "mic.fill" : "mic")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(viewModel.isDiscoverSpeechListening ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "ui.DiscoverHeader.982c247069"))

                Button {
                    Task { await viewModel.applyDiscoverNaturalLanguageFilter() }
                } label: {
                    if viewModel.isApplyingDiscoverNL {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .help(String(localized: "ui.DiscoverHeader.c60031bbbe"))
                .disabled(viewModel.discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: DiscoverChromeLayout.searchMaxWidth)
    }

    private var rolePicker: some View {
        Menu {
            Button(String(localized: "ui.DiscoverHeader.92f6703a86")) {
                viewModel.discoverRoleFilter = nil
            }
            Divider()
            ForEach(viewModel.bundleManager.roles) { role in
                Button(role.name) {
                    viewModel.discoverRoleFilter = role.id
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.discoverRoleFilterTitle)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .foregroundStyle(Color.accentColor)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - 分类（App Store Categories → 横向芯片，不再嵌套第二侧栏）

    private var categoryChipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ToolCategory.allCases) { category in
                    let count = viewModel.catalogCount(for: category)
                    FilterChip(
                        title: category == .all ? String(format: String(localized: "ui.DiscoverHeader.fmt.469dd96a56"), locale: .current, "\(count)") : category.displayName,
                        isSelected: selectedCategory == category,
                        action: { selectedCategory = category }
                    )
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
        }
        .frame(height: DiscoverChromeLayout.categoryBarHeight)
        .padding(.bottom, 4)
    }

    private var nlSummaryBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.accentColor)
            Text(viewModel.discoverNLSummary ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(String(localized: "ui.DiscoverHeader.4403fca0c0")) {
                viewModel.clearDiscoverFilters()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.06))
    }

    private var searchPlaceholder: String {
        viewModel.discoverMode == .homebrew
            ? String(localized: "ui.DiscoverHeader.c3d0aaee8f")
            : String(localized: "ui.DiscoverHeader.c60f7787fd")
    }
}

enum DiscoverChromeLayout {
    static let modePickerHeight: CGFloat = 44
    static let filterBarHeight: CGFloat = 44
    static let categoryBarHeight: CGFloat = 36
    static let searchMaxWidth: CGFloat = 280
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
                }
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isSelected ? String(localized: "ui.DiscoverHeader.4d9546cc49") : String(localized: "ui.DiscoverHeader.eb8939dd54"))
    }
}
