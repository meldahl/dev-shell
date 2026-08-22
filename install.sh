#!/usr/bin/env bash
# dev-shell installer for zsh.
#
#   ./install.sh                     asks where your projects live, then
#                                    whether to customize the look
#   ./install.sh --dev-root ~/code   no question about the path
#
# Writes a dev-shell block to ~/.zshrc -- re-running replaces it, so this is
# also how you change the settings later; every question defaults to the
# current setting -- and installs zsh-autosuggestions plus
# history-substring-search if oh-my-zsh is present. Without a terminal to ask
# on (curl | bash, CI, a dotfiles script) the path must be given, via
# --dev-root or DEV_ROOT in the environment, unless a block already has it;
# the look keeps its current values. Anything given here is not asked for:
#
#   --dev-root DIR        projects directory
#   --ux on|off           completion styling (menu, colours, suggestions)
#   --keys on|off         Up/Down history search keybindings
#   --accent N            256-colour index for the selected item
#   --continuation STR    continuation prompt (PS2)
#   --uninstall           remove the block again (backup first)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
START="# >>> dev-shell >>>"
END="# <<< dev-shell <<<"
DEFAULT_CONTINUATION='%_❯❯ '   # %_ is zsh's name for the open construct (dquote, then, ...)

usage() {
  echo "usage: ./install.sh [--dev-root DIR] [--ux on|off] [--keys on|off]"
  echo "                    [--accent N] [--continuation STR]"
  echo "       ./install.sh --uninstall"
}

# on/off flags accept a few spellings; prints 1 or 0, fails otherwise.
onoff() {
  case $1 in
    on|1|yes|true)   printf 1 ;;
    off|0|no|false)  printf 0 ;;
    *) return 1 ;;
  esac
}

arg_root="" arg_ux="" arg_keys="" arg_accent="" arg_cont="" cont_given=0 uninstall=0
while [ $# -gt 0 ]; do
  case $1 in
    -h|--help)   usage; exit 0 ;;
    --uninstall) uninstall=1; shift; continue ;;
    --dev-root|--ux|--keys|--accent|--continuation)
      [ $# -ge 2 ] || { usage >&2; exit 2; } ;;
    *) usage >&2; exit 2 ;;
  esac
  case $1 in
    --dev-root)     arg_root=$2 ;;
    --ux)           arg_ux=$(onoff "$2")   || { echo "error: --ux takes on|off" >&2; exit 2; } ;;
    --keys)         arg_keys=$(onoff "$2") || { echo "error: --keys takes on|off" >&2; exit 2; } ;;
    --accent)       case $2 in ''|*[!0-9]*) false ;; *) [ "$2" -le 255 ] ;; esac \
                      || { echo "error: --accent takes a number 0-255" >&2; exit 2; }; arg_accent=$2 ;;
    --continuation) arg_cont=$2; cont_given=1 ;;
  esac
  shift 2
done

if [ ! -f "$ZSHRC" ]; then
  echo "error: $ZSHRC not found" >&2
  exit 1
fi

if (( uninstall )); then
  if ! grep -qFx "$START" "$ZSHRC"; then
    echo "no dev-shell block in $ZSHRC -- nothing to remove."
    exit 0
  fi
  if ! grep -qFx "$END" "$ZSHRC"; then
    echo "error: $ZSHRC has '$START' but no '$END'." >&2
    echo "       Remove the block by hand: delete from '$START' down to the line that sources" >&2
    echo "       dev-shell.zsh, or restore a $ZSHRC.dev-shell-backup-* file." >&2
    exit 1
  fi
  cp "$ZSHRC" "$ZSHRC.dev-shell-backup-$(date +%Y%m%d-%H%M%S)"
  tmp="$(mktemp)"
  # Drop the block and the blank line the installer put above it; keep
  # everything else as it was.
  START="$START" END="$END" awk '
    function flush() { if (pending) { print ""; pending = 0 } }
    skip { if ($0 == ENVIRON["END"]) skip = 0; next }
    $0 == ENVIRON["START"] { skip = 1; pending = 0; next }
    $0 == "" { flush(); pending = 1; next }
    { flush(); print }
    END { flush() }
  ' "$ZSHRC" > "$tmp"
  cp "$tmp" "$ZSHRC" && rm -f "$tmp"
  if ! zsh -n "$ZSHRC"; then
    echo "error: $ZSHRC has a syntax error after removing the block; restore from the backup above" >&2
    exit 1
  fi
  echo "removed the dev-shell block from $ZSHRC (backup beside it). Open a new zsh session."
  echo "note: the oh-my-zsh plugins the installer enabled stay in plugins=(...); drop them there if you like."
  exit 0
fi

interactive=0
[ -t 0 ] && interactive=1

# The value a variable has in the existing block, unquoted and unescaped.
# Fails when there is no block or the block does not set it.
current() {
  awk -v s="$START" -v e="$END" -v n="$1" '
    $0 == s { b = 1; next }
    $0 == e { b = 0 }
    b { l = $0; sub(/^export /, "", l)
        if (index(l, n "=") == 1) { found = 1; print substr(l, length(n) + 2); exit } }
    END { exit !found }
  ' "$ZSHRC" | sed -E 's/^"(.*)"$/\1/; s/\\([\\"$`])/\1/g'
}
# Double-quote a value for the block (zsh double-quote escaping).
quoted() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/[\\"$`]/\\&/g')"; }
# Ask with a default shown in brackets; Enter keeps it. Terminal only. IFS=
# keeps the answer verbatim (a continuation prompt ends in a space).
ask() { # $1 prompt, $2 default -> REPLY
  IFS= read -r -e -p "$1 [$2]: " REPLY
  REPLY=${REPLY:-$2}
}
# y/n with a default -> YN (1|0). Every prompt goes through read -e in this
# shell: readline buffers stdin, so a plain or subshell read after it can
# starve when the input is piped.
ask_yn() { # $1 prompt, $2 default (1|0) -> YN
  local hint reply
  [ "$2" = 1 ] && hint="Y/n" || hint="y/N"
  while :; do
    read -r -e -p "$1 [$hint]: " reply
    case $reply in
      "")                YN=$2; return ;;
      [Yy]|[Yy][Ee][Ss]) YN=1; return ;;
      [Nn]|[Nn][Oo])     YN=0; return ;;
    esac
    echo "  please answer y or n"
  done
}
# How the menu, suggestions and continuation prompt will look with the given
# settings, on sample projects, so the choice can be made by eye.
preview() { # $1 ux (1|0), $2 accent, $3 continuation
  local off=$'\033[0m' hdr=$'\033[1;38;5;81m' sel=$'\033[1;38;5;'"$2"'m' ghost=$'\033[38;5;244m'
  if [ "$1" != 1 ]; then
    echo
    echo "  (styling off: plain completion list, no colours, no suggestions)"
    echo "  PROJECT        │ BRANCH"
    echo "  api            │ on main"
    echo "  website        │ on feat/dark-mode"
    echo "  notes          │ no git repo"
    echo
    return
  fi
  echo
  echo "  % dev <Tab>"
  echo "  ${hdr}PROJECT        │ BRANCH${off}"
  echo "  api            │ on main"
  echo "  ${sel}website        │ on feat/dark-mode${off}          <- selected row, in the accent"
  echo "  notes          │ no git repo"
  echo
  echo "  % dev web${ghost}site -c${off}                          <- suggestion from history"
  echo "  % echo \"multi"
  echo "  ${3//\%_/dquote}line\"                                 <- continuation prompt"
  echo
}

# --- projects directory: --dev-root wins; otherwise ask, defaulting to the
# current setting (block, then environment, then ~/dev); without a terminal
# take the environment or the block, or insist on being told rather than guess.
cur_root=$(current DEV_ROOT) || cur_root=""
if [ -n "$arg_root" ]; then
  DEV_ROOT=$arg_root
elif (( interactive )); then
  default=${cur_root:-${DEV_ROOT:-$HOME/dev}}
  while :; do
    ask "Projects directory" "$default"
    answer=${REPLY/#\~/$HOME}   # read does not expand a leading ~
    case $answer in /*) break ;; esac
    echo "  please give an absolute path (or ~/...)"
  done
  DEV_ROOT=$answer
elif [ -n "${DEV_ROOT:-}" ]; then
  :   # from the environment
elif [ -n "$cur_root" ]; then
  DEV_ROOT=$cur_root
else
  echo "error: no terminal to ask on. Pass the projects directory:" >&2
  echo "       ./install.sh --dev-root /path/to/projects   (or DEV_ROOT=... ./install.sh)" >&2
  exit 1
fi
[ -d "$DEV_ROOT" ] || echo "note: $DEV_ROOT does not exist yet -- dev will say so until it does."

# --- the look: current settings, then a gated round of questions (skipped
# when any look flag was given), then the flags on top.
ux=$(current DEV_SHELL_UX)               || ux=1
keys=$(current DEV_SHELL_KEYS)           || keys=1
accent=$(current DEV_SHELL_ACCENT)       || accent=214
cont=$(current DEV_SHELL_CONTINUATION)   || cont=$DEFAULT_CONTINUATION
look_given=0
[ -n "$arg_ux$arg_keys$arg_accent" ] || (( cont_given )) && look_given=1 || true

if (( interactive && ! look_given )); then
  echo "This is how it looks now:"
  preview "$ux" "$accent" "$cont"
  ask_yn "Customize the look (styling, continuation prompt, accent colour, keys)?" 0
  if (( YN )); then
    while :; do
      ask_yn "Completion styling (menu, colours, suggestions) on?" "$ux"; ux=$YN
      if (( ux )); then
        ask "Continuation prompt" "$cont"; cont=$REPLY
        while :; do
          ask "Accent colour, 0-255" "$accent"
          case $REPLY in ''|*[!0-9]*) ;; *) [ "$REPLY" -le 255 ] && { accent=$REPLY; break; } ;; esac
          echo "  please give a number 0-255"
        done
      fi
      ask_yn "Up/Down search history by what is already typed?" "$keys"; keys=$YN
      echo "With those settings:"
      preview "$ux" "$accent" "$cont"
      ask_yn "Keep these?" 1
      (( YN )) && break
    done
  fi
fi
[ -n "$arg_ux" ]     && ux=$arg_ux
[ -n "$arg_keys" ]   && keys=$arg_keys
[ -n "$arg_accent" ] && accent=$arg_accent
(( cont_given ))     && cont=$arg_cont
true

cp "$ZSHRC" "$ZSHRC.dev-shell-backup-$(date +%Y%m%d-%H%M%S)"

BLOCK="$START
export DEV_ROOT=$(quoted "$DEV_ROOT")
DEV_SHELL_UX=$ux
DEV_SHELL_KEYS=$keys
DEV_SHELL_ACCENT=$accent
DEV_SHELL_CONTINUATION=$(quoted "$cont")
source $(quoted "$REPO/zsh/dev-shell.zsh")
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
