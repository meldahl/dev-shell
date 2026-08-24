# dev-shell — steering

[Home](README.md) · [References](docs/references.md) · [History list](docs/history-list-behavior.md) · **Steering**

## Table of contents

- [Overview](#overview)
- [Working with Karl — decision checkpoints](#working-with-karl--decision-checkpoints)
- [Building new features — reuse before you write](#building-new-features--reuse-before-you-write)
- [Code style](#code-style)
- [Architecture notes](#architecture-notes)
- [Verification standard](#verification-standard)
- [Docs, plan, memory](#docs-plan-memory)

## Overview

Project-specific steering for dev-shell — a `dev` command plus completion and history polish kept identical across PowerShell and zsh (see the [README](README.md)). The portable rules live in `~/.claude/CLAUDE.md`; this file holds only what is specific to this repo. The standing principle, restated by Karl on 2026-08-23: **keep pwsh and zsh/wsl as similar as possible** — a feature lands on both sides, or its gap is written into README "Known limitations" in the same change.

## Working with Karl — decision checkpoints

The global rules apply: end completed work with a clickable AskUserQuestion (open decisions plus what next, recommendations first); never commit unasked — approval covers one block, this public repo carries **no `Co-Authored-By` trailer** and Karl's Gmail as author; record behaviour rulings in the same change, in `docs/<domain>-behavior.md` (see [Docs, plan, memory](#docs-plan-memory)). The plan lives at `~/.claude/plans/dev-shell-plan.md`.

## Building new features — reuse before you write

| Need | Reuse | Where |
|---|---|---|
| A new `dev` option | the `for arg` parser (options bind before or after the project), the `_dev()` `_arguments` spec; PowerShell's `param()` with the same name | `zsh/dev-shell.zsh` `dev()` / `_dev()`, `powershell/dev-shell.ps1` |
| Open something external | `_dev_open` — WSL → `explorer.exe`, macOS → `open`, else `xdg-open` | `zsh/dev-shell.zsh` |
| A completion list with a header and aligned columns | `_dev_projects`: `compadd -Q -l -X header -d displays -a names`; width starts at the header's length. PowerShell: `name │ desc` rows padded past half the buffer so MenuComplete stays single-column | `zsh/dev-shell.zsh`, `powershell/dev-shell.ps1` |
| The history list as you type | the ListView in the `DEV_SHELL_UX` branch: `_dev_lv_render` (POSTDISPLAY + region_highlight, on `line-pre-redraw`), `_dev_lv_compute`, `_dev_lv_down`/`_dev_lv_up` (nav, −1 = the typed line), `_dev_lv_escape` (dismiss/dispatch), `_dev_lv_finish` | `zsh/dev-shell.zsh` "Shell UX"; contract in [docs/history-list-behavior.md](docs/history-list-behavior.md) |
| A new install-time setting | `current` / `quoted` / `ask` / `ask_yn` / `preview` and the `BLOCK` template, flags parsed in the top loop; PowerShell: `param()` plus the same marked block | `install.sh`, `install.ps1` |
| A new oh-my-zsh plugin | `clone_plugin` + `enable_plugin` (prepends; the last one enabled ends first) | `install.sh` |
| A test of an installer | headless: `"$INST" --flag </dev/null`; prompted: `pty()` through `script`; PowerShell: `run()` with the `$PROFILE` override and the probe copy | `tests/install-sh.test.sh`, `tests/install-ps1.test.sh` |
| A test of the zsh line UX | `uxhome` + `tests/zsh-ux.probe.py` (pty driver: `send`, `query`, `rows`, `check`) | `tests/install-sh.test.sh` B14/B15 |
| A tool the code shells out to | stub it on PATH and log the call (`explorer.exe`, `open`, `xdg-open`, `code`, `git`) | B12, B16, `uxhome` |

## Code style

- zsh module: `local` everything, `print -r --`, guard-first, `(( flag ))`, `$+commands[x]` / `$+functions[x]`; comments state constraints — many are ZLE couplings (POSTDISPLAY, region_highlight offsets, hook order, KEYTIMEOUT), keep them accurate.
- bash (`install.sh`, tests): `set -u`, POSIX-leaning, **shellcheck clean at warning level**; no `# shellcheck disable` without a `-- reason`.
- PowerShell mirrors the zsh side name for name (`$DevRoot` / `DEV_ROOT`, `-Open` / `--open`, `$DevAccent` / `DEV_SHELL_ACCENT`).
- Tests are dense one-line checks with `ok` / `bad` counters and a `RESULT: N passed, M failed` line; a behaviour fix lands with a check, and a bug report becomes a failing check first.

## Architecture notes

- Files: `zsh/dev-shell.zsh` (module: `dev`, completion, Shell UX, keys), `powershell/dev-shell.ps1`, `install.sh` / `install.ps1` (write a marked block into `~/.zshrc` / `$PROFILE`; a re-run replaces it; `--uninstall` / `-Uninstall`), `tests/` (see [Verification standard](#verification-standard)), `docs/`.
- Load order: the block is sourced at the **end** of `.zshrc`, after oh-my-zsh and any plugins. The history list needs **no plugin** — it is drawn in ZLE (`POSTDISPLAY` + `region_highlight`, a `line-pre-redraw` hook). The one optional extra is zsh-autosuggestions (ghost text), which the ListView **suppresses while it is on** (`_ZSH_AUTOSUGGEST_DISABLED=1`) so the two do not fight for `POSTDISPLAY`.
- ZLE couplings, commented in the Shell UX block: the render runs only after an editing/nav widget (a `_DEV_LV_KEEP` allow-list) so it never draws over the Tab project menu; `region_highlight` offsets index buffer + POSTDISPLAY and are tagged `memo=devlv`; Esc peeks the next byte to tell an arrow from a lone Esc (no `KEYTIMEOUT` lag). zsh-autocomplete, if still in `plugins=(…)`, draws its own list and conflicts — `install.sh` warns.
- Headless installs need a path (flag, env, or an existing block); the only plugin the installer touches is zsh-autosuggestions (optional ghost text).
- This machine has the real install (block in `~/.zshrc`); the suites never touch the real HOME — sandbox homes under `mktemp`, the PowerShell suite under Windows `%TEMP%`.

## Verification standard

`/verify`: syntax for every language (`bash -n`, `zsh -n`, the PowerShell parser, `py_compile`) → `shellcheck -S warning install.sh tests/*.sh` → `bash tests/run.sh` (zsh suite, then the PowerShell suite from WSL), judged by each suite's `RESULT` line and `run.sh`'s exit status. The PostToolUse hook `.claude/hooks/lint-changed.sh` runs the per-file checks on every edit.

## Docs, plan, memory

- [docs/references.md](docs/references.md): the registry of official docs for every dependency (zsh manual sections incl. ZLE, PSReadLine, WSL…). A new dependency adds a row in the same change.
- Behaviour rulings go to `docs/<domain>-behavior.md` — the narrative contract plus pointers to the checks that enforce it — in the same change as the code. First instance: [docs/history-list-behavior.md](docs/history-list-behavior.md).
- Markdown convention (global): one nav bar under every H1 (current doc bold), a `## Table of contents`, lead text under `## Overview`; verify links and anchors after a restructure.
- Plan: `~/.claude/plans/dev-shell-plan.md` ("Where things stand" first). Memory: `~/.claude/projects/-home-karlb-dev-dev-shell/memory/`.
