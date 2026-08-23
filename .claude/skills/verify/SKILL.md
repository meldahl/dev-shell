---
name: verify
description: Full dev-shell verification pass — syntax checks for every language in the repo, shellcheck at warning level, then tests/run.sh (the zsh suite and, from WSL, the PowerShell suite). Run before commits and at every block boundary.
---

Run from the repo root. Judge every step by its own output, never by a pipeline's exit status.

1. **Syntax, every language** — all four must be silent:
   `bash -n install.sh tests/*.sh` · `zsh -n zsh/dev-shell.zsh` · `python3 -m py_compile tests/zsh-ux.probe.py` · the PowerShell parser on `install.ps1` and `powershell/dev-shell.ps1` (from WSL, with a Windows path):
   `pwsh.exe -NoProfile -Command "$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile('<wslpath -w file>', [ref]$null, [ref]$e); $e | % { $_.Extent.StartLineNumber.ToString() + ': ' + $_.Message }"` (repeat with `powershell.exe` for 5.1).
2. **shellcheck, warning level**: `shellcheck -S warning install.sh tests/*.sh` — no output. Style notes are not gated (the dense harnesses carry quoting notes); never add a `# shellcheck disable` without a `-- reason` and a probe that the rule really fires on correct code.
3. **Suites**: `bash tests/run.sh` — the zsh suite (bash, zsh, python3, `script`; clones zsh-autocomplete into scratch unless `ZAC=` points at one; ~3 min) then, from WSL, the PowerShell suite against pwsh 7 and Windows PowerShell 5.1 (~3 min; elsewhere it prints a skip note). Read each suite's `RESULT: N passed, M failed` line and `run.sh`'s exit status. A failing suite keeps its scratch directory and prints `scratch kept: …` — inspect it, then delete it.
4. **Never edit files while the suites run**: they source the working tree, so a mid-run edit voids the run — re-run from step 1.
5. **Report faithfully**: counts per suite, every FAIL line with its context lines, the skip note if any. "Green" = both RESULT lines show `0 failed` and `run.sh` exited 0. The suites use sandbox homes; the real machine's shell is checked by opening a new tab.
