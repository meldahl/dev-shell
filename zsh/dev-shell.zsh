# dev-shell — project navigation and completion polish for zsh.
#
# Source this from ~/.zshrc:
#     source /path/to/dev-shell/zsh/dev-shell.zsh
#
# Optional configuration, set BEFORE sourcing:
#   DEV_ROOT                directory holding your projects  (default: $HOME/dev)
#   DEV_SHELL_UX            0 to skip the completion styling and the history list
#                           (keeps just the command)
#   DEV_SHELL_KEYS          0 to skip the Up/Down history keybindings
#   DEV_SHELL_ACCENT        256-colour index for the selected item  (default: 214)
#   DEV_SHELL_CONTINUATION  continuation prompt, i.e. PS2  (default: "%_❯❯ " -- %_ names
#                           the open construct, e.g. dquote, as zsh's own default does)
#
# Source it AFTER your plugins. The history list as you type needs
# zsh-autocomplete (marlonrichert), ghost-text suggestions need
# zsh-autosuggestions; without zsh-autocomplete, Up/Down fall back to
# history-substring-search when that is loaded. Everything is guarded, so a
# missing plugin only means the feature is absent.

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
# zsh-autocomplete registers the ~autocomplete named directory when it loads
# (its README uses it as the plugin's handle), so that is the detection.
_dev_has_autocomplete() { (( ${+nameddirs[autocomplete]} )) }

if [[ ${DEV_SHELL_UX:-1} == 1 ]]; then
  # Label each completion group so the list has a heading.
  zstyle ':completion:*' group-name ''
  zstyle ':completion:*:descriptions' format '%F{81}%B%d%b%f'

  # 'ma' recolours the selected entry instead of filling a background box,
  # which would otherwise run into the next column. The accent (amber by
  # default) keeps it clear of the cyan header and the default light-blue text.
  zmodload -i zsh/complist
  zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}" "ma=1;38;5;${DEV_SHELL_ACCENT:-214}"

  if _dev_has_autocomplete; then
    # History list as you type, PSReadLine's ListView: every line starts in
    # history mode, 10 rows, from the first character, no duplicates
    # (hist_find_no_dups is the switch the plugin honours), no ';' appended to
    # a picked line. Ctrl-R switches the line to live completions instead.
    zstyle ':autocomplete:*' default-context history-incremental-search-backward
    zstyle ':autocomplete:history-incremental-search-backward:*' list-lines 10
    zstyle ':autocomplete:*' min-input 1
    zstyle ':autocomplete:*' add-semicolon no
    setopt hist_find_no_dups

    # The list itself comes from the plugin's history completer, which fixes
    # its own look and matching: event numbers, black-on-yellow matches, a
    # fuzzy query, no heading. dev-shell owns that function instead -- forked
    # from zsh-autocomplete 027cdab (Completions/_autocomplete__history_lines)
    # and reshaped to PSReadLine's ListView: "> line ... [History]" rows under
    # a "<-/N>   <History(N)>" heading, the input matched as a substring with
    # prefix matches first, newest first, no duplicates, no multi-line
    # commands, match and selected row in the accent. Up from the first row
    # returns to the typed line (PSReadLine's virtual item) -- done at the
    # menuselect layer below, not as a listed match. zsh can only replace the
    # word at the cursor, so the words around it stay as typed (lbuffer/
    # rbuffer below). Defined at the first precmd, after the
    # plugin's compinit has declared the original for autoloading; re-check
    # when the plugin updates.
    _dev_define_history_lines() {
      add-zsh-hook -d precmd _dev_define_history_lines
      _autocomplete__history_lines() {
        setopt localoptions multibyte extendedglob
        (( _matcher_num > 1 )) && return 1

        local -a before=( "${(@b)words[1,CURRENT-1]}" ) after=( "${(@b)words[CURRENT+1,-1]}" )
        local lbuffer='' rbuffer='' input=$words[CURRENT]
        (( $#before )) && lbuffer="${(j.[[:blank:]]##.)before}[[:blank:]]##"
        (( $#after ))  && rbuffer="[[:blank:]]##${(j.[[:blank:]]##.)after}"
        lbuffer="$lbuffer${(b)QIPREFIX}"; rbuffer="${(b)QISUFFIX}$rbuffer"
        local pat="${lbuffer}*${rbuffer}"
        [[ -n $input ]] && pat="${lbuffer}(#i)*${(b)input}*${rbuffer}"

        local -i incremental=0 max=10
        [[ $curcontext == *-incremental-* ]] && incremental=1
        if (( incremental )); then
          zstyle -s ':autocomplete:history-incremental-search-backward:' list-lines max || max=10
        else
          zle -R 'Loading...'
          zstyle -s ":autocomplete:${curcontext}:" list-lines max || (( max = LINES / 2 ))
        fi

        # Newest first; prefix matches rank before the rest (PSReadLine).
        local -a nums=( ${(On)${(k)history[(R)${~pat}]}} ) prefixed others plines olines
        local -A seen
        local n cmd segment
        for n in $nums; do
          cmd=$history[$n]
          [[ $cmd == *$'\n'* ]] && continue
          segment=${${cmd##$~lbuffer}%%$~rbuffer}
          [[ -n $input && $segment == (#i)${(b)input} ]] && continue
          (( $+seen[$segment] )) && continue
          seen[$segment]=1
          if [[ -n $input && $segment == (#i)${(b)input}* ]]; then
            prefixed+=( "$segment" ); plines+=( "$cmd" )
            (( $#prefixed >= max )) && break
          else
            others+=( "$segment" ); olines+=( "$cmd" )
          fi
        done
        # Slice under quotes with (@) yields one empty word on an empty array,
        # so guard each append on a non-empty source.
        local -a matches=() lines=()
        (( $#prefixed )) && matches=( "${(@)prefixed[1,max]}" ) lines=( "${(@)plines[1,max]}" )
        local -i room=$(( max - $#matches ))
        (( room > 0 && $#others )) && matches+=( "${(@)others[1,room]}" ) lines+=( "${(@)olines[1,room]}" )
        (( $#matches )) || return 1

        # Rows: "> text", the text cut with an ellipsis, "[History]" flush right.
        local tag='[History]' text
        local -i width=$(( COLUMNS - 1 )) textw=0
        (( textw = width - 3 - $#tag ))
        local -a displays
        for text in "${(@)lines}"; do
          (( $#text > textw )) && text="${text[1,textw-1]}…"
          displays+=( "> ${text}${(l:textw-$#text:: :):-} ${tag}" )
        done

        # Colours: the marker and the tag in the metadata grey, the first
        # occurrence of the input in the accent, the selected row in the
        # accent (unprefixed ma=, which a tagged group's _setup never yields).
        local accent="1;38;5;${DEV_SHELL_ACCENT:-214}" meta='38;5;244' w=${(b)input}
        _comp_colors=( "=(#b)(> )*( \[History\])=0=${meta}=${meta}" "ma=${accent}" )
        if [[ -n $input && $input != *[:=]* ]]; then
          _comp_colors=( "=(#b)(> )((^*(#i)${w}*))((#i)${w})(*)( \[History\])=0=${meta}=0=${accent}=0=${meta}" "$_comp_colors[@]" )
        fi

        # The heading counts the real matches. It is drawn once, so it cannot
        # track the selection the way PSReadLine's live <i/N> does.
        local -i n=$#matches
        local head="<-/${n}>" src="<History(${n})>"
        local esc=$'\e'
        local heading="%{${esc}[${meta};3m%}${head}${(l:width-$#head-$#src:: :):-}${src}%{${esc}[0m%}"

        # The typed line as a last, dim row with no tag: menu selection wraps
        # first<->last, so Up from the first match lands here and restores it,
        # PSReadLine's virtual original item. Only with something typed -- an
        # empty query (the Up history menu on a blank line) has nothing to
        # return to.
        if [[ -n $input ]]; then
          matches+=( "$input" ); text=$input
          (( $#text > textw )) && text="${text[1,textw-1]}…"
          displays+=( "> ${text}" )
        fi

        local -a expl
        _description -2V history-lines expl ''
        builtin compadd -QU -S '' -X "$heading" -ld displays "$expl[@]" -a matches
      }
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _dev_define_history_lines

    # The plugin records recent directories (cdr) under
    # ${XDG_DATA_HOME:-~/.local/share}/zsh but never creates that directory, so
    # every cd would complain; create it unless cdr was pointed elsewhere.
    zstyle -m ':chpwd:' recent-dirs-file '*' || mkdir -p -- "${XDG_DATA_HOME:-$HOME/.local/share}/zsh"

    # Enter inside a menu. menuselect cannot hand Enter to a widget of ours (it
    # leaves the menu and re-dispatches the key), so the widget that opens a
    # menu decides: a history list runs the line, as PSReadLine does
    # (.accept-line, re-dispatched); a completion menu only accepts the entry
    # (accept-line's menuselect meaning). The list a line shows is history
    # unless Ctrl-R toggled it, which the plugin records in curcontext.
    _dev_menu_enter() { # run | accept
      local widget=accept-line
      [[ $1 == run ]] && widget=.accept-line
      bindkey -M menuselect '^M' $widget
    }
    _dev_list_is_history() { [[ $curcontext == history-incremental-search* ]] }
    _dev_menu_enter accept
    # Esc leaves a list and restores the line, as PSReadLine's Esc dismisses
    # its list. Arrow sequences still reach the menu: they arrive whole.
    bindkey -M menuselect '^[' send-break

    # Tab still opens the project menu. The plugin would menu-select whatever
    # list is already on screen -- the history list -- so list the plain
    # completions first (curcontext is compsys's context variable; empty means
    # the widget's own) and menu-select those.
    _dev_menu_complete() {
      _dev_menu_enter accept
      local curcontext=
      zle list-choices
      zle menu-select -w
    }
    zle -N _dev_menu_complete
    bindkey '^I' _dev_menu_complete

    # Down enters the list on screen, Up opens the history menu.
    _dev_list_select() {
      if _dev_list_is_history; then _dev_menu_enter run; else _dev_menu_enter accept; fi
      zle down-line-or-select -w
    }
    _dev_history_menu() {
      _dev_menu_enter run
      zle up-line-or-search -w
    }
    zle -N _dev_list_select
    zle -N _dev_history_menu
  else
    # Arrow-navigable menu on Tab.
    zstyle ':completion:*' menu select
  fi

  # Continuation prompt, matching the PowerShell side; %_ keeps zsh's hint of
  # which construct is still open (dquote, then, ...), which PS2 shows by default.
  PS2=${DEV_SHELL_CONTINUATION-'%_❯❯ '}

  # Ghost-text suggestions from history (requires the zsh-autosuggestions
  # plugin; harmless if it is not installed).
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=244'
fi

# Up/Down: the history menu and the list with zsh-autocomplete, otherwise
# search history by what is already typed (history-substring-search). Both the
# normal and the application-mode sequences are bound, so plugin order cannot
# decide who wins.
if [[ ${DEV_SHELL_KEYS:-1} == 1 ]]; then
  if _dev_has_autocomplete && [[ ${DEV_SHELL_UX:-1} == 1 ]]; then
    bindkey '^[[A' _dev_history_menu '^[OA' _dev_history_menu
    bindkey '^[[B' _dev_list_select  '^[OB' _dev_list_select
  elif _dev_has_autocomplete; then
    bindkey '^[[A' up-line-or-search   '^[OA' up-line-or-search
    bindkey '^[[B' down-line-or-select '^[OB' down-line-or-select
  elif (( $+functions[history-substring-search-up] )); then
    bindkey '^[[A' history-substring-search-up   '^[OA' history-substring-search-up
    bindkey '^[[B' history-substring-search-down '^[OB' history-substring-search-down
  fi
fi
