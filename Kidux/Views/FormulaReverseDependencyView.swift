import SwiftUI

struct FormulaReverseDependencySheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    let formula: String
    @State private var dependents: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "ui.FormulaReverseDependencyView.f95a425758"))
                        .font(.title2.bold())
                    Text(formula)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "ui.FormulaReverseDependencyView.b15d91274e")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            Group {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(String(localized: "ui.FormulaReverseDependencyView.ac08584618"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(20)
                } else if dependents.isEmpty {
                    EmptyStateView(
                        title: String(localized: "ui.FormulaReverseDependencyView.82fe5518fa"),
                        systemImage: "shield.checkmark",
                        description: String(localized: "ui.FormulaReverseDependencyView.e025902283")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(dependents, id: \.self) { name in
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.up")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                    Text(name)
                                        .font(.body.monospaced())
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        .padding(16)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 480, height: 420)
        .task {
            await loadDependents()
        }
    }

    private func loadDependents() async {
        isLoading = true
        defer { isLoading = false }
        do {
            dependents = await viewModel.fetchReverseDependencies(formula: formula)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
