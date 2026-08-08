#!/bin/bash
# Kidux — 配置 Zsh 插件（autosuggestions + syntax-highlighting）
set -euo pipefail

ZSH_CUSTOM="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"

install_plugin() {
  local name="$1"
  local repo="$2"
  local dir="${ZSH_CUSTOM}/plugins/${name}"
  if [ -d "$dir" ]; then
    echo "插件 ${name} 已存在"
    return
  fi
  git clone --depth=1 "$repo" "$dir"
  echo "已安装插件 ${name}"
}

install_plugin "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions.git"
install_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git"

# 更新 .zshrc plugins 行
if [ -f "${HOME}/.zshrc" ]; then
  if grep -q '^plugins=' "${HOME}/.zshrc"; then
    sed -i '' 's/^plugins=(.*)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "${HOME}/.zshrc" 2>/dev/null || \
    sed -i 's/^plugins=(.*)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "${HOME}/.zshrc"
  else
    echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> "${HOME}/.zshrc"
  fi
  echo "已更新 .zshrc plugins 配置"
fi

echo "Zsh 插件配置完成"
