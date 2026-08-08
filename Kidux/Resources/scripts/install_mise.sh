#!/bin/bash
# Kidux — 安装 mise（多语言运行时版本管理）
set -euo pipefail

if command -v mise >/dev/null 2>&1; then
  echo "mise 已存在，跳过"
  exit 0
fi

curl -fsSL https://mise.jdx.dev/install.sh | sh

if ! grep -q 'mise activate' "${HOME}/.zshrc" 2>/dev/null; then
  echo 'eval "$(mise activate zsh)"' >> "${HOME}/.zshrc"
  echo "已写入 mise 配置到 .zshrc"
fi

echo "mise 安装完成"
