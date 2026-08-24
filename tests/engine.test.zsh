#!/usr/bin/env zsh
# dev-shell history-list ENGINE + RENDERER unit tests -- pure zsh, no pty.
# Sources the module and calls the engine/renderer functions directly, so the
# search, selection, and highlight-offset logic is proven without a terminal.
# Usage: zsh tests/engine.test.zsh   (exits non-zero on any failure)
emulate -L zsh
setopt extendedglob
local repo=${0:A:h:h}
autoload -Uz compinit; compinit -u -D 2>/dev/null
export DEV_ROOT=${TMPDIR:-/tmp}
source $repo/zsh/dev-shell.zsh

integer pass=0 fail=0
ok(){ (( ++pass )); return 0 }
bad(){ (( ++fail )); print -r -- "  FAIL: $1" }
eqi(){ (( $1 == $2 )) && ok || bad "$3: expected [$2] got [$1]" }
eqs(){ [[ $1 = $2 ]] && ok || bad "$3: expected [$2] got [$1]" }

# Controlled history from a file. fc -R drops the file's LAST line (zsh treats
# it as the line being entered), so a throwaway line is appended.
local hf=${TMPDIR:-/tmp}/dev-hl-engtest.$$
print -rl -- "aaa one" "aaa two" "bbb x" "aaa three" "xax mid" "zzz cmd" "_ignored_last" > $hf
HISTFILE=$hf HISTSIZE=200 SAVEHIST=200
fc -R $hf
trap "rm -f $hf" EXIT

# --- engine: search ---
_dev_hl_search aaa
eqi $#_dev_hl_matches 3          "aaa: 3 matches"
eqs $_dev_hl_matches[1] "aaa three" "aaa: newest first"
eqs $_dev_hl_matches[3] "aaa one"   "aaa: oldest last"
eqi $_dev_hl_sel -1             "aaa: sel starts at -1"

_dev_hl_search a
eqs $_dev_hl_matches[1] "aaa three" "a: prefix ranks before substring"
eqs $_dev_hl_matches[-1] "xax mid"  "a: substring last"
[[ " ${(j: :)_dev_hl_matches} " == *"xax mid"* ]] && ok || bad "a: substring present"

_dev_hl_search "aaa three"; eqi $#_dev_hl_matches 0 "query as long as a line -> nothing longer"
_dev_hl_search "";          eqi $#_dev_hl_matches 0 "empty query"
_dev_hl_search zzznope;     eqi $#_dev_hl_matches 0 "no match"

# a raw-escape history line renders visualized in matches[i] via (V); the match
# array keeps the raw value so it still runs.
print -rl -- $'\e[31m colour it \e[0m' "keep" > $hf; fc -R $hf
_dev_hl_search colour
[[ ${(V)_dev_hl_matches[1]} == *'^[[31m'* ]] && ok || bad "raw ESC visualized in display: ${(V)_dev_hl_matches[1]}"
[[ $_dev_hl_matches[1] == *$'\e[31m'* ]] && ok || bad "raw ESC kept in the match value"

# reload the aaa history for movement tests
print -rl -- "aaa one" "aaa two" "bbb x" "aaa three" "xax mid" "zzz cmd" "_last" > $hf; fc -R $hf

# --- engine: move (3 aaa matches; sel -1..2) ---
_dev_hl_search aaa
_dev_hl_move 1;  eqi $_dev_hl_sel 0  "+1 from query -> 0"
_dev_hl_move 1;  eqi $_dev_hl_sel 1  "+1 -> 1"
_dev_hl_move 1;  eqi $_dev_hl_sel 2  "+1 -> 2 (last)"
_dev_hl_move 1;  eqi $_dev_hl_sel -1 "+1 past last -> query"
_dev_hl_move -1; eqi $_dev_hl_sel 2  "-1 from query -> last (wrap)"
_dev_hl_move -1; eqi $_dev_hl_sel 1  "-1 -> 1"
_dev_hl_move 100;  (( _dev_hl_sel >= -1 && _dev_hl_sel < $#_dev_hl_matches )) && ok || bad "big +move in range: $_dev_hl_sel"
_dev_hl_move -100; (( _dev_hl_sel >= -1 && _dev_hl_sel < $#_dev_hl_matches )) && ok || bad "big -move in range: $_dev_hl_sel"

# --- renderer: offsets land on the right text ---
covers(){ local combined="$BUFFER$POSTDISPLAY"; print -r -- "${combined[$1+1,$2]}" }  # 1-based, end-exclusive
COLUMNS=60; BUFFER="pw"
_dev_hl_matches=( "pwd" "echo pwd" "compare pw x" ); _dev_hl_sel=-1; _dev_hl_top=0; _DEV_HL_VIS=10
_dev_hl_render "pw"
[[ $POSTDISPLAY == $'\n'"<-/3>"*"<History(-/3)>"* ]] && ok || bad "heading <-/3> spread"
integer rown=${#${(M)${(f)POSTDISPLAY}:#> *}}
eqi $rown 3 "3 rows drawn"
local -a accents=( ${(M)region_highlight:#* fg=214,bold} )
eqi $#accents 3 "one match highlight per row"
local e s en
for e in $accents; do s=${e%% *}; en=${${e#* }%% *}; [[ ${(L)"$(covers $s $en)"} == "pw" ]] && ok || bad "accent covers 'pw', got [$(covers $s $en)]" ; done
local -a markers=( ${(M)region_highlight:#* fg=244} )
integer mok=0
for e in ${markers[2,-1]}; do s=${e%% *}; en=${${e#* }%% *}; [[ "$(covers $s $en)" == "> " ]] && (( mok++ )); done
eqi $mok 3 "markers cover '> '"

_dev_hl_sel=1; _dev_hl_render "pw"       # select 'echo pwd'
accents=( ${(M)region_highlight:#* fg=214,bold} ); integer found=0
for e in $accents; do s=${e%% *}; en=${${e#* }%% *}; [[ "$(covers $s $en)" == "echo pwd" ]] && found=1; done
eqi $found 1 "selected row fully in accent"

# --- renderer: scroll window ---
_dev_hl_matches=( m{01..12} ); _DEV_HL_VIS=10; _dev_hl_sel=11; _dev_hl_top=2
_dev_hl_render "m"
rown=${#${(M)${(f)POSTDISPLAY}:#> *}}
eqi $rown 10 "window shows VIS rows"
[[ $POSTDISPLAY == *"> m12"* ]] && ok || bad "deep selection visible"
[[ $POSTDISPLAY != *"> m01"* ]] && ok || bad "scrolled-off row hidden"

# empty matches -> empty POSTDISPLAY, buffer highlights kept
BUFFER="hi"; region_highlight=( "0 1 fg=9" ); _dev_hl_matches=(); _dev_hl_render ""
[[ -z $POSTDISPLAY ]] && ok || bad "no matches -> empty POSTDISPLAY"
[[ " ${region_highlight} " == *"0 1 fg=9"* ]] && ok || bad "buffer highlight kept"

print -r -- "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
