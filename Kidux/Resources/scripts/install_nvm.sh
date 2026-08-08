#!/bin/bash
# Kidux — 安装 nvm（Node 版本管理器）
set -euo pipefail

export NVM_DIR="${HOME}/.nvm"

if [ -d "$NVM_DIR" ]; then
  echo "nvm 已存在，跳过"
  exit 0
fi

curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

# 写入 .zshrc（如未配置）
if ! grep -q 'NVM_DIR' "${HOME}/.zshrc" 2>/dev/null; then
  cat >> "${HOME}/.zshrc" << 'EOF'

# Kidux — nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF
  echo "已写入 nvm 配置到 .zshrc"
fi

echo "nvm 安装完成"
