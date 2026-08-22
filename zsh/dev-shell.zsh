# dev-shell — project navigation and completion polish for zsh.
#
# Source this from ~/.zshrc:
#     source /path/to/dev-shell/zsh/dev-shell.zsh
#
# Optional configuration, set BEFORE sourcing:
#   DEV_ROOT                directory holding your projects  (default: $HOME/dev)
#   DEV_SHELL_UX            0 to skip the completion styling (keeps just the command)
#   DEV_SHELL_KEYS          0 to skip the history keybindings
#   DEV_SHELL_ACCENT        256-colour index for the selected item  (default: 214)
#   DEV_SHELL_CONTINUATION  continuation prompt, i.e. PS2  (default: "%_❯❯ " -- %_ names
#                           the open construct, e.g. dquote, as zsh's own default does)

: ${DEV_ROOT:=$HOME/dev}
export DEV_ROOT

_dev_is_wsl() { [[ -n $WSL_DISTRO_NAME ]] }

# Open a directory in the desktop file manager: Explorer from WSL, Finder on
# macOS, the preferred handler elsewhere.
_dev_open() {
  if _dev_is_wsl; then
    # explorer.exe returns a non-zero exit code even on success.
    explorer.exe "$(wslpath -w "$1")" 2>/dev/null
    return 0
  fi
  if [[ $OSTYPE == darwin* ]]; then
    open "$1"
    return
  fi
  if (( $+commands[xdg-open] )); then
    xdg-open "$1" >/dev/null 2>&1
    return
  fi
  print -u2 "dev: no file manager opener found (explorer.exe, open, xdg-open)"
  return 1
}

dev() {
  local open_code=0 open_folder=0

  while [[ $1 == -* ]]; do
    case $1 in
      -c|--code)               open_code=1 ;;
      -o|--open|-e|--explorer) open_folder=1 ;;
      -h|--help)
        print "usage: dev [-c|--code] [-o|--open] [project]"
        print "  -c, --code   open the project in VS Code"
        print "  -o, --open   open the project in your file manager"
        print "               (Explorer, Finder, or the desktop default; -e/--explorer still work)"
        print "  with no project, acts on \$DEV_ROOT ($DEV_ROOT)"
        return 0
        ;;
      *)
        print -u2 "dev: unknown option: $1"
        return 1
        ;;
    esac
    shift
  done

  if [[ ! -d $DEV_ROOT ]]; then
    print -u2 "dev: DEV_ROOT does not exist: $DEV_ROOT"
    return 1
  fi

  local target=$DEV_ROOT
  [[ -n $1 ]] && target=$DEV_ROOT/$1

  if [[ ! -d $target ]]; then
    print -u2 "dev: no such project: $1"
    return 1
  fi

  if (( open_code )); then
    if (( ! $+commands[code] )); then
      print -u2 "dev: 'code' is not on PATH"
      return 1
    fi
    code "$target"
    return
  fi

  if (( open_folder )); then
    _dev_open "$target"
    return
  fi

  cd "$target"
}

# Read the current branch straight from .git, without spawning git. Faster on
# every Tab (no process per project), and it sidesteps git's safe.directory
# refusal when a Windows git inspects a repo living inside WSL.
_dev_branch() {
  local dir=$1 gitdir=$1/.git line
  if [[ -f $gitdir ]]; then
    # Worktrees and submodules store "gitdir: <path>" in a file.
    line=$(<$gitdir)
    gitdir=${line#gitdir: }
    [[ $gitdir == /* ]] || gitdir=$dir/$gitdir
  fi
  [[ -r $gitdir/HEAD ]] || return 1
  line=$(<$gitdir/HEAD)
  if [[ $line == "ref: refs/heads/"* ]]; then
    print -r -- ${line#ref: refs/heads/}
  else
    print -r -- ${line[1,7]}
  fi
}
# One row per project, with the current git branch as a description column.
#
# _describe would collapse projects that share a branch onto a single row, so
# the display strings are built directly. Note that zsh escapes control
# characters inside compadd display strings, and list-colors patterns match the
# completion VALUE rather than the displayed text -- so the description column
# cannot be coloured separately. The header and the │ rule carry that job.
# -l lists one project per row: without it zsh packs the display strings into
# as many columns as fit, and the header then tops only the first of them.
_dev_projects() {
  local -a names displays
  local d name branch label hdr=PROJECT
  integer width=0

  [[ -d $DEV_ROOT ]] || return 1

  for d in $DEV_ROOT/*(/N); do
    name=${d:t}
    (( ${#name} > width )) && width=${#name}
  done
  (( width )) || return 1

  for d in $DEV_ROOT/*(/N); do
    name=${d:t}
    branch=$(_dev_branch "$d")
    if [[ -n $branch ]]; then
      label="on $branch"
    else
      label="no git repo"
    fi
    names+=("$name")
    displays+=("${(r:$width:)name}  │ $label")
  done

  compadd -Q -l -X "%F{81}%B${(r:$width:)hdr}  │ BRANCH%b%f" -d displays -a names
}

_dev() {
  _arguments \
    '(-c --code)'{-c,--code}'[open in VS Code]' \
    '(-o --open -e --explorer)'{-o,--open,-e,--explorer}'[open in the file manager]' \
    '1:project:_dev_projects'
}
compdef _dev dev

# --- Shell UX ---------------------------------------------------------------
if [[ ${DEV_SHELL_UX:-1} == 1 ]]; then
  # Label each completion group so the list has a heading.
  zstyle ':completion:*' group-name ''
  zstyle ':completion:*:descriptions' format '%F{81}%B%d%b%f'

  # Arrow-navigable menu. 'ma' recolours the selected entry instead of filling
  # a background box, which would otherwise run into the next column. The
  # accent (amber by default) keeps it clear of the cyan header and the
  # default light-blue text.
  zstyle ':completion:*' menu select
  zmodload -i zsh/complist
  zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}" "ma=1;38;5;${DEV_SHELL_ACCENT:-214}"

  # Continuation prompt, matching the PowerShell side; %_ keeps zsh's hint of
  # which construct is still open (dquote, then, ...), which PS2 shows by default.
  PS2=${DEV_SHELL_CONTINUATION-'%_❯❯ '}

  # Ghost-text suggestions from history (requires the zsh-autosuggestions
  # plugin; harmless if it is not installed).
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=244'
fi

# Up/Down search history by what is already typed. Requires the
# history-substring-search plugin, so only bind when it actually loaded.
if [[ ${DEV_SHELL_KEYS:-1} == 1 ]] && (( $+functions[history-substring-search-up] )); then
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
fi