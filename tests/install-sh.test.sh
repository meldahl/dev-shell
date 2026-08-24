#!/usr/bin/env bash
# dev-shell zsh suite: the installer headless and at a pty, the module under
# zsh, the opener with stubbed tools, --uninstall, the history-list UX (pty, via
# tests/zsh-ux.probe.py -- the list needs no plugin), and the installer's
# zsh-autosuggestions handling with a stubbed git. Needs bash, zsh, python3,
# script(1), git. zsh-autosuggestions is taken from ~/.oh-my-zsh/custom (SUG=
# overrides) and, when present, sourced so the probe checks the ListView
# suppresses its ghost. Scratch is a mktemp directory, removed when everything
# passes and kept, with its path printed, when something fails. Exits non-zero
# on failure.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; INST=$REPO/install.sh; MOD=$REPO/zsh/dev-shell.zsh
REAL_HOME=$HOME; S="$(mktemp -d "${TMPDIR:-/tmp}/devshell-zsh.XXXXXX")"
trap '[ "${fail:-1}" = 0 ] && rm -rf "$S" || echo "scratch kept: $S"' EXIT
mkdir -p $S/shtest/home/dev/proj; export HOME=$S/shtest/home; unset DEV_ROOT ZDOTDIR ZSH
pass=0; fail=0; ok(){ printf '  PASS: %s\n' "$1"; pass=$((pass+1)); }; bad(){ printf '  FAIL: %s\n' "$1"; fail=$((fail+1)); }
blk(){ awk '/^# >>> dev-shell >>>$/{b=1} b{print} /^# <<< dev-shell <<<$/{b=0}' "$HOME/.zshrc"; }
val(){ blk | sed -nE "s/^(export )?$1=//p"; }
expect(){ local got; got=$(val "$1"); [ "$got" = "$2" ] && ok "$1=$2" || bad "$1: expected [$2] got [$got]"; }
pty(){ local input=$1; shift; printf "$input" | script -qfec "$INST $*" /dev/null 2>&1 | tr -d '\r'; }
printf '# my zshrc\nexport FOO=1\n' > "$HOME/.zshrc"
echo "### B1 headless fresh, no env/flag -> rc1, untouched"; cp "$HOME/.zshrc" $S/b1; out=$("$INST" </dev/null 2>&1); rc=$?; [ $rc = 1 ] && ok "rc=1" || bad "rc=$rc"; cmp -s "$HOME/.zshrc" $S/b1 && ok "untouched" || bad "changed"; printf '%s' "$out" | grep -q 'no terminal' && ok "message" || bad "message"
echo "### B2 headless --dev-root /p1 -> block with all defaults"; out=$("$INST" --dev-root /p1 </dev/null 2>&1); [ $? = 0 ] && ok "rc=0" || { bad "rc"; printf '%s\n' "$out"; }
expect DEV_ROOT '"/p1"'; expect DEV_SHELL_UX 1; expect DEV_SHELL_KEYS 1; expect DEV_SHELL_ACCENT 214; expect DEV_SHELL_CONTINUATION '"%_❯❯ "'
blk | grep -qFx "source \"$REPO/zsh/dev-shell.zsh\"" && ok "source line" || { bad "source line"; blk; }
echo "### B3 headless re-run, no args -> allowed via block, updated"; out=$("$INST" </dev/null 2>&1); [ $? = 0 ] && ok "rc=0" || { bad "rc"; printf '%s\n' "$out"; }; printf '%s' "$out" | grep -q 'updated dev-shell block' && ok "updated" || bad "updated"; expect DEV_ROOT '"/p1"'; [ "$(grep -cFx '# >>> dev-shell >>>' "$HOME/.zshrc")" = 1 ] && ok "1 marker" || bad "markers"
echo "### B4 look flags with nasty continuation, then round-trip"; out=$("$INST" --accent 39 --continuation 'a"b$c\d`e' --ux off --keys no </dev/null 2>&1); [ $? = 0 ] && ok "rc=0" || { bad "rc"; printf '%s\n' "$out"; }
expect DEV_SHELL_ACCENT 39; expect DEV_SHELL_UX 0; expect DEV_SHELL_KEYS 0; expect DEV_SHELL_CONTINUATION '"a\"b\$c\\d\`e"'; expect DEV_ROOT '"/p1"'
"$INST" --dev-root /p2 </dev/null >/dev/null 2>&1; expect DEV_ROOT '"/p2"'; expect DEV_SHELL_ACCENT 39; expect DEV_SHELL_UX 0; expect DEV_SHELL_KEYS 0; expect DEV_SHELL_CONTINUATION '"a\"b\$c\\d\`e"'
got=$(zsh -c "$(blk | grep -E '^(export )?DEV_'); print -r -- \$DEV_SHELL_CONTINUATION"); [ "$got" = 'a"b$c\d`e' ] && ok "zsh evaluates continuation back to original" || bad "zsh eval: [$got]"
echo "### B5 flag validation"; for a in "--accent 300" "--ux maybe" "--accent" "--bogus"; do "$INST" $a </dev/null >/dev/null 2>&1; [ $? = 2 ] && ok "rc=2 for $a" || bad "rc for $a"; done
echo "### B6 pty: Enter, Enter (gate=n) -> preview shown, nothing changed"; out=$(pty '\n\n'); printf '%s' "$out" | grep -q 'This is how it looks now:' && ok "preview heading" || bad "preview heading"; printf '%s' "$out" | grep -q 'PROJECT        │ BRANCH' && printf '%s' "$out" | grep -q 'website' && ok "sample rows" || bad "sample rows"; printf '%s' "$out" | grep -q 'Customize the look' && ok "gate asked" || bad "gate"; expect DEV_SHELL_ACCENT 39; expect DEV_ROOT '"/p2"'
echo "### B7 pty: customize y, styling y, '>> ', 300 (bad), 99, keys n, keep Enter"; out=$(pty '\ny\ny\n>> \n300\n99\nn\n\n'); printf '%s' "$out" | grep -q 'please give a number 0-255' && ok "accent re-prompt" || bad "accent re-prompt"; printf '%s' "$out" | grep -q 'With those settings:' && ok "second preview" || bad "second preview"; printf '%s' "$out" | grep -q 'Keep these?' && ok "keep asked" || bad "keep"
expect DEV_SHELL_UX 1; expect DEV_SHELL_CONTINUATION '">> "'; expect DEV_SHELL_ACCENT 99; expect DEV_SHELL_KEYS 0
echo "### B8 pty: customize y, styling n -> no continuation/accent questions; keys Enter keeps 0; keep Enter"; out=$(pty '\ny\nn\n\n\n'); printf '%s' "$out" | grep -q 'Accent colour' && bad "accent asked despite styling off" || ok "accent not asked"; printf '%s' "$out" | grep -q 'styling off' && ok "off-preview note" || bad "off-preview"; expect DEV_SHELL_UX 0; expect DEV_SHELL_KEYS 0; expect DEV_SHELL_ACCENT 99
echo "### B9 pty with --accent 5 -> root asked, gate skipped"; out=$(pty '\n' --accent 5); printf '%s' "$out" | grep -q 'Projects directory \[/p2\]' && ok "root prompt with block default" || bad "root prompt: $(printf '%s' "$out" | grep -m1 Projects)"; printf '%s' "$out" | grep -q 'Customize the look' && bad "gate asked" || ok "gate skipped"; expect DEV_SHELL_ACCENT 5
echo "### B10 START without END -> error, untouched"; cp "$HOME/.zshrc" $S/b10; sed -i '/^# <<< dev-shell <<</d' "$HOME/.zshrc"; cp "$HOME/.zshrc" $S/b10b; "$INST" --dev-root /x </dev/null >/dev/null 2>&1; [ $? = 1 ] && ok "rc=1" || bad "rc"; cmp -s "$HOME/.zshrc" $S/b10b && ok "untouched" || bad "changed"; cp $S/b10 "$HOME/.zshrc"
echo "### B11 module under zsh with final settings"; "$INST" --ux on --continuation '>> ' --accent 7 </dev/null >/dev/null 2>&1
zsh -n "$HOME/.zshrc" && ok "zsh -n" || bad "zsh -n"
res=$(zsh -c 'autoload -Uz compinit; compinit -u -D; source ~/.zshrc 2>&1; print "root=$DEV_ROOT"; print -r -- "ps2=$PS2"; print "ma=$(zstyle -L ":completion:*" list-colors | grep -o "ma=1;38;5;[0-9]*")"; dev --help | grep -q -- "-o, --open" && print "help=ok"; dev --bogus 2>&1 | grep -q "unknown option" && print "bogus=ok"' 2>&1); printf '%s\n' "$res"
printf '%s' "$res" | grep -q '^root=/p2$' && ok "DEV_ROOT" || bad "DEV_ROOT"; printf '%s' "$res" | grep -q '^ps2=>> $' && ok "PS2 = continuation" || bad "PS2"; d=$(zsh -c "autoload -Uz compinit; compinit -u -D; source $MOD; print -r -- \"\$PS2\""); [ "$d" = '%_❯❯ ' ] && ok "module PS2 default = %_❯❯ " || bad "module PS2 default: [$d]"; printf '%s' "$res" | grep -q 'ma=1;38;5;7' && ok "accent in list-colors" || bad "accent"; printf '%s' "$res" | grep -q 'help=ok' && ok "help mentions -o" || bad "help"
echo "### B12 opener with stubbed tools"; ST=$S/shtest/stubs; mkdir -p $ST; LOG=$S/shtest/oplog
for t in explorer.exe open xdg-open code; do printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> %s\n' "$t" "$LOG" > $ST/$t; chmod +x $ST/$t; done; printf '#!/bin/sh\nprintf "%%s\\n" "W:\\\\fake\\\\$(basename "$2")"\n' > $ST/wslpath; chmod +x $ST/wslpath
zopen(){ # $1 = env prelude, $2 = dev args
  : > $LOG; zsh -c "autoload -Uz compinit; compinit -u -D; $1; export DEV_ROOT=$HOME/dev; PATH=$ST:\$PATH; source $MOD; dev $2; print rc=\$?" 2>&1 | tr -d '\r'; echo "log: $(cat $LOG)"; }
r=$(zopen "export WSL_DISTRO_NAME=Ubuntu" "-o proj"); printf '%s' "$r" | grep -q 'log: explorer.exe W:\\fake\\proj' && printf '%s' "$r" | grep -q 'rc=0' && ok "WSL -> explorer.exe via wslpath" || { bad "WSL"; echo "$r"; }
r=$(zopen "unset WSL_DISTRO_NAME; OSTYPE=darwin22" "-e proj"); printf '%s' "$r" | grep -q "log: open $HOME/dev/proj" && ok "macOS -> open (via -e alias)" || { bad "macOS"; echo "$r"; }
r=$(zopen "unset WSL_DISTRO_NAME; OSTYPE=linux-gnu" "--open proj"); printf '%s' "$r" | grep -q "log: xdg-open $HOME/dev/proj" && ok "Linux -> xdg-open" || { bad "Linux"; echo "$r"; }
r=$(zopen "unset WSL_DISTRO_NAME; OSTYPE=linux-gnu; rm -f $ST/xdg-open" "--explorer proj"); printf '%s' "$r" | grep -q 'no file manager opener found' && printf '%s' "$r" | grep -q 'rc=1' && ok "no opener -> error rc1" || { bad "no opener"; echo "$r"; }
r=$(zopen "" "-c proj"); printf '%s' "$r" | grep -q "log: code $HOME/dev/proj" && ok "-c -> code" || { bad "code"; echo "$r"; }
r=$(zopen "" "proj -c"); printf '%s' "$r" | grep -q "log: code $HOME/dev/proj" && printf '%s' "$r" | grep -q 'rc=0' && ok "trailing flag: proj -c -> code (no cd)" || { bad "trailing -c"; echo "$r"; }
r=$(zopen "unset WSL_DISTRO_NAME; OSTYPE=darwin22" "proj --open"); printf '%s' "$r" | grep -q "log: open $HOME/dev/proj" && ok "trailing flag: proj --open -> open" || { bad "trailing --open"; echo "$r"; }
r=$(zopen "" "proj -x"); printf '%s' "$r" | grep -q 'unknown option: -x' && printf '%s' "$r" | grep -q 'rc=1' && ok "unknown trailing option -> error rc1" || { bad "unknown trailing option"; echo "$r"; }
r=$(zopen "" "proj other"); printf '%s' "$r" | grep -q 'one project at a time' && printf '%s' "$r" | grep -q 'rc=1' && ok "two projects -> error rc1" || { bad "two projects"; echo "$r"; }
r=$(zopen "" "--help"); printf '%s' "$r" | grep -q 'usage: dev \[project\]' && ok "--help shows options-anywhere usage" || { bad "help usage"; echo "$r"; }
echo "### B13 --uninstall"
out=$("$INST" --uninstall </dev/null 2>&1); rc=$?; [ $rc = 0 ] && ok "rc=0" || bad "rc=$rc"; printf '%s' "$out" | grep -q 'removed the dev-shell block' && ok "message" || { bad "message"; printf '%s\n' "$out"; }
[ "$(cat "$HOME/.zshrc")" = "$(printf '# my zshrc\nexport FOO=1')" ] && ok "zshrc back to the original (blank above the block gone)" || { bad "content:"; cat -A "$HOME/.zshrc"; }
"$INST" --uninstall </dev/null 2>&1 | grep -q 'nothing to remove' && ok "second --uninstall: nothing to remove" || bad "second uninstall"
printf 'a\n\n# >>> dev-shell >>>\nx\n# <<< dev-shell <<<\nb\n\nc\n' > "$HOME/.zshrc"; "$INST" --uninstall </dev/null >/dev/null 2>&1; [ "$(cat "$HOME/.zshrc")" = "$(printf 'a\nb\n\nc')" ] && ok "middle block removed with its blank; other blanks kept" || { bad "middle:"; cat -A "$HOME/.zshrc"; }
printf 'a\n# >>> dev-shell >>>\nx\n' > "$HOME/.zshrc"; out=$("$INST" --uninstall </dev/null 2>&1); rc=$?; [ $rc = 1 ] && printf '%s' "$out" | grep -q 'by hand' && ok "no END -> rc1 + manual steps" || { bad "no END (rc=$rc)"; printf '%s\n' "$out"; }; [ "$(cat "$HOME/.zshrc")" = "$(printf 'a\n# >>> dev-shell >>>\nx')" ] && ok "untouched" || bad "changed"
echo "### B14 history-list UX, keys on (pty)"; SUG=${SUG:-$REAL_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions}
uxhome(){ # $1 dir, $2 keys(1|0) -> a HOME for tests/zsh-ux.probe.py (no plugin)
  rm -rf "$1"; mkdir -p "$1/dev/api" "$1/dev/web" "$1/bin"; git -C "$1/dev/web" init -q -b feat/x
  printf '#!/bin/sh\necho CODE-RAN\n' > "$1/bin/code"; chmod +x "$1/bin/code"   # a history line runs 'dev api -c'; a marker, never the real editor
  printf ': 1700000001:0;dev reader\n: 1700000002:0;dev api -c\n: 1700000003:0;pwd\n: 1700000004:0;echo pwd\n: 1700000005:0;git status\n: 1700000006:0;dev web\n: 1700000007:0;pwd\n' > "$1/.zsh_history"
  printf ': 1700000008:0;\x1b[31m esc-color line \x1b[0m\n' >> "$1/.zsh_history"   # a raw ANSI escape must not repaint the list
  { echo 'PROMPT="PS> "; HISTFILE=$HOME/.zsh_history; HISTSIZE=1000; SAVEHIST=0; setopt extendedglob; path=($HOME/bin $path)'
    echo 'autoload -Uz compinit; compinit -u -D'
    [ -d "$SUG" ] && echo "source $SUG/zsh-autosuggestions.zsh"   # the ListView must suppress its ghost
    echo "export DEV_ROOT=$1/dev DEV_SHELL_ACCENT=214 DEV_SHELL_KEYS=$2"; echo "source $MOD"; } > "$1/.zshrc"; }
