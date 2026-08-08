import SwiftUI

private enum DependencyDisplayMode: String, CaseIterable, Identifiable {
    case list
    case graph

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return String(localized: "ui.DependencyTreeView.3712972d84")
        case .graph: return String(localized: "ui.DependencyTreeView.9be72ba165")
        }
    }
}

struct DependencyTreeView: View {
    let formula: String
    let root: DependencyTreeNode?
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("brew deps --tree --installed")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(String(localized: "ui.DependencyTreeView.813ce1595b"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            } else if let root {
                if root.children.isEmpty {
                    Text(String(format: String(localized: "ui.DependencyTreeView.fmt.5dccdd0800"), locale: .current, "\(root.name)"))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        OutlineGroup([root], id: \.name, children: \.outlineChildren) { node in
                            Text(node.name)
                                .font(.body.monospaced())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 200, maxHeight: 360)
                }
            } else {
                Text(String(localized: "ui.DependencyTreeView.01ceb3edde"))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(4)
    }
}

struct FormulaDependencySheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    let formula: String
    @State private var displayMode: DependencyDisplayMode = .list

    private var graphPayload: (root: DependencyTreeNode, truncated: Bool)? {
        guard let root = viewModel.formulaDependencyRoot else { return nil }
        let limited = root.graphLimited()
        return (limited.node, limited.truncated)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "ui.DependencyTreeView.2bd7b9f1de"))
                        .font(.title2.bold())
                    Text(formula)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker(String(localized: "ui.DependencyTreeView.027446c2f9"), selection: $displayMode) {
                    ForEach(DependencyDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                Button(String(localized: "ui.DependencyTreeView.b15d91274e")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            Group {
                if viewModel.isLoadingFormulaDependencies {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(String(localized: "ui.DependencyTreeView.813ce1595b"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.formulaDependencyError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(20)
                } else if displayMode == .graph, let payload = graphPayload {
                    DependencyGraphView(root: payload.root, truncated: payload.truncated)
                        .padding(20)
                } else {
                    DependencyTreeView(
                        formula: formula,
                        root: viewModel.formulaDependencyRoot,
                        isLoading: false,
                        errorMessage: nil
                    )
                    .padding(20)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 560, height: 520)
        .task {
            await viewModel.loadFormulaDependencies(for: formula)
        }
    }
}

#Preview {
    FormulaDependencySheet(formula: "node")
        .environment(AppViewModel())
}
