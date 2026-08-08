#!/bin/bash
# Kidux — 配置 Starship 提示符（支持 zsh / fish，由 KIDUX_SHELL 控制）
set -euo pipefail

if ! command -v starship >/dev/null 2>&1; then
  echo "starship 未安装，跳过配置"
  exit 0
fi

SHELL_KIND="${KIDUX_SHELL:-zsh}"

if [ "$SHELL_KIND" = "fish" ]; then
  FISH_DIR="${HOME}/.config/fish"
  FISH_CONFIG="${FISH_DIR}/config.fish"
  mkdir -p "$FISH_DIR"
  touch "$FISH_CONFIG"
  if grep -q 'starship init fish' "$FISH_CONFIG" 2>/dev/null; then
    echo "Starship（Fish）已配置"
    exit 0
  fi
  {
    echo ""
    echo "# Kidux — Starship prompt"
    echo "starship init fish | source"
  } >> "$FISH_CONFIG"
  echo "Starship 配置完成（Fish）"
  exit 0
fi

INIT_LINE='eval "$(starship init zsh)"'
ZSHRC="${HOME}/.zshrc"
touch "$ZSHRC"

if grep -q 'starship init zsh' "$ZSHRC" 2>/dev/null; then
  echo "Starship（Zsh）已配置"
  exit 0
fi

{
  echo ""
  echo "# Kidux — Starship prompt"
  echo "$INIT_LINE"
} >> "$ZSHRC"
echo "Starship 配置完成（Zsh）"
