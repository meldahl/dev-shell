#!/usr/bin/env bash
# dev-shell installer for zsh.
#
#   ./install.sh              install, using $HOME/dev as DEV_ROOT
#   DEV_ROOT=~/code ./install.sh
#
# Adds a source line to ~/.zshrc, and installs zsh-autosuggestions plus
# history-substring-search if oh-my-zsh is present.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
DEV_ROOT="${DEV_ROOT:-$HOME/dev}"
MARKER="# >>> dev-shell >>>"

if [ ! -f "$ZSHRC" ]; then
  echo "error: $ZSHRC not found" >&2
  exit 1
fi

cp "$ZSHRC" "$ZSHRC.dev-shell-backup-$(date +%Y%m%d-%H%M%S)"

if grep -qF "$MARKER" "$ZSHRC"; then
  echo "dev-shell block already present in $ZSHRC -- leaving it alone."
else
  cat >> "$ZSHRC" <<EOF

$MARKER
export DEV_ROOT="$DEV_ROOT"
source "$REPO/zsh/dev-shell.zsh"
# <<< dev-shell <<<
EOF
  echo "added dev-shell block to $ZSHRC"
fi

# oh-my-zsh plugins: ghost-text suggestions and prefix history search.
OMZ="${ZSH:-$HOME/.oh-my-zsh}"
if [ -d "$OMZ" ]; then
  SUGG="$OMZ/custom/plugins/zsh-autosuggestions"
  if [ ! -d "$SUGG" ]; then
    echo "installing zsh-autosuggestions..."
    git clone --depth=1 -q https://github.com/zsh-users/zsh-autosuggestions "$SUGG"
  fi
  for p in zsh-autosuggestions history-substring-search; do
    if ! grep -qE "^plugins=.*[( ]$p[ )]" "$ZSHRC"; then
      sed -i -E "s/^(plugins=\()/\1$p /" "$ZSHRC"
      echo "enabled plugin: $p"
    fi
  done
else
  echo "note: oh-my-zsh not found -- install zsh-autosuggestions and"
  echo "      history-substring-search yourself for suggestions and history search."
fi

if ! zsh -n "$ZSHRC"; then
  echo "error: $ZSHRC has a syntax error; restore from the backup above" >&2
  exit 1
fi

echo "done. Open a new zsh session, or run: source $ZSHRC"