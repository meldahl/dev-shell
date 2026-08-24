# dev-shell

**Home** · [References](docs/references.md) · [History list](docs/history-list-behavior.md) · [Steering](CLAUDE.md)

## Table of contents

- [Overview](#overview)
- [What it gives you](#what-it-gives-you)
- [Install](#install)
- [Configuration](#configuration)
- [Portability — read this before using it elsewhere](#portability--read-this-before-using-it-elsewhere)
- [Uninstall](#uninstall)
- [Tests](#tests)
- [Licence](#licence)

## Overview

A `dev` command plus completion and history polish, kept identical across
**PowerShell** and **zsh** — so the same muscle memory works on Windows and
inside WSL or Linux.

```
❯ dev <Tab>

PROJECT        │ BRANCH
api            │ on main
website        │ on feat/dark-mode
cli            │ on fix/flaky-tests
notes          │ no git repo
```

## What it gives you

| Command | Action |
|---|---|
| `dev` | cd to your projects root |
| `dev myproject` | cd into a project |
| `dev <Tab>` | menu of projects, one `name │ on branch` row each |
| `dev myproject -c` / `-Code` | open in VS Code |
| `dev myproject -o` / `-Open` | open in your file manager — Explorer, Finder, or the desktop default (`-e` / `-Explorer` still work) |
| `dev --help` / `Get-Help dev` | usage |

Plus, in both shells: Tab opens a **visual menu** instead of cycling silently,
the selection is **recoloured rather than boxed** (a filled box always abuts the
next column), and **matching history is listed as you type** — up to ten
`> line` rows under a live `<i/N>  <History(i/N)>` heading, Down/Up move through
them (the header tracks the position), Up from the first row returns to what you
typed with its cursor, Enter runs the pick, Esc leaves it, and Tab still opens
the project menu. PowerShell does this with PSReadLine's ListView; zsh with a
ListView dev-shell draws itself in the line editor — no plugin — so the two look
and behave the same.

## Install

Clone anywhere, then run the installer for whichever shell you use. It asks
where your projects live — Enter keeps the default, `~/dev` — and writes a small
block into your shell config, backing the file up first.

**zsh**

```sh
git clone https://github.com/meldahl/dev-shell.git ~/dev/dev-shell
cd ~/dev/dev-shell
./install.sh
```

**PowerShell**

```powershell
git clone https://github.com/meldahl/dev-shell.git $HOME\dev\dev-shell
cd $HOME\dev\dev-shell
./install.ps1
```

On Windows with WSL installed, the PowerShell installer also asks which distro
and which path inside it `-Code` should open (Enter skips). With both set, the
editor runs inside Linux through the VS Code WSL remote rather than tunnelling
over the filesystem bridge.

Then it shows a **preview** of the look on a few sample projects — the menu
header, the accent-coloured selected item, a ghost-text suggestion, the history
list, the continuation prompt — and offers to customize it: styling on or off, the
continuation prompt (`❯❯`; in zsh `%_❯❯`, where `%_` names the construct still
open — `dquote❯❯`, `then❯❯` — as zsh's own default does), the accent colour (a
256-colour index, amber `214` by default) and, in zsh, the Up/Down history keys.
Enter keeps every default; after your answers the preview is shown again and you
confirm or go round once more.

**Changing the paths later.** Re-run the installer: each question defaults to
your current setting, and the block is replaced in place, never duplicated. Or
edit the block by hand — [Uninstall](#uninstall) says where it lives.

**Scripted installs.** Without a terminal to ask on (`curl | bash`, CI, a
dotfiles bootstrap) the installers refuse to guess the path and exit with a
message unless a block already has it; the look keeps its current values. Pass
what you want instead — a flag or parameter is never asked for, and when any
look setting is given the customization step is skipped:

```sh
./install.sh --dev-root ~/code --ux on --keys off --accent 39 --continuation '>> '
```

```powershell
./install.ps1 -DevRoot C:\code -WslDistro Ubuntu -WslRoot /home/you/dev -Accent 39
# also: -ShellUx $false  -ContinuationPrompt '>> '
```

`DEV_ROOT` in the environment also works for the zsh installer: scripts use it
as the answer, and when the installer can ask it is the default on offer (after
an existing block, which always wins).

## Configuration

The installer writes these into the block it adds, from your answers or its
arguments; re-run it to change them, or set them by hand **before** the module
is sourced.

| zsh | PowerShell | Meaning |
|---|---|---|
| `DEV_ROOT` | `$DevRoot` | projects directory (default `~/dev`) |
| — | `$DevWslDistro` | WSL distro for `-Code`, e.g. `Ubuntu` |
| — | `$DevWslRoot` | projects path *inside* that distro |
| `DEV_SHELL_UX=0` | `$DevShellUx = $false` | skip the styling and the history list, keep the command |
| `DEV_SHELL_KEYS=0` | — | leave Up/Down/Esc at their zsh defaults (the list still shows) |
| `DEV_SHELL_ACCENT` | `$DevAccent` | 256-colour index for the selected item (default `214`) |
| `DEV_SHELL_CONTINUATION` | `$DevContinuationPrompt` | continuation prompt (default `%_❯❯ ` / `❯❯ `) |
| — | `$DevPromptExtraLines` | extra lines your prompt occupies (auto-detected) |

## Portability — read this before using it elsewhere

**Works anywhere**

- The `dev` command, git-branch annotations, and Tab completion, on any machine
  with zsh or PowerShell.
- `-c` / `-Code` wherever `code` is on `PATH` (falls back to opening the local
  path when the WSL settings are absent).
- `-o` / `-Open` opens Explorer from Windows and WSL, Finder on macOS (`open`),
  and the desktop default on Linux (`xdg-open`, which must be installed).
- Branch detection reads `.git/HEAD` directly rather than shelling out, so no
  `git` binary is required and it stays fast with many projects. It also works
  where a Windows `git` would refuse outright: inspecting a repo inside WSL
  fails with *detected dubious ownership* unless you weaken `safe.directory`.
  Worktrees and submodules (a `.git` file rather than a directory) are followed.

**Needs something extra**

- **The history list needs no plugin** — it is drawn in the zsh line editor.
  The one optional extra is
  [`zsh-autosuggestions`](https://github.com/zsh-users/zsh-autosuggestions) for
  grey inline ghost text; `install.sh` clones and enables it when oh-my-zsh is
  present. Because the list is itself the prediction (its top row is the
  suggestion), the ghost is turned off while the list is on, so the two do not
  fight — the same as PowerShell's ListView, which has no inline ghost. If you
  were running [`zsh-autocomplete`](https://github.com/marlonrichert/zsh-autocomplete),
  remove it from `plugins=(…)`: it draws its own list and would conflict.
- **PowerShell predictions need PSReadLine 2.2+.** Older versions still get the
  Tab menu; the prediction block is wrapped in `try`/`catch`.
- **A Unicode-capable font.** The `│` rule, the `❯❯` continuation prompt, and the
  box characters need one. Any Nerd Font or modern terminal font is fine;
  a legacy raster font will show boxes.

**Known limitations**

- **Windows PowerShell 5.1 cannot follow a symlink whose target is a UNC path.**
  If `$DevRoot` is a symlink to `\\wsl.localhost\...`, 5.1 fails on it entirely
  while PowerShell 7 is fine. Point `$DevRoot` straight at the UNC path on 5.1.
- **The description column cannot be coloured in zsh's Tab menu.** Two
  independent limits close it off: zsh escapes control characters inside
  `compadd` display strings, and `list-colors` patterns match the completion
  *value*, never the displayed text. The `│` rule and the coloured header do
  that work instead. (The history list, drawn separately, has no such limit —
  its match and selection are in the accent.)
- **The `>` marker on the selected row of PowerShell's prediction dropdown is
  hardcoded** in PSReadLine. Only its colours are configurable.
- **The zsh history list matches on a plain case-insensitive substring**
  (prefix-first, newest-first), where PSReadLine's predictor has extra ranking;
  and a keystroke within ~30 ms of Esc can read as a key sequence rather than a
  lone Esc. Neither bites at human speed. The look, the live `<i/N>` header, and
  the typed-line-restored-on-Up otherwise match PowerShell exactly.
- **The PowerShell `dev` menu has no header row.** MenuComplete lays items out
  in columns with no slot for a `PROJECT │ BRANCH` heading, so that stays a
  zsh-only touch; the project rows themselves match.
- **No vertical spacing between the input line and the completion menu.**
  PSReadLine exposes no such option (`ExtraPromptLineCount` is for multi-line
  prompts and misusing it corrupts rendering).
- Working from a Windows shell into a WSL path crosses the filesystem bridge on
  every operation and is far slower for git and builds. Use `dev` from a shell
  inside the distro for real work; the Windows side is the convenient door.

## Uninstall

```sh
./install.sh --uninstall
```

```powershell
./install.ps1 -Uninstall
```

Either removes the block between `# >>> dev-shell >>>` and `# <<< dev-shell <<<`
from `~/.zshrc` or your `$PROFILE`, backing the file up first, and says so if it
cannot — then delete that block by hand, or restore one of the `*-backup-*`
files the installers leave beside the config. The oh-my-zsh plugins `install.sh`
enabled stay in `plugins=(…)`; drop them there if you no longer want them.

## Tests

`tests/run.sh` runs both suites and fails if either does: the zsh suite (bash,
zsh, python3, `script`; pty-driven against sandboxed homes, with a small VT
emulator rendering the terminal grid) and, from WSL, the PowerShell suite
against pwsh 7 and Windows PowerShell 5.1 (skipped with a note where they are
not reachable). Scratch directories are removed on success and kept, with their
paths printed, on failure.

## Licence

MIT