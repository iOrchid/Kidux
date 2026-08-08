#!/bin/bash
# Kidux — 导入 iTerm2 配色方案（Dracula）
set -euo pipefail

THEME_NAME="Dracula"
THEME_URL="https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/schemes/Dracula.itermcolors"
DEST_DIR="${HOME}/.macdevtools/iterm2-themes"
DEST_FILE="${DEST_DIR}/${THEME_NAME}.itermcolors"

mkdir -p "$DEST_DIR"

if [ -f "$DEST_FILE" ]; then
  echo "主题文件已存在: $DEST_FILE"
else
  echo "下载 iTerm2 主题: $THEME_NAME"
  curl -fsSL "$THEME_URL" -o "$DEST_FILE"
fi

# 通过 AppleScript 导入（需 iTerm2 已安装）
if [ -d "/Applications/iTerm.app" ]; then
  osascript <<EOF
tell application "iTerm"
  tell current terminal
    import color preset from "$DEST_FILE" as "$THEME_NAME"
  end tell
end tell
EOF
  echo "已导入 iTerm2 配色: $THEME_NAME"
  echo "请在 iTerm2 → Settings → Profiles → Colors → Color Presets 中选择 $THEME_NAME"
else
  echo "iTerm2 未安装，主题已保存到: $DEST_FILE"
  echo "安装 iTerm2 后手动导入该 .itermcolors 文件"
fi
