import SwiftUI

enum AppPageStyle {
    case classic
    case ai
}

enum AppTheme {
    static let cornerRadius: CGFloat = 14
    static let cardCornerRadius: CGFloat = 16
    static let sidebarWidth: CGFloat = 220
    static let aiContentMaxWidth: CGFloat = 760

    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.10, green: 0.38, blue: 0.92),
            Color(red: 0.08, green: 0.58, blue: 0.78)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroBackground = LinearGradient(
        colors: [
            Color.accentColor.opacity(0.06),
            Color.clear
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardStroke = Color.primary.opacity(0.08)
    static let subtleFill = Color.primary.opacity(0.04)
    static let pageHorizontalPadding: CGFloat = 28
    static let contentPadding: CGFloat = 20
    static let contentMinHeight: CGFloat = 520
    static let toolbarReservedHeight: CGFloat = 44
    static let pageHeaderBlockHeight: CGFloat = 108
    static let pageHeaderVerticalPadding: CGFloat = 16
    static let pageHeaderTrailingWidth: CGFloat = 360
    static let discoverCardWidth: CGFloat = 280
    static let discoverIconSize: CGFloat = 64

    /// App Store 风格分区标题（低于 PageHeader 28pt，与环境页 `.headline` 同级偏上）
    struct DiscoverSectionHeader: View {
        let title: String
        var subtitle: String?
        var trailing: String? = nil

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3.weight(.bold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// App Store 风格「获取」胶囊按钮（短文案，避免卡片内截断成 brew instal…）
    struct AppStoreGetButton: View {
        let title: String
        var isDisabled: Bool = false
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .disabled(isDisabled)
        }
    }

    @ViewBuilder
    static func pageBackground(style: AppPageStyle) -> some View {
        switch style {
        case .classic:
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
        case .ai:
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.04),
                        Color.blue.opacity(0.02),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
    }
}

/// 统一页面容器
struct AppPageScaffold<Content: View>: View {
    var style: AppPageStyle = .classic
    var maxContentWidth: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AppTheme.pageBackground(style: style)
            if let maxContentWidth {
                content
                    .frame(maxWidth: maxContentWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(.background, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            )
    }
}

/// AI 对话输入区
struct AIInputBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    var placeholder: String
    var isGenerating: Bool
    var onSubmit: () -> Void
    var onStop: () -> Void
    var focus: FocusState<Bool>.Binding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmed.isEmpty && !isGenerating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .default))
                    .lineLimit(1...8)
                    .focused(focus)
                    .padding(.leading, 16)
                    .padding(.vertical, 14)
                    .frame(minHeight: 36, alignment: .leading)
                    .onSubmit(onSubmit)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.command) {
                            onSubmit()
                            return .handled
                        }
                        return .ignored
                    }

                actionButton
                    .padding(.trailing, 4)
                    .padding(.bottom, 6)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            HStack(spacing: 8) {
                if isGenerating {
                    Button(action: onStop) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(String(localized: "ui.AppTheme.095e938e"))
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Text(String(localized: "ui.AppTheme.7b48da4817"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(inputFill)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.04), radius: 1, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    focus.wrappedValue ? Color.accentColor.opacity(0.55) : inputStroke,
                    lineWidth: focus.wrappedValue ? 1.5 : 1
                )
        }
        .shadow(
            color: .black.opacity(focus.wrappedValue ? (colorScheme == .dark ? 0.35 : 0.12) : (colorScheme == .dark ? 0.2 : 0.06)),
            radius: focus.wrappedValue ? 16 : 10,
            y: focus.wrappedValue ? 8 : 4
        )
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: focus.wrappedValue)
    }

    private var inputFill: Color {
        colorScheme == .dark
            ? Color(white: 0.14)
            : Color(nsColor: .textBackgroundColor)
    }

    private var inputStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.primary.opacity(0.1)
    }

    @ViewBuilder
    private var actionButton: some View {
        Button(action: isGenerating ? onStop : onSubmit) {
            ZStack {
                Circle()
                    .fill(buttonFill)
                    .frame(width: 36, height: 36)
                Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                    .font(.system(size: isGenerating ? 12 : 15, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isGenerating && !canSend)
        .help(isGenerating ? String(localized: "ui.AppTheme.dda4c02718") : String(localized: "ui.AppTheme.89d2e87bac"))
    }

    private var buttonFill: AnyShapeStyle {
        if isGenerating {
            return AnyShapeStyle(Color.red.gradient)
        }
        if canSend {
            return AnyShapeStyle(AppTheme.accentGradient)
        }
        return AnyShapeStyle(Color.primary.opacity(0.14))
    }
}

struct StableContentArea<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: AppTheme.contentMinHeight, alignment: .top)
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String
    var actions: [EmptyStateAction] = []

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            if !actions.isEmpty {
                HStack(spacing: 10) {
                    ForEach(actions) { action in
                        Button(action.title, action: action.handler)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: AppTheme.contentMinHeight)
    }
}

struct EmptyStateAction: Identifiable {
    let id = UUID()
    let title: String
    let handler: () -> Void
}

/// 经典模式 detail 列统一容器：固定对齐与裁剪，避免各页自行处理窗口 chrome。
struct DetailContentHost<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipped()
    }
}