uxprobe(){ # $1 dir, $2 mode: run the probe, fold its PASS/FAIL lines into the totals
  local out; out=$(python3 "$REPO/tests/zsh-ux.probe.py" "$1" "$2" 2>&1); printf '%s\n' "$out" | grep -E '^  (PASS|FAIL)|^    \|'
  pass=$((pass + $(printf '%s\n' "$out" | grep -c '^  PASS'))); fail=$((fail + $(printf '%s\n' "$out" | grep -c '^  FAIL'))); }
uxhome $S/shtest/ux-full 1; uxprobe $S/shtest/ux-full full
echo "### B15 history-list UX, keys off (list shows, keys stay zsh defaults)"; uxhome $S/shtest/ux-nokeys 0; uxprobe $S/shtest/ux-nokeys nokeys
echo "### B16 installer enables zsh-autosuggestions (stub git)"
OH=$S/shtest/omzhome; rm -rf $OH; mkdir -p $OH/.oh-my-zsh/custom/plugins $OH/bin
cat > $OH/bin/git <<'EOF'
#!/bin/sh
echo "git $*" >> "$HOME/git.log"
[ "$1" = clone ] && mkdir -p "$(eval echo \${$#})"
exit 0
EOF
chmod +x $OH/bin/git; printf '# rc\nplugins=(git)\n' > $OH/.zshrc
HOME=$OH PATH=$OH/bin:$PATH "$INST" --dev-root /p </dev/null >/dev/null 2>&1
grep -qx 'plugins=(zsh-autosuggestions git)' $OH/.zshrc && ok "zsh-autosuggestions enabled (no other plugin added)" || { bad "plugins"; grep '^plugins' $OH/.zshrc; }
[ -d $OH/.oh-my-zsh/custom/plugins/zsh-autosuggestions ] && [ ! -d $OH/.oh-my-zsh/custom/plugins/zsh-autocomplete ] && ok "only zsh-autosuggestions cloned" || bad "clone dirs"
HOME=$OH PATH=$OH/bin:$PATH "$INST" --dev-root /p </dev/null >/dev/null 2>&1
[ "$(grep -c '^plugins=' $OH/.zshrc)" = 1 ] && grep -qx 'plugins=(zsh-autosuggestions git)' $OH/.zshrc && [ "$(grep -c clone $OH/git.log)" = 1 ] && ok "re-run: no duplicate entry, no re-clone" || bad "re-run"
printf '# rc\nplugins=(git)\n' > $OH/.zshrc; rm -rf $OH/.oh-my-zsh/custom/plugins/*
HOME=$OH PATH=$OH/bin:$PATH "$INST" --dev-root /p --ux off </dev/null >/dev/null 2>&1
grep -qx 'plugins=(zsh-autosuggestions git)' $OH/.zshrc && ok "ux off: still just zsh-autosuggestions" || { bad "ux off plugins"; grep '^plugins' $OH/.zshrc; }
echo; echo "RESULT: $pass passed, $fail failed"; [ "$fail" = 0 ]
