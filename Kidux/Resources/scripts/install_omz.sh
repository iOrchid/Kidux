#!/bin/bash
# Kidux — 安装 Oh My Zsh（非交互）
set -euo pipefail

if [ -d "${HOME}/.oh-my-zsh" ]; then
  echo "Oh My Zsh 已存在，跳过"
  exit 0
fi

export RUNZSH=no
export CHSH=no
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

echo "Oh My Zsh 安装完成"
