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
# One completion menu style, used for both the project list and the options, so
# they read the same: a "LEFT  │ RIGHT" header over rows aligned to the widest
# left cell. Args are the two header words then (value label description)
# triples -- the value is inserted, the label shown in the left column. Note
# that zsh escapes control characters in display strings and list-colors match
# the completion VALUE not the display, so the description cannot be coloured;
# the │ rule and the coloured header carry that. -l lists one row each.
_dev_two_col() {
  emulate -L zsh
  local hl=$1 hr=$2; shift 2
  local -a vals=() labels=() descs=()
  while (( $# >= 3 )); do vals+=( "$1" ); labels+=( "$2" ); descs+=( "$3" ); shift 3; done
  (( $#vals )) || return 1
  integer width=${#hl} i
  for i in {1..$#labels}; do (( ${#labels[i]} > width )) && width=${#labels[i]}; done
  local -a displays=()
  for i in {1..$#vals}; do displays+=( "${(r:$width:)labels[i]}  │ ${descs[i]}" ); done
  compadd -Q -l -X "%F{81}%B${(r:$width:)hl}  │ ${hr}%b%f" -d displays -a vals
}

_dev_projects() {
  [[ -d $DEV_ROOT ]] || return 1
  local d name branch label
  local -a triples=()
  for d in $DEV_ROOT/*(/N); do
    name=${d:t}
    branch=$(_dev_branch "$d")
    [[ -n $branch ]] && label="on $branch" || label="no git repo"
    triples+=( "$name" "$name" "$label" )
  done
  (( $#triples )) || return 1
  _dev_two_col PROJECT BRANCH "$triples[@]"
}

# The options, styled like the project menu. The two long forms are listed;
# the short forms and the -e/--explorer aliases still complete but stay off the
# list (-n), so "-<Tab>" shows two clean rows without hiding any spelling.
_dev_options() {
  _dev_two_col OPTION DESCRIPTION \
    --code "-c, --code" "open the project in VS Code" \
    --open "-o, --open" "open in your file manager"
  compadd -n -- -c -o -e --explorer
}

_dev() {
  # An option word completes options; otherwise the project (once), then, with a
  # project already given, options -- matching dev()'s "options anywhere".
  if [[ $words[CURRENT] == -* ]]; then
    _dev_options
    return
  fi
  local w
  for w in ${words[2,CURRENT-1]}; do
    [[ $w != -* ]] && { _dev_options; return }
  done
  _dev_projects
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
  # Drawn and driven here, no plugin, in three layers so each stays simple and
  # testable: an ENGINE (search + selection, pure logic, unit-tested in plain
  # zsh), a RENDERER (state -> POSTDISPLAY + region_highlight), and a CONTROLLER
  # (the ZLE widgets and the redraw hook). The controller decides search vs keep
  # vs hide from WHICH widget fired -- never by comparing the buffer -- so
  # navigation and editing never race. Matching history shows as "> line" rows
  # under a live "<i/N>  <History(i/N)>" heading; the match and the selected row
  # take the accent, the marker and heading the metadata grey. Down/Up move the
  # selection and copy it onto the line; index -1 is the line you typed, so Up
  # from the first row restores it and its cursor -- PowerShell's original item.
  # Enter runs the line; Esc or an edit dismisses it. Matching is a
  # case-insensitive substring, prefix first, newest first, no duplicates or
  # lines no longer than the query; (V) shows control characters printable so a
  # history line's own escapes cannot repaint the list.

  # -- engine: state --
  typeset -ga _dev_hl_matches=()     # matching history lines
  typeset -gi _dev_hl_sel=-1         # selection: -1 = the typed line, 0.. a match
  typeset -gi _dev_hl_top=0          # first visible match (scroll window)
  typeset -gi _DEV_HL_MAX=10         # most matches kept (PowerShell's cap)
  typeset -gi _DEV_HL_VIS=10         # rows shown at once (== MAX unless scrolling)
  typeset -g  _dev_hl_query='' _dev_hl_accent="fg=${DEV_SHELL_ACCENT:-214},bold" _dev_hl_meta='fg=244'
  typeset -gi _dev_hl_qcursor=0 _dev_hl_off=0

  # -- engine: search & move (pure) --
  _dev_hl_search() {
    emulate -L zsh; setopt extendedglob
    local q=$1; _dev_hl_matches=(); _dev_hl_sel=-1; _dev_hl_top=0
    [[ -z $q ]] && return
    local -a nums=( ${(On)${(k)history[(R)(#i)*${(b)q}*]}} )
    local -A seen; local n cmd; local -a pre=() rest=()
    for n in $nums; do
      cmd=$history[$n]
      [[ $cmd == *$'\n'* ]] && continue
      (( ${#cmd} <= ${#q} )) && continue
      (( $+seen[$cmd] )) && continue
      seen[$cmd]=1
      if [[ $cmd == (#i)${(b)q}* ]]; then pre+=( "$cmd" ); else rest+=( "$cmd" ); fi
      (( $#pre >= _DEV_HL_MAX && $#rest >= _DEV_HL_MAX )) && break
    done
    _dev_hl_matches=( "${(@)pre}" "${(@)rest}" )
    (( $#_dev_hl_matches > _DEV_HL_MAX )) && _dev_hl_matches=( "${(@)_dev_hl_matches[1,_DEV_HL_MAX]}" )
  }
  _dev_hl_move() {
    local -i d=$1 n=$#_dev_hl_matches
    (( n == 0 )) && return
    local -i v=$(( _dev_hl_sel + 1 + d ))          # 0 = query, 1..n = matches
    (( v = (v % (n + 1) + (n + 1)) % (n + 1) ))    # wrap into 0..n
    _dev_hl_sel=$(( v - 1 ))
    if (( _dev_hl_sel < _dev_hl_top )); then _dev_hl_top=$_dev_hl_sel
    elif (( _dev_hl_sel >= _dev_hl_top + _DEV_HL_VIS )); then _dev_hl_top=$(( _dev_hl_sel - _DEV_HL_VIS + 1 )); fi
    (( _dev_hl_top < 0 )) && _dev_hl_top=0
  }

  # -- renderer (pure: state -> POSTDISPLAY + region_highlight) --
  # ZLE 5.8 strips the region_highlight `memo` tag, so clear the list's own
  # entries by offset -- they are the only ones at or past the buffer length --
  # and keep anything colouring the buffer (e.g. syntax highlighting).
  _dev_hl_clear_hl() {
    local -a keep=(); local e
    for e in $region_highlight; do (( ${e%% *} < $#BUFFER )) && keep+=( "$e" ); done
    region_highlight=( "${keep[@]}" )
  }
  _dev_hl_render() {
    emulate -L zsh; setopt extendedglob
    local q=$1
    _dev_hl_clear_hl
    if (( ! $#_dev_hl_matches )); then POSTDISPLAY=''; return; fi
    local -i n=$#_dev_hl_matches cols=${COLUMNS:-80}
    local disp='-'; (( _dev_hl_sel >= 0 )) && disp=$(( _dev_hl_sel + 1 ))
    local left="<${disp}/${n}>" right="<History(${disp}/${n})>"
    local -i pad=$(( cols - ${#left} - ${#right} )); (( pad < 2 )) && pad=2
    local head="${left}${(l:pad:: :):-}${right}"
    local body=$'\n'$head
    local -i off=$(( $#BUFFER + 1 ))               # after the leading newline
    region_highlight+=( "$off $(( off + $#head )) ${_dev_hl_meta}" )
    (( off += $#head ))
    local vq=${(V)q} row
    local -i lo=$(( _dev_hl_top + 1 )) hi=$(( _dev_hl_top + _DEV_HL_VIS ))
    (( hi > n )) && hi=$n
    local -i i tstart tend qi
    for (( i = lo; i <= hi; i++ )); do
      row=${(V)_dev_hl_matches[i]}
      (( ${#row} > cols - 3 )) && row="${row[1,cols-4]}…"
      body+=$'\n'"> $row"
      (( off += 1 ))                               # the newline
      region_highlight+=( "$off $(( off + 2 )) ${_dev_hl_meta}" )   # "> "
      (( off += 2 ))
      tstart=$off; tend=$(( off + ${#row} ))
      if (( i - 1 == _dev_hl_sel )); then
        region_highlight+=( "$tstart $tend ${_dev_hl_accent}" )
      elif [[ -n $vq ]]; then
        qi=${row[(i)(#i)${(b)vq}]}
        (( qi <= ${#row} )) &&
            region_highlight+=( "$(( tstart + qi - 1 )) $(( tstart + qi - 1 + ${#vq} )) ${_dev_hl_accent}" )
      fi
      (( off = tend ))
    done
    POSTDISPLAY=$body
  }

  # -- controller: which widgets mean edit / keep --
  typeset -ga _DEV_HL_EDIT=(
    self-insert backward-delete-char delete-char delete-char-or-list
    backward-kill-word kill-word backward-kill-line kill-line kill-whole-line
    yank yank-pop bracketed-paste
  )
  typeset -ga _DEV_HL_KEEP=(
    _dev_hl_down _dev_hl_up forward-char backward-char
    beginning-of-line end-of-line
  )

  _dev_hl_hide() { _dev_hl_matches=(); _dev_hl_sel=-1; POSTDISPLAY=''; _dev_hl_clear_hl }

  # The redraw hook: an edit re-searches from the buffer, the list's own
  # navigation and cursor moves just redraw, everything else hides. Tab suspends
  # the list (so the project menu owns the screen) until the next edit.
  _dev_hl_hook() {
    emulate -L zsh
    local lw=${LASTWIDGET#.}
    if (( _dev_hl_off )); then
      if (( ${_DEV_HL_EDIT[(Ie)$lw]} )); then _dev_hl_off=0
      else _dev_hl_hide; return; fi
    fi
    if [[ -z $LASTWIDGET ]] || (( ${_DEV_HL_EDIT[(Ie)$lw]} )); then
      _dev_hl_query=$BUFFER; _dev_hl_qcursor=$CURSOR
      _dev_hl_search "$BUFFER"; _dev_hl_render "$BUFFER"
    elif (( ${_DEV_HL_KEEP[(Ie)$lw]} )); then
      _dev_hl_render "$_dev_hl_query"
    else
      _dev_hl_hide
    fi
  }
  _dev_hl_finish() { _dev_hl_off=0; _dev_hl_query=''; _dev_hl_hide }

  # -- controller: key widgets --
  _dev_hl_down() {
    (( $#_dev_hl_matches )) || { zle .down-line-or-history; return }
    _dev_hl_move 1
    if (( _dev_hl_sel < 0 )); then BUFFER=$_dev_hl_query; CURSOR=$_dev_hl_qcursor
    else BUFFER=$_dev_hl_matches[_dev_hl_sel+1]; CURSOR=$#BUFFER; fi
  }
  _dev_hl_up() {
    (( $#_dev_hl_matches )) || { zle .up-line-or-history; return }
    _dev_hl_move -1
    if (( _dev_hl_sel < 0 )); then BUFFER=$_dev_hl_query; CURSOR=$_dev_hl_qcursor
    else BUFFER=$_dev_hl_matches[_dev_hl_sel+1]; CURSOR=$#BUFFER; fi
  }
  _dev_hl_dismiss() {   # restore the typed line and hide
    if (( $#_dev_hl_matches )) && (( _dev_hl_sel != -1 )); then
      BUFFER=$_dev_hl_query; CURSOR=$_dev_hl_qcursor
    fi
    _dev_hl_hide
  }
  _dev_hl_tab() { _dev_hl_off=1; _dev_hl_hide; zle expand-or-complete }

  # Esc dismisses -- but arrows and other keys arrive as ESC-prefixed sequences,
  # so peek: a byte right after ESC means a sequence, which we dispatch (arrows
  # to the list, the rest to the matching line editor); a lone ESC dismisses.
  # This keeps Esc instant without the KEYTIMEOUT wait a bare ^[ would add.
  _dev_hl_escape() {
    local c1 c2
    if read -k -t 0.03 c1; then
      if [[ $c1 == ('['|O) ]] && read -k -t 0.03 c2; then
        case $c2 in
          (A) zle _dev_hl_up;         return ;;
          (B) zle _dev_hl_down;       return ;;
          (C) zle .forward-char;      return ;;
          (D) zle .backward-char;     return ;;
          (H) zle .beginning-of-line; return ;;
          (F) zle .end-of-line;       return ;;
        esac
      fi
      return
    fi
    _dev_hl_dismiss
  }

  zle -N _dev_hl_down; zle -N _dev_hl_up; zle -N _dev_hl_escape; zle -N _dev_hl_tab
  add-zle-hook-widget line-pre-redraw _dev_hl_hook
  add-zle-hook-widget line-finish _dev_hl_finish
fi

# Up/Down drive the history list, Esc dismisses it, Tab opens the project menu
# (suspending the list); both the normal and the application-mode arrow
# sequences are bound. DEV_SHELL_KEYS=0 leaves the keys at their zsh defaults.
if [[ ${DEV_SHELL_UX:-1} == 1 && ${DEV_SHELL_KEYS:-1} == 1 ]]; then
  bindkey '^[[A' _dev_hl_up   '^[OA' _dev_hl_up
  bindkey '^[[B' _dev_hl_down '^[OB' _dev_hl_down
  bindkey '^[' _dev_hl_escape
  bindkey '^I' _dev_hl_tab
fi
