# 参与启椟 · Kidux

## 环境

- macOS 15+
- Xcode（与工程的 Swift / macOS deployment 一致）
- 可选：Homebrew（运行期安装能力依赖它）

## 配置

### Apple Team ID

编辑 [`Kidux/Config/Signing.xcconfig`](Kidux/Config/Signing.xcconfig) 中的 `DEVELOPMENT_TEAM`，或参考同目录 `Signing.xcconfig.example`。

在 Xcode → Settings → Accounts 登录 Apple ID，并为 `Kidux`、`KiduxShareExtension`、`KiduxWidgets` 选择同一 Team。

### 仓库 URL

远程更新与资源地址由 [`Kidux/Config/RepositoryConfig.swift`](Kidux/Config/RepositoryConfig.swift) 统一派生（含 Releases、`data/`、`bin/appcast.xml` 等）。

若 Fork 到自己的仓库，请修改该文件中的 `owner` / `name` / `defaultBranch`，并保持 `Signing.xcconfig` 里的 `INFOPLIST_KEY_SUFeedURL` 与之一致。

请勿将密钥、证书或含凭据的本地配置提交到仓库。

## 构建

```bash
xcodebuild -project Kidux.xcodeproj -scheme Kidux \
  -configuration Debug -derivedDataPath ./build/DerivedData build
```

或用 Xcode 打开 `Kidux.xcodeproj`，选择 scheme `Kidux` 后运行（⌘R）。提交 PR 前请在本地完成构建验证。

## 反馈

| 类型 | 渠道 |
|------|------|
| Bug / 功能请求 | [Issues](https://github.com/iOrchid/Kidux/issues) |
| 用法与讨论 | [Discussions](https://github.com/iOrchid/Kidux/discussions) |
| 安全问题 | 请勿在公开 Issue 中粘贴密钥；联系维护者并轮换凭据 |

## 贡献范围

- 欢迎：崩溃修复、性能改进、文档笔误、Catalog / Bundle 纠错、可访问性
- 请先开 Issue 讨论：大范围重构、绕过合规的破解源、与 Homebrew 装机无关的能力堆叠

## License

[MIT](LICENSE)

```text
MIT License

Copyright (c) 2026 Kidux

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
