#!/usr/bin/env bash
# dev-shell PowerShell suite, run from WSL against the Windows PowerShells
# found on PATH (pwsh.exe 7, powershell.exe 5.1): the installer headless and
# prompted (a probe copy with the stdin guard removed, since WSL interop always
# reports redirected input), a $PROFILE override into scratch, -Uninstall, and
# module checks. Scratch is a mktemp directory under Windows %TEMP%, which both
# sides can see; removed when everything passes, kept with its path printed
# when something fails. Skipped with a note when no engine is reachable.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$REPO" || exit 1
engines=(); for e in pwsh.exe powershell.exe; do command -v "$e" >/dev/null 2>&1 && engines+=("$e"); done
if [ ${#engines[@]} = 0 ]; then echo "PowerShell suite skipped: no pwsh.exe/powershell.exe on PATH (run it from WSL)"; exit 0; fi
WTEMP=$("${engines[0]}" -NoProfile -Command '$env:TEMP' | tr -d '\r'); WHOME=$("${engines[0]}" -NoProfile -Command '$HOME' | tr -d '\r')
LBASE="$(mktemp -d "$(wslpath -u "$WTEMP")/devshell-ps.XXXXXX")"; WBASE="$(wslpath -w "$LBASE")"
trap '[ "${fail:-1}" = 0 ] && rm -rf "$LBASE" || echo "scratch kept: $LBASE"' EXIT
mkdir -p "$LBASE/powershell"; cp install.ps1 "$LBASE/install.ps1"; cp powershell/dev-shell.ps1 "$LBASE/powershell/dev-shell.ps1"
sed '/if (\[Console\]::IsInputRedirected) { return \$null }/d' install.ps1 > "$LBASE/install.probe.ps1"
sed -i 's/if (-not \$lookGiven -and -not \[Console\]::IsInputRedirected) {/if (-not $lookGiven) {/' "$LBASE/install.probe.ps1"
echo "lines: real=$(wc -l < install.ps1) probe=$(wc -l < $LBASE/install.probe.ps1) (probe drops 1 guard line, relaxes 1)"
PROF_W="$WBASE\\home\\profile.ps1"; PROF_L="$LBASE/home/profile.ps1"
pass=0; fail=0; ok(){ printf '  PASS: %s\n' "$1"; pass=$((pass+1)); }; bad(){ printf '  FAIL: %s\n' "$1"; fail=$((fail+1)); }
prof(){ [ -f "$PROF_L" ] && sed '1s/^\xEF\xBB\xBF//' "$PROF_L" | tr -d '\r' || echo "(no profile file)"; }
show(){ printf '%s\n' "$1" | grep -v '^\s*$' | head -${2:-5}; }
has(){ prof | grep -qFx -- "$1" && ok "line: $1" || { bad "missing line: $1"; prof; }; }
run(){ local exe=$1 scr=$2 pre=$3 args=$4; shift 4; timeout 90 "$exe" -NoProfile "$@" -Command "\$PROFILE='$PROF_W'; $pre; & '$WBASE\\$scr' $args" 2>&1 | tr -d '\r'; }
reset(){ rm -rf "${LBASE:?}/home"; }
seed(){ mkdir -p "$LBASE/home"; printf '%s\r\n' "$@" > "$PROF_L"; }
for EXE in "${engines[@]}"; do
echo "################ $EXE ################"
echo "### P1 headless fresh, no -DevRoot -> throw"; reset; out=$(run $EXE install.ps1 '' '' </dev/null); printf '%s' "$out" | grep -qF 'no terminal to ask on' && ok "message" || { bad "message"; show "$out"; }; [ -e "$PROF_L" ] && bad "profile created" || ok "nothing written"
echo "### P2 -DevRoot C:\\code fresh -> block with defaults"; reset; out=$(run $EXE install.ps1 '' '-DevRoot C:\code' </dev/null); printf '%s' "$out" | grep -qF 'added dev-shell block' && ok "added" || { bad "added"; show "$out"; }
has '$DevRoot = "C:\code"'; has '$DevShellUx = $true'; has '$DevContinuationPrompt = "❯❯ "'; has '$DevAccent = 214'; has ". \"$WBASE\\powershell\\dev-shell.ps1\""; prof | grep -q DevWsl && bad "WSL lines?" || ok "no WSL lines"
echo "### P3 headless re-run, no args -> allowed via block"; out=$(run $EXE install.ps1 '' '' </dev/null); printf '%s' "$out" | grep -qF 'updated dev-shell block' && ok "updated" || { bad "updated"; show "$out"; }; has '$DevRoot = "C:\code"'
echo "### P4 look params with nasty continuation, then round-trip"; out=$(run $EXE install.ps1 '' '-Accent 39 -ContinuationPrompt '"'"'a"b$c`d'"'"' -ShellUx $false' </dev/null); [ -n "$out" ] && :; has '$DevAccent = 39'; has '$DevShellUx = $false'; has '$DevContinuationPrompt = "a`"b`$c``d"'
out=$(run $EXE install.ps1 '' '-DevRoot D:\x' </dev/null); has '$DevRoot = "D:\x"'; has '$DevAccent = 39'; has '$DevShellUx = $false'; has '$DevContinuationPrompt = "a`"b`$c``d"'
res=$(timeout 90 $EXE -NoProfile -Command ". '$PROF_W'; ([int[]][char[]]\$DevContinuationPrompt) -join ','; \"acc=\$DevAccent ux=\$DevShellUx\"" </dev/null 2>&1 | tr -d '\r'); printf '%s' "$res" | grep -q '^97,34,98,36,99,96,100$' && ok "dot-sourced continuation round-trips (a\"b\$c\`d)" || { bad "round-trip"; printf '%s\n' "$res" | head -4; }; printf '%s' "$res" | grep -q 'acc=39 ux=False' && ok "accent/ux round-trip" || bad "acc/ux: $(printf '%s' "$res" | tail -1)"
echo "### P5 validation"; out=$(run $EXE install.ps1 '' '-Accent 300' </dev/null); printf '%s' "$out" | grep -q '255' && ok "-Accent 300 rejected" || { bad "accent range"; show "$out"; }; out=$(run $EXE install.ps1 '' "-DevRoot ''" </dev/null); printf '%s' "$out" | grep -qF 'must not be empty' && ok "empty root rejected" || bad "empty root"
echo "### P6 probe: root Enter, distro Enter, gate Enter -> defaults + preview"; reset; out=$(printf '\n\n\n' | run $EXE install.probe.ps1 '' ''); printf '%s' "$out" | grep -qF 'This is how it looks now:' && ok "preview heading" || { bad "preview heading"; show "$out" 12; }; printf '%s' "$out" | grep -qF 'selected item, in the accent' && ok "preview body" || bad "preview body"; has "\$DevRoot = \"$WHOME\\dev\""; has '$DevAccent = 214'
echo "### P7 probe: gate y, styling y, '>> ', 300, 99, keep Enter"; out=$(printf '\n\ny\ny\n>> \n300\n99\n\n' | run $EXE install.probe.ps1 '' ''); printf '%s' "$out" | grep -qF 'please give a number 0-255' && ok "accent re-prompt" || { bad "accent re-prompt"; show "$out" 12; }; printf '%s' "$out" | grep -qF 'With those settings:' && ok "second preview" || bad "second preview"; has '$DevShellUx = $true'; has '$DevContinuationPrompt = ">> "'; has '$DevAccent = 99'
echo "### P8 probe: gate y, styling n -> no accent question; keep Enter"; out=$(printf '\n\ny\nn\n\n' | run $EXE install.probe.ps1 '' ''); printf '%s' "$out" | grep -qF 'Accent colour' && bad "accent asked" || ok "accent not asked"; printf '%s' "$out" | grep -qF 'styling off' && ok "off-preview" || bad "off-preview"; has '$DevShellUx = $false'; has '$DevAccent = 99'
echo "### P9 probe with -Accent 5 -> gate skipped (no preview), root Enter keeps block value"; run $EXE install.ps1 '' '-DevRoot D:\fromblock' </dev/null >/dev/null; out=$(printf '\n\n' | run $EXE install.probe.ps1 '' '-Accent 5'); printf '%s' "$out" | grep -qF 'This is how it looks now' && bad "gate path taken" || ok "gate skipped"; has '$DevAccent = 5'; has '$DevRoot = "D:\fromblock"'
echo "### P10 real script -NonInteractive -DevRoot -> ok, look kept"; out=$(run $EXE install.ps1 '' '-DevRoot C:\ni' -NonInteractive </dev/null); printf '%s' "$out" | grep -qF 'updated dev-shell block' && ok "ok" || { bad "NonInteractive"; show "$out"; }; has '$DevAccent = 5'
echo "### P11 -Uninstall on a seeded profile -> block + blank above removed, rest intact"; seed 'head' '' '# >>> dev-shell >>>' '$DevRoot = "C:\old"' '# <<< dev-shell <<<' 'tail'; out=$(run $EXE install.ps1 '' '-Uninstall' </dev/null); printf '%s' "$out" | grep -qF 'removed the dev-shell block' && ok "message" || { bad "message"; show "$out"; }; [ "$(prof | tr '\n' '|')" = 'head|tail|' ] && ok "content = head|tail" || { bad "content: $(prof | tr '\n' '|')"; }
echo "### P12 -Uninstall with no block -> nothing to remove, untouched"; out=$(run $EXE install.ps1 '' '-Uninstall' </dev/null); printf '%s' "$out" | grep -qF 'nothing to remove' && ok "message" || bad "message"; [ "$(prof | tr '\n' '|')" = 'head|tail|' ] && ok "untouched" || bad "changed"
echo "### P12b -Uninstall with START but no END -> manual instructions"; seed 'a' '# >>> dev-shell >>>' 'x'; out=$(run $EXE install.ps1 '' '-Uninstall' </dev/null); printf '%s' "$out" | grep -qF 'by hand' && ok "manual instructions" || { bad "manual"; show "$out"; }; [ "$(prof | tr '\n' '|')" = 'a|# >>> dev-shell >>>|x|' ] && ok "untouched" || bad "changed"
echo "### P13 module: -Open alias + escape char on this engine"; reset; run $EXE install.ps1 '' '-DevRoot C:\m' </dev/null >/dev/null
res=$(timeout 90 $EXE -NoProfile -Command "Import-Module PSReadLine -ErrorAction SilentlyContinue; . '$PROF_W'; \"aliases=\$((Get-Command dev).Parameters['Open'].Aliases -join ',')\"; try { \$c=(Get-PSReadLineOption).SelectionColor; \"selcode=\$([int][char]\$c[0]) sel=\$(\$c.Substring(1))\"; \"cont=\$(([int[]][char[]](Get-PSReadLineOption).ContinuationPrompt) -join ',')\" } catch { 'psreadline-unavailable' }" </dev/null 2>&1 | tr -d '\r'); printf '%s\n' "$res" | grep -E 'aliases=|selcode=|cont=|unavailable'
printf '%s' "$res" | grep -q 'aliases=Explorer' && ok "-Explorer alias" || bad "alias"; printf '%s' "$res" | grep -q 'selcode=27 sel=\[1;38;5;214m' && ok "selection colour = ESC[1;38;5;214m" || { printf '%s' "$res" | grep -q unavailable && echo "  (PSReadLine options not readable here)" || bad "selection colour"; }
done
echo; echo "RESULT: $pass passed, $fail failed"; [ "$fail" = 0 ]
