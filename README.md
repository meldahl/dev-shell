# dev-shell

A `dev` command plus completion and history polish, kept identical across
**PowerShell** and **zsh** — so the same muscle memory works on Windows and
inside WSL or Linux.

```
❯ dev <Tab>

PROJECT        │ BRANCH
apollo         │ on main
hermesAI       │ on add_jwt_token_auth
jarvis         │ on feat/action-builder
random         │ no git repo
```

## What it gives you

| Command | Action |
|---|---|
| `dev` | cd to your projects root |
| `dev myproject` | cd into a project |
| `dev <Tab>` | menu of projects, annotated with the current git branch |
| `dev myproject -c` / `-Code` | open in VS Code |
| `dev myproject -e` / `-Explorer` | open in the file manager |
| `dev --help` / `Get-Help dev` | usage |

Plus, in both shells: Tab opens a **visual menu** instead of cycling silently,
the selection is **recoloured rather than boxed** (a filled box always abuts the
next column), and history drives **inline suggestions**.

## Install

Clone anywhere, then run the installer for whichever shell you use. Both back up
your config first and are safe to re-run.

**zsh**

```sh
git clone https://github.com/YOUR-NAME/dev-shell.git ~/dev/dev-shell
cd ~/dev/dev-shell
DEV_ROOT=~/dev ./install.sh
```

**PowerShell**

```powershell
git clone https://github.com/YOUR-NAME/dev-shell.git $HOME\dev\dev-shell
cd $HOME\dev\dev-shell
./install.ps1 -DevRoot $HOME\dev
```

If your projects live inside WSL but you drive them from Windows, point `-Code`
at the WSL remote so the editor runs inside Linux rather than tunnelling over
the filesystem bridge:

```powershell
./install.ps1 -DevRoot $HOME\dev -WslDistro Ubuntu -WslRoot /home/you/dev
```

## Configuration

Set these **before** the module is sourced (the installer writes them into the
block it adds).

| zsh | PowerShell | Meaning |
|---|---|---|
| `DEV_ROOT` | `$DevRoot` | projects directory (default `~/dev`) |
| — | `$DevWslDistro` | WSL distro for `-Code`, e.g. `Ubuntu` |
| — | `$DevWslRoot` | projects path *inside* that distro |
| `DEV_SHELL_UX=0` | `$DevShellUx = $false` | skip the styling, keep the command |
| `DEV_SHELL_KEYS=0` | — | skip the Up/Down history keybindings |
| — | `$DevPromptExtraLines` | extra lines your prompt occupies (auto-detected) |

## Portability — read this before using it elsewhere

**Works anywhere**

- The `dev` command, git-branch annotations, and Tab completion, on any machine
  with zsh or PowerShell.
- `-c` / `-Code` wherever `code` is on `PATH` (falls back to opening the local
  path when the WSL settings are absent).
- Branch detection reads `.git/HEAD` directly rather than shelling out, so no
  `git` binary is required and it stays fast with many projects. It also works
  where a Windows `git` would refuse outright: inspecting a repo inside WSL
  fails with *detected dubious ownership* unless you weaken `safe.directory`.
  Worktrees and submodules (a `.git` file rather than a directory) are followed.

**Needs something extra**

- **`-e` / `--explorer` in zsh requires WSL.** It uses `wslpath` and
  `explorer.exe`. On native Linux or macOS it exits with an error rather than
  doing something surprising. Swap in `xdg-open` or `open` if you want it there.
- **Suggestions and history search need two zsh plugins**, `zsh-autosuggestions`
  and `history-substring-search`. `install.sh` handles both when oh-my-zsh is
  present; without oh-my-zsh, install them yourself. The keybindings are guarded,
  so nothing breaks if they are missing — the features are simply absent.
- **PowerShell predictions need PSReadLine 2.2+.** Older versions still get the
  Tab menu; the prediction block is wrapped in `try`/`catch`.
- **A Unicode-capable font.** The `│` rule, the `❯❯` continuation prompt, and the
  box characters need one. Any Nerd Font or modern terminal font is fine;
  a legacy raster font will show boxes.

**Known limitations**

- **Windows PowerShell 5.1 cannot follow a symlink whose target is a UNC path.**
  If `$DevRoot` is a symlink to `\\wsl.localhost\...`, 5.1 fails on it entirely
  while PowerShell 7 is fine. Point `$DevRoot` straight at the UNC path on 5.1.
- **The description column cannot be coloured in zsh.** Two independent limits
  close it off: zsh escapes control characters inside `compadd` display strings,
  and `list-colors` patterns match the completion *value*, never the displayed
  text. The `│` rule and the coloured header do that work instead.
- **The `>` marker on the selected row of PowerShell's prediction dropdown is
  hardcoded** in PSReadLine. Only its colours are configurable.
- **No vertical spacing between the input line and the completion menu.**
  PSReadLine exposes no such option (`ExtraPromptLineCount` is for multi-line
  prompts and misusing it corrupts rendering).
- Working from a Windows shell into a WSL path crosses the filesystem bridge on
  every operation and is far slower for git and builds. Use `dev` from a shell
  inside the distro for real work; the Windows side is the convenient door.

## Uninstall

Delete the block between `# >>> dev-shell >>>` and `# <<< dev-shell <<<` from
`~/.zshrc` or your `$PROFILE`, or restore one of the `*-backup-*` files the
installers leave beside them.

## Licence

MIT