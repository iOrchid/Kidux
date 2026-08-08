#!/bin/bash
# Kidux — Fish Shell 基础配置（S17-12；不执行 chsh）
set -euo pipefail

FISH_DIR="${HOME}/.config/fish"
FISH_CONFIG="${FISH_DIR}/config.fish"
mkdir -p "$FISH_DIR"

if [ -f "$FISH_CONFIG" ] && grep -q 'Kidux — Fish' "$FISH_CONFIG" 2>/dev/null; then
  echo "Fish 配置已存在，跳过"
  exit 0
fi

touch "$FISH_CONFIG"

{
  echo ""
  echo "# Kidux — Fish"
  echo "if test -d /opt/homebrew/bin"
  echo "  fish_add_path /opt/homebrew/bin /opt/homebrew/sbin"
  echo "else if test -d /usr/local/bin"
  echo "  fish_add_path /usr/local/bin /usr/local/sbin"
  echo "end"
  echo "set -gx LANG en_US.UTF-8"
} >> "$FISH_CONFIG"

echo "已写入 Fish 基础配置 → ${FISH_CONFIG}"
echo "提示：如需将登录 Shell 切换为 Fish，请手动执行：chsh -s \"\$(brew --prefix)/bin/fish\""
