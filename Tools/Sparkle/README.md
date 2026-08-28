# Sparkle 签名工具

从 [Sparkle 2.9.3 Release](https://github.com/sparkle-project/Sparkle/releases/download/2.9.3/Sparkle-2.9.3.tar.xz) 解压后，将 `bin/generate_keys` 与 `bin/sign_update` 放到本目录：

```bash
curl -L -o /tmp/Sparkle-2.9.3.tar.xz \
  https://github.com/sparkle-project/Sparkle/releases/download/2.9.3/Sparkle-2.9.3.tar.xz
mkdir -p /tmp/SparkleExtract
tar -xJf /tmp/Sparkle-2.9.3.tar.xz -C /tmp/SparkleExtract
cp /tmp/SparkleExtract/bin/generate_keys /tmp/SparkleExtract/bin/sign_update \
  Tools/Sparkle/
chmod +x Tools/Sparkle/generate_keys Tools/Sparkle/sign_update
```

Kidux 使用钥匙串 account **`kidux`**（与 `SUPublicEDKey` 对应）：

```bash
# 首次：生成密钥并把公钥写入 Xcode INFOPLIST_KEY_SUPublicEDKey
./Tools/Sparkle/generate_keys --account kidux

# 发布：对公证后的 DMG 签名，输出填入 bin/appcast.xml
./Tools/Sparkle/sign_update --account kidux build/Kidux-<version>.dmg

# 或一键（推荐：先 sync 公开源码，再公证+DMG+appcast）:
./bin/release.sh
# 只发安装包、不同步源码:
./bin/release.sh --no-sync
```

私钥仅存本机钥匙串，**不要**提交到仓库。详见 `docs/12-DISTRIBUTION.md` §8。