/// S22-27 — 安装 / 维护进度 Sheet 统一尺寸
enum BrewProgressLayout {
    static let sheetWidth: CGFloat = 720
    static let sheetHeight: CGFloat = 520
}

/// 经典侧栏页统一脚手架：PageHeader → Divider → 可选 chrome/accessory → 滚动区。
/// 顶栏使用不透明背景 + 更高 zIndex，避免 ScrollView / LazyVGrid 内容透出或画进顶栏。
struct ClassicPageScaffold<HeaderTrailing: View, Chrome: View, Accessory: View, Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var headerTrailing: () -> HeaderTrailing
    @ViewBuilder var chrome: () -> Chrome
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder headerTrailing: @escaping () -> HeaderTrailing = { EmptyView() },
        @ViewBuilder chrome: @escaping () -> Chrome = { EmptyView() },
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.headerTrailing = headerTrailing
        self.chrome = chrome
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: title, subtitle: subtitle, trailing: headerTrailing)
            Divider()
            chrome()
            accessory()
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// 经典页 ScrollView 内容区统一内边距与最大宽度。
struct ClassicPageScrollContent<Content: View>: View {
    var maxContentWidth: CGFloat? = 960
    var verticalPadding: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .padding(.horizontal, AppTheme.pageHorizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: maxContentWidth ?? .infinity)
                .frame(maxWidth: .infinity)
        }
    }
}

/// 经典页非滚动内容居中 loading / 空状态。
struct ClassicPageCenteredState<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// 滚动表面裁剪，防止 LazyVGrid 等内容画出边界、透到顶栏。
    func isolatesScrollSafeAreaFromWindowChrome() -> some View {
        compositingGroup().clipped()
    }
}

/// App Store 风格状态胶囊（发现页 / 清单行共用）
struct ToolStatusTag: View {
    let title: String
    var color: Color

    var body: some View {
        Text(title)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
            .fixedSize()
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    var verticalPadding: CGFloat = AppTheme.pageHeaderVerticalPadding
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String,
        verticalPadding: CGFloat = AppTheme.pageHeaderVerticalPadding,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.verticalPadding = verticalPadding
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)

            trailing()
                .frame(width: AppTheme.pageHeaderTrailingWidth, alignment: .trailing)
        }
        .frame(height: AppTheme.pageHeaderBlockHeight, alignment: .top)
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.top, verticalPadding + 4)
        .padding(.bottom, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// 各页统一的「重新扫描」按钮，固定宽度避免切换 Tab 时闪动
struct PageHeaderRescanButton: View {
    var title: String = String(localized: "common.rescan")
    var isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 96, height: 22)
            } else {
                Label(title, systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(.bordered)
        .disabled(isLoading)
        .frame(width: 112, alignment: .trailing)
    }
}

struct AppCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GlassCard { content }
    }
}

/// 交互风格切换（经典模式 ↔ 沉浸对话）；首页卡片 / 沉浸顶栏
struct InteractionModeToggleButton: View {
    @Environment(AppViewModel.self) private var viewModel
    var compact: Bool = false

    var body: some View {
        let mode = viewModel.activeInteractionMode
        let target: AppInteractionMode = mode == .classic ? .ai : .classic
        Button {
            viewModel.toggleInteractionMode(to: target)
        } label: {
            if compact {
                Label(target.enterLabel, systemImage: target.enterIcon)
                    .labelStyle(.titleAndIcon)
            } else {
                Label(target.enterLabel, systemImage: target.enterIcon)
            }
        }
        .help(mode == .classic ? String(localized: "ui.AppTheme.5ee4db4c79") : String(localized: "ui.AppTheme.4ce94865fc"))
    }
}
