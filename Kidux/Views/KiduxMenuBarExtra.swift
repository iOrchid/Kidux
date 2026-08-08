import SwiftUI
import AppKit

struct KiduxMenuBarLabel: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 4) {
            if viewModel.isBrewOperationBusy {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "shippingbox.fill")
            }
            if viewModel.settings.showMenuBarHealthIndicator,
               viewModel.menuBarHealthStatus != .green {
                Circle()
                    .fill(viewModel.menuBarHealthStatus.color)
                    .frame(width: 6, height: 6)
            }
            if viewModel.outdatedCount > 0 {
                Text("\(viewModel.outdatedCount)")
                    .font(.caption2.bold())
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [BrandInfo.menuBarTitle]
        if let busy = viewModel.services.brewBusyTitle {
            parts.append(busy)
        }
        if viewModel.settings.showMenuBarHealthIndicator {
            parts.append(viewModel.menuBarHealthStatus.summaryLine)
        }
        if viewModel.outdatedCount > 0 {
            parts.append(String(format: String(localized: "ui.KiduxMenuBarExtra.fmt.f7abdad8e7"), locale: .current, "\(viewModel.outdatedCount)"))
        }
        return parts.joined(separator: "，")
    }
}

struct KiduxMenuBarMenu: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        Button(String(localized: "menubar.open_main")) {
            viewModel.focusMainWindow()
        }
        .keyboardShortcut("o")

        Divider()

        Button(String(localized: "ui.KiduxMenuBarExtra.3859050382")) {
            viewModel.navigateTo(.discover)
            viewModel.focusMainWindow()
        }
        .keyboardShortcut("d")

        Button(String(localized: "ui.KiduxMenuBarExtra.9d5bf2a10a")) {
            viewModel.navigateTo(.installed)
            viewModel.focusMainWindow()
        }
        .keyboardShortcut("i")

        if viewModel.outdatedCount > 0 {
            Button(String(format: String(localized: "ui.KiduxMenuBarExtra.fmt.99e0eb7a40"), locale: .current, "\(viewModel.outdatedCount)")) {
                viewModel.openInstalledUpdates()
            }
            .keyboardShortcut("u")
        }

        Button(String(localized: "ui.KiduxMenuBarExtra.aef3db49a1")) {
            viewModel.navigateTo(.environment)
            viewModel.focusMainWindow()
        }

        if viewModel.settings.showMenuBarHealthIndicator,
           let detail = viewModel.menuBarHealthDetailLine {
            Text(detail)
                .foregroundStyle(.secondary)
        }

        Divider()

        Button(String(localized: "ui.KiduxMenuBarExtra.d341972b2e")) {
            Task {
                await viewModel.scanInstalledStatus(force: true)
                await viewModel.checkForUpdates(force: true)
                await viewModel.refreshMenuBarEnvironment()
            }
        }
        .disabled(viewModel.isScanningInstalled || viewModel.isCheckingUpdates)

        Button(String(localized: "ui.KiduxMenuBarExtra.c87b272f25")) {
            viewModel.focusMainWindow()
            viewModel.openCommandPalette()
        }
        .keyboardShortcut("k")

        Button(String(localized: "ui.KiduxMenuBarExtra.7209c9f473")) {
            viewModel.openSystemSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button(String(localized: "app.quit")) {
            KiduxTerminationGuard.requestQuit()
        }
        .keyboardShortcut("q")
    }
}

struct KiduxMenuBarScene: Scene {
    let viewModel: AppViewModel

    var body: some Scene {
        MenuBarExtra {
            KiduxMenuBarMenu()
                .environment(viewModel)
        } label: {
            KiduxMenuBarLabel()
                .environment(viewModel)
        }
        .menuBarExtraStyle(.menu)
    }
}
