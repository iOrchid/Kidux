import SwiftUI
import TipKit

/// S20-04 — 情境引导（首次配置 / 换机 / 发现 NL / FM）
@available(macOS 14.0, *)
struct DiscoverNaturalLanguageTip: Tip {
    var title: Text { Text("用自然语言找软件") }
    var message: Text? {
        Text("试试输入「适合前端的编辑器」，或点麦克风语音搜索。")
    }
    var image: Image? { Image(systemName: "sparkles") }
}

@available(macOS 14.0, *)
struct MigrationWizardTip: Tip {
    var title: Text { Text("换机向导") }
    var message: Text? {
        Text("旧机导出快照，新机导入后可一键补齐环境。")
    }
    var image: Image? { Image(systemName: "arrow.triangle.2.circlepath") }
}

@available(macOS 14.0, *)
struct DryRunInstallTip: Tip {
    var title: Text { Text("安装前先预览") }
    var message: Text? {
        Text("「模拟安装」会列出将执行的 brew/mas 命令，不会真正安装。")
    }
    var image: Image? { Image(systemName: "eye") }
}

enum KiduxTips {
    static func configureIfAvailable() {
        if #available(macOS 14.0, *) {
            try? Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.applicationDefault)
            ])
        }
    }
}
