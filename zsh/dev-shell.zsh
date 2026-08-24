# dev-shell — project navigation and completion polish for zsh.
#
# Source this from ~/.zshrc:
#     source /path/to/dev-shell/zsh/dev-shell.zsh
#
# Optional configuration, set BEFORE sourcing:
#   DEV_ROOT                directory holding your projects  (default: $HOME/dev)
#   DEV_SHELL_UX            0 to skip the menu styling and the history list
#                           (keeps just the command)
#   DEV_SHELL_KEYS          0 to leave Up/Down/Esc at their zsh defaults
#   DEV_SHELL_ACCENT        256-colour index for the selected item  (default: 214)
#   DEV_SHELL_CONTINUATION  continuation prompt, i.e. PS2  (default: "%_❯❯ " -- %_ names
#                           the open construct, e.g. dquote, as zsh's own default does)
#
# The history list as you type is drawn here with no plugin. Ghost-text
# suggestions are a separate, optional extra: the zsh-autosuggestions plugin,
# sourced before this file. Everything is guarded, so a missing plugin only
# means the ghost text is absent.

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
  local open_code=0 open_folder=0 project='' arg

  # Options may come before or after the project, as PowerShell binds them.
  for arg in "$@"; do
    case $arg in
      -c|--code)               open_code=1 ;;
      -o|--open|-e|--explorer) open_folder=1 ;;
      -h|--help)
        print "usage: dev [project] [-c|--code] [-o|--open]"
        print "  -c, --code   open the project in VS Code"
        print "  -o, --open   open the project in your file manager"
        print "               (Explorer, Finder, or the desktop default; -e/--explorer still work)"
        print "  with no project, acts on \$DEV_ROOT ($DEV_ROOT)"
        return 0
        ;;
      -*)
        print -u2 "dev: unknown option: $arg"
        return 1
        ;;
      *)
        if [[ -n $project ]]; then
          print -u2 "dev: one project at a time: $project, $arg"
          return 1
        fi
        project=$arg
        ;;
    esac
  done

  if [[ ! -d $DEV_ROOT ]]; then
    print -u2 "dev: DEV_ROOT does not exist: $DEV_ROOT"
    return 1
  fi

  local target=$DEV_ROOT
  [[ -n $project ]] && target=$DEV_ROOT/$project

  if [[ ! -d $target ]]; then
    print -u2 "dev: no such project: $project"
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
  integer width=${#hdr}

  [[ -d $DEV_ROOT ]] || return 1

  for d in $DEV_ROOT/*(/N); do
    name=${d:t}
    names+=("$name")
    (( ${#name} > width )) && width=${#name}
  done
  (( $#names )) || return 1

  for name in $names; do
    branch=$(_dev_branch "$DEV_ROOT/$name")
    if [[ -n $branch ]]; then
      label="on $branch"
    else
      label="no git repo"
    fi
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
  zmodload -i zsh/complist
  autoload -Uz add-zle-hook-widget

  # Tab opens the project menu: compsys menu selection with the selected row
  # recoloured in the accent rather than boxed (a filled box abuts the next
  # column). 'ma' is the menu-selection colour.
  zstyle ':completion:*' menu select
  zstyle ':completion:*' group-name ''
  zstyle ':completion:*:descriptions' format '%F{81}%B%d%b%f'
  zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}" "ma=1;38;5;${DEV_SHELL_ACCENT:-214}"

  # Continuation prompt, matching the PowerShell side; %_ keeps zsh's hint of
  # which construct is still open (dquote, then, ...), which PS2 shows by default.
  PS2=${DEV_SHELL_CONTINUATION-'%_❯❯ '}

  # The history list is the prediction display, PowerShell's ListView -- its top
  # row is the suggestion. zsh-autosuggestions' inline ghost would fight it for
  # POSTDISPLAY, so turn the ghost off while the list is on (the plugin can stay
  # loaded for DEV_SHELL_UX=0, where the ghost works and there is no list).
  (( $+functions[_zsh_autosuggest_fetch] )) && typeset -g _ZSH_AUTOSUGGEST_DISABLED=1

  # --- History list as you type: PowerShell's PSReadLine ListView -----------
  # Matching history is drawn below the input in POSTDISPLAY -- up to ten
  # "> line" rows under a live "<i/N>  <History(i/N)>" heading -- and coloured
  # with region_highlight: the marker and heading grey, the matched text and
  # the selected row in the accent. Down/Up move the selection and copy it onto
  # the line; index -1 is the line you typed, so Up from the first row restores
  # it and its cursor, PowerShell's original item, with no extra row. Enter
  # runs the line; Esc or an edit dismisses it. The list is matched as a
  # case-insensitive substring, prefix matches first, newest first, no
  # duplicates or multi-line commands; (V) makes control characters printable
  # so a history line's own escapes cannot repaint the list. It is all drawn
  # and driven here -- no plugin -- so the header tracks the selection exactly
  # and nothing is faked. zsh-autosuggestions (ghost text) still layers on top.
  typeset -g  _dev_lv_orig='' _dev_lv_expect=$'\0'
  typeset -gi _dev_lv_sel=-1 _dev_lv_ocur=0 _dev_lv_off=0
  typeset -ga _dev_lv_matches=()
  typeset -gi _DEV_LV_MAX=10
  typeset -g  _dev_lv_accent="fg=${DEV_SHELL_ACCENT:-214},bold" _dev_lv_meta='fg=244'

  # Editing widgets: after one of these the list is (re)shown. Tab and the
  # project menu it opens suspend the list until the next real edit, so the two
  # never draw at once; cursor moves keep the list but do not un-suspend it.
  typeset -ga _DEV_LV_EDIT=(
    self-insert backward-delete-char delete-char delete-char-or-list
    backward-kill-word kill-word backward-kill-line kill-line kill-whole-line
    yank yank-pop bracketed-paste
  )
  # After these the list stays as it is (its own navigation and cursor moves).
  typeset -ga _DEV_LV_KEEP=(
    "${_DEV_LV_EDIT[@]}" forward-char backward-char
    beginning-of-line end-of-line _dev_lv_down _dev_lv_up
  )

  # Drop the list's own region_highlight entries. ZLE 5.8 strips the `memo`
  # attribute, so they cannot be tagged -- but they are the only highlights in
  # the POSTDISPLAY range (offset >= the buffer length), so filter by offset and
  # keep anything colouring the buffer itself (e.g. syntax highlighting).
  _dev_lv_clear_hl() {
    local -a keep=(); local e
    for e in $region_highlight; do
      (( ${e%% *} < $#BUFFER )) && keep+=( "$e" )
    done
    region_highlight=( "${keep[@]}" )
  }

  _dev_lv_hide() {
    _dev_lv_matches=(); POSTDISPLAY=''
    _dev_lv_clear_hl
  }

  _dev_lv_compute() {
    setopt localoptions extendedglob
    _dev_lv_matches=()
    local q=$BUFFER
    [[ -z $q ]] && return
    local -a nums=( ${(On)${(k)history[(R)(#i)*${(b)q}*]}} )
    local -A seen; local n cmd; local -a pre=() rest=()
    for n in $nums; do
      cmd=$history[$n]
      [[ $cmd == *$'\n'* ]] && continue
      (( ${#cmd} <= ${#q} )) && continue     # nothing to add over what is typed
      (( $+seen[$cmd] )) && continue
      seen[$cmd]=1
      if [[ $cmd == (#i)${(b)q}* ]]; then pre+=( "$cmd" ); else rest+=( "$cmd" ); fi
      (( $#pre >= _DEV_LV_MAX && $#rest >= _DEV_LV_MAX )) && break
    done
    _dev_lv_matches=( "${(@)pre}" "${(@)rest}" )
    (( $#_dev_lv_matches > _DEV_LV_MAX )) && _dev_lv_matches=( "${(@)_dev_lv_matches[1,_DEV_LV_MAX]}" )
  }

  _dev_lv_render() {
    setopt localoptions extendedglob
    local lw=${LASTWIDGET#.}
    # A genuine edit ends a Tab/menu suspension; while suspended, stay hidden.
    if (( _dev_lv_off )); then
      if (( ${_DEV_LV_EDIT[(Ie)$lw]} )); then _dev_lv_off=0
      else _dev_lv_hide; return; fi
    fi
    # Draw only after an edit or the list's own navigation.
    if [[ -n $LASTWIDGET ]] && (( ! ${_DEV_LV_KEEP[(Ie)$lw]} )); then
      _dev_lv_hide; return
    fi
    if [[ $BUFFER != $_dev_lv_expect ]]; then     # a real edit
      _dev_lv_sel=-1; _dev_lv_orig=$BUFFER; _dev_lv_ocur=$CURSOR
      _dev_lv_expect=$BUFFER; _dev_lv_compute
    fi
    _dev_lv_clear_hl
    if (( ! $#_dev_lv_matches )); then POSTDISPLAY=''; return; fi

    # Heading: "<i/N>" hard left, "<History(i/N)>" hard right, spread across the
    # window as PowerShell's ListView shows it.
    local -i n=$#_dev_lv_matches
    local sel='-'; (( _dev_lv_sel >= 0 )) && sel=$(( _dev_lv_sel + 1 ))
    local left="<${sel}/${n}>" right="<History(${sel}/${n})>"
    local -i pad=$(( COLUMNS - ${#left} - ${#right} )); (( pad < 2 )) && pad=2
    local head="${left}${(l:pad:: :):-}${right}"
    local body=$'\n'$head
    local -i off=$(( $#BUFFER + 1 ))              # past the leading newline
    region_highlight+=( "$off $(( off + $#head )) ${_dev_lv_meta}" )
    (( off += $#head ))

    local q=${(V)_dev_lv_expect} row
    local -i i tstart tend qi
    for (( i = 1; i <= n; i++ )); do
      row=${(V)_dev_lv_matches[i]}
      (( ${#row} > COLUMNS - 3 )) && row="${row[1,COLUMNS-4]}…"
      body+=$'\n'"> $row"
      (( off += 1 ))                              # the newline
      region_highlight+=( "$off $(( off + 2 )) ${_dev_lv_meta}" )   # "> "
      (( off += 2 ))
      tstart=$off; tend=$(( off + ${#row} ))
      if (( i - 1 == _dev_lv_sel )); then
        region_highlight+=( "$tstart $tend ${_dev_lv_accent}" )
      elif [[ -n $q ]]; then
        qi=${row[(i)(#i)${(b)q}]}
        (( qi <= ${#row} )) &&
            region_highlight+=( "$(( tstart + qi - 1 )) $(( tstart + qi - 1 + ${#q} )) ${_dev_lv_accent}" )
      fi
      (( off = tend ))
    done
    POSTDISPLAY=$body
  }

  _dev_lv_down() {
    (( $#_dev_lv_matches )) || { zle .down-line-or-history; return }
    if (( _dev_lv_sel < $#_dev_lv_matches - 1 )); then
      (( _dev_lv_sel++ )); BUFFER=$_dev_lv_matches[_dev_lv_sel+1]; CURSOR=$#BUFFER
    else
      _dev_lv_sel=-1; BUFFER=$_dev_lv_orig; CURSOR=$_dev_lv_ocur
    fi
    _dev_lv_expect=$BUFFER
  }
  _dev_lv_up() {
    (( $#_dev_lv_matches )) || { zle .up-line-or-history; return }
    if (( _dev_lv_sel == 0 )); then
      _dev_lv_sel=-1; BUFFER=$_dev_lv_orig; CURSOR=$_dev_lv_ocur
    elif (( _dev_lv_sel > 0 )); then
      (( _dev_lv_sel-- )); BUFFER=$_dev_lv_matches[_dev_lv_sel+1]; CURSOR=$#BUFFER
    else
      _dev_lv_sel=$(( $#_dev_lv_matches - 1 )); BUFFER=$_dev_lv_matches[_dev_lv_sel+1]; CURSOR=$#BUFFER
    fi
    _dev_lv_expect=$BUFFER
  }
  _dev_lv_dismiss() {   # restore the typed line and hide the list
    if (( $#_dev_lv_matches )) && (( _dev_lv_sel != -1 )); then
      BUFFER=$_dev_lv_orig; CURSOR=$_dev_lv_ocur; _dev_lv_expect=$BUFFER
    fi
    _dev_lv_sel=-1; _dev_lv_hide
  }
  _dev_lv_finish() { _dev_lv_sel=-1; _dev_lv_off=0; _dev_lv_expect=$'\0'; _dev_lv_hide }

  # Tab opens the project menu: suspend the list (until the next edit) and hide
  # it first, so the list and the menu never draw at once.
  _dev_lv_complete() { _dev_lv_off=1; _dev_lv_hide; zle expand-or-complete }

  # Esc dismisses the list -- but arrows and other keys arrive as ESC-prefixed
  # sequences, so peek: a byte right after ESC means a sequence, which we
  # dispatch (arrows to the list, the rest to the matching line-editor widget);
  # a lone ESC dismisses. This keeps Esc instant without the KEYTIMEOUT wait a
  # bare ^[ binding would add to every arrow.
  _dev_lv_escape() {
    local c1 c2
    if read -k -t 0.03 c1; then
      if [[ $c1 == ('['|O) ]] && read -k -t 0.03 c2; then
        case $c2 in
          (A) zle _dev_lv_up;       return ;;
          (B) zle _dev_lv_down;     return ;;
          (C) zle .forward-char;    return ;;
          (D) zle .backward-char;   return ;;
          (H) zle .beginning-of-line; return ;;
          (F) zle .end-of-line;     return ;;
        esac
      fi
      return   # an ESC sequence we do not handle: swallow it, keep the list
    fi
    _dev_lv_dismiss
  }

  zle -N _dev_lv_down; zle -N _dev_lv_up; zle -N _dev_lv_escape; zle -N _dev_lv_complete
  add-zle-hook-widget line-pre-redraw _dev_lv_render
  add-zle-hook-widget line-finish _dev_lv_finish
fi

# Up/Down drive the history list, Esc dismisses it, Tab opens the project menu
# (suspending the list); both the normal and the application-mode arrow
# sequences are bound. DEV_SHELL_KEYS=0 leaves the keys at their zsh defaults
# (the list still shows, as a passive preview).
if [[ ${DEV_SHELL_UX:-1} == 1 && ${DEV_SHELL_KEYS:-1} == 1 ]]; then
  bindkey '^[[A' _dev_lv_up   '^[OA' _dev_lv_up
  bindkey '^[[B' _dev_lv_down '^[OB' _dev_lv_down
  bindkey '^[' _dev_lv_escape
  bindkey '^I' _dev_lv_complete
fi
