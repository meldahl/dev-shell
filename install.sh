#!/usr/bin/env bash
# dev-shell installer for zsh.
#
#   ./install.sh                     asks where your projects live
#   ./install.sh --dev-root ~/code   no questions
#
# Writes a dev-shell block to ~/.zshrc -- re-running replaces it, so this is
# also how you change the settings later -- and installs zsh-autosuggestions
# plus history-substring-search if oh-my-zsh is present. Without a terminal to
# ask on (curl | bash, CI, a dotfiles script) the path must be given, via
# --dev-root or DEV_ROOT in the environment.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
START="# >>> dev-shell >>>"
END="# <<< dev-shell <<<"

usage() { echo "usage: ./install.sh [--dev-root DIR]"; }

root_arg=""
while [ $# -gt 0 ]; do
  case $1 in
    --dev-root) [ $# -ge 2 ] || { usage >&2; exit 2; }; root_arg=$2; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *)          usage >&2; exit 2 ;;
  esac
done

if [ ! -f "$ZSHRC" ]; then
  echo "error: $ZSHRC not found" >&2
  exit 1
fi

# Projects directory: --dev-root wins; otherwise ask, offering the current
# DEV_ROOT (or ~/dev) as the default. With no terminal to ask on, take DEV_ROOT
# from the environment or insist on being told rather than guess.
default="${DEV_ROOT:-$HOME/dev}"
if [ -n "$root_arg" ]; then
  DEV_ROOT=$root_arg
elif [ -t 0 ]; then
  while :; do
    read -r -e -p "Projects directory [$default]: " answer
    answer="${answer:-$default}"
    answer="${answer/#\~/$HOME}"   # read does not expand a leading ~
    case $answer in /*) break ;; esac
    echo "  please give an absolute path (or ~/...)"
  done
  DEV_ROOT=$answer
elif [ -z "${DEV_ROOT:-}" ]; then
  echo "error: no terminal to ask on. Pass the projects directory:" >&2
  echo "       ./install.sh --dev-root /path/to/projects   (or DEV_ROOT=... ./install.sh)" >&2
  exit 1
fi
[ -d "$DEV_ROOT" ] || echo "note: $DEV_ROOT does not exist yet -- dev will say so until it does."

cp "$ZSHRC" "$ZSHRC.dev-shell-backup-$(date +%Y%m%d-%H%M%S)"

BLOCK="$START
export DEV_ROOT=\"$DEV_ROOT\"
source \"$REPO/zsh/dev-shell.zsh\"
$END"

if grep -qFx "$START" "$ZSHRC"; then
  if ! grep -qFx "$END" "$ZSHRC"; then
    echo "error: $ZSHRC has '$START' but no '$END'; fix the block by hand" >&2
    exit 1
  fi
  # Swap the old block for the new one in place, so re-running changes settings.
  tmp="$(mktemp)"
  START="$START" END="$END" BLOCK="$BLOCK" awk '
    $0 == ENVIRON["START"] { print ENVIRON["BLOCK"]; skip = 1; next }
    $0 == ENVIRON["END"]   { skip = 0; next }
    !skip
  ' "$ZSHRC" > "$tmp"
  cp "$tmp" "$ZSHRC" && rm -f "$tmp"
  echo "updated dev-shell block in $ZSHRC"
else
  printf '\n%s\n' "$BLOCK" >> "$ZSHRC"
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

echo "done -- dev will use $DEV_ROOT. Open a new zsh session, or run: source $ZSHRC"
