# Sparkle (vendored)

本地嵌入 [Sparkle](https://sparkle-project.org/) **2.9.3** 的 `Sparkle.framework`，避免 Xcode SPM 从 GitHub Releases 拉二进制失败（`Missing package product 'Sparkle'`）。

升级方式：从官方 [Release](https://github.com/sparkle-project/Sparkle/releases) 下载 `Sparkle-for-Swift-Package-Manager.zip`，解出 `Sparkle.xcframework` / framework 后替换本目录，或重新用 SPM 官方源解析成功后再拷贝进 `Vendor/Sparkle/`。
