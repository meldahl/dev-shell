#!/bin/sh
# PostToolUse hook (Edit|Write): check the edited file with the tool that owns
# its language and feed findings back (exit 2 + stderr). The same per-file
# checks /verify runs first; the suites are too slow for a hook.
f=$(python3 -c 'import json, sys
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))
except Exception:
    print("")')
[ -n "$f" ] && [ -f "$f" ] || exit 0

fail() { # $1 tool, $2 output
  echo "$1: $f" >&2
  printf '%s\n' "$2" | head -20 >&2
  exit 2
}

case "$f" in
  *.sh)
    out=$(bash -n "$f" 2>&1) || fail "bash -n" "$out"
    if command -v shellcheck >/dev/null 2>&1; then
      out=$(shellcheck -S warning -f gcc "$f" 2>&1) || fail "shellcheck (warning level)" "$out"
    fi ;;
  *.zsh)
    out=$(zsh -n "$f" 2>&1) || fail "zsh -n" "$out" ;;
  *.py)
    out=$(python3 -m py_compile "$f" 2>&1) || fail "py_compile" "$out" ;;
  *.ps1)
    # The PowerShell parser, on whichever engine is reachable (from WSL the
    # Windows ones, through interop, need a Windows path).
    engine=""
    for e in pwsh.exe powershell.exe pwsh; do
      command -v "$e" >/dev/null 2>&1 && { engine=$e; break; }
    done
    [ -n "$engine" ] || exit 0
    w=$f
    case $engine in *.exe) command -v wslpath >/dev/null 2>&1 && w=$(wslpath -w "$f") ;; esac
    out=$("$engine" -NoProfile -Command "\$e=\$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$w', [ref]\$null, [ref]\$e); \$e | ForEach-Object { \$_.Extent.StartLineNumber.ToString() + ': ' + \$_.Message }" 2>&1 | tr -d '\r')
    [ -z "$out" ] || fail "PowerShell parser" "$out" ;;
esac
exit 0
