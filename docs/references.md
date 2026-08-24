# Reference docs registry

[Home](../README.md) · **References** · [History list](history-list-behavior.md) · [Steering](../CLAUDE.md)

## Table of contents

- [Overview](#overview)
- [zsh](#zsh)
- [zsh plugins](#zsh-plugins)
- [PowerShell](#powershell)
- [Platform and tools](#platform-and-tools)

## Overview

The official documentation for everything dev-shell depends on, one row per dependency, with a note on when it is the page to open. Never assert an API, option or behaviour from memory — open the row. The universal registry (MDN, ARIA, WCAG, OWASP, Node, Git, Bash…) lives in `~/.claude/CLAUDE.md`; it is not repeated here.

## zsh

| Topic | Source | When |
|---|---|---|
| Line editor (`zle`, `bindkey`, widgets, `BUFFER`/`CURSOR`/`POSTDISPLAY`/`PREDISPLAY`, `region_highlight`, `KEYTIMEOUT`, `read -k`) | https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html (`man zshzle`) | the history ListView: drawing below the line, colouring it, binding keys |
| ZLE hook widgets (`add-zle-hook-widget line-pre-redraw` / `line-finish`) | https://zsh.sourceforge.io/Doc/Release/User-Contributions.html#index-add_002dzle_002dhook_002dwidget (`man zshcontrib`) | the ListView's render and cleanup hooks |
| Completion system (`zstyle` styles, `_description`, `_setup`, `list-colors`, `format`, `group-name`, `menu`) | https://zsh.sourceforge.io/Doc/Release/Completion-System.html (`man zshcompsys`) | the `_dev` completer, any `zstyle ':completion:*'` |
| Completion widgets (`compadd`, `compstate`, `curcontext`) | https://zsh.sourceforge.io/Doc/Release/Completion-Widgets.html (`man zshcompwid`) | `_dev_projects` (the Tab project menu) |
| complist module (`menuselect` keymap, `ma=` and friends, `ZLS_COLORS`) | https://zsh.sourceforge.io/Doc/Release/Zsh-Modules.html#The-zsh_002fcomplist-Module (`man zshmodules`) | menu selection, what Enter/Esc do inside a list |
| Contributed functions (`history-beginning-search-menu`, `cdr`/`chpwd_recent_dirs`, `add-zsh-hook`) | https://zsh.sourceforge.io/Doc/Release/User-Contributions.html (`man zshcontrib`) | recent-dirs, hooks |
| Options (`hist_find_no_dups`, `share_history`, `autopushd`…) | https://zsh.sourceforge.io/Doc/Release/Options.html (`man zshoptions`) | any `setopt` |
| Parameters (`$history`, `$commands`, `$functions`, `$nameddirs`, `$widgets`) | https://zsh.sourceforge.io/Doc/Release/Parameters.html and https://zsh.sourceforge.io/Doc/Release/Zsh-Modules.html#The-zsh_002fparameter-Module | detection code such as `_dev_has_autocomplete` |

## zsh plugins

The history list needs no plugin. The one optional extra is the inline ghost.

| Topic | Source | When |
|---|---|---|
| zsh-autosuggestions (`ZSH_AUTOSUGGEST_*`, `_ZSH_AUTOSUGGEST_DISABLED`) | https://github.com/zsh-users/zsh-autosuggestions#readme | the optional ghost text; how the ListView suppresses it while it is on |
| oh-my-zsh — plugins and `$ZSH_CUSTOM` | https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins · https://github.com/ohmyzsh/ohmyzsh/wiki/Customization | `install.sh` cloning/enabling zsh-autosuggestions |

## PowerShell

| Topic | Source | When |
|---|---|---|
| PSReadLine `Set-PSReadLineOption` (`PredictionSource`, `PredictionViewStyle ListView`, `Colors`: `ListPrediction`, `ListPredictionSelected`, `Emphasis`, `InlinePrediction`, `Selection`) | https://learn.microsoft.com/powershell/module/psreadline/set-psreadlineoption | the PowerShell side of the history list and the menu colours |
| PSReadLine `Set-PSReadLineKeyHandler` (`MenuComplete`, history functions) | https://learn.microsoft.com/powershell/module/psreadline/set-psreadlinekeyhandler | Tab and key parity |
| `about_PSReadLine` (keys, edit modes, history file) | https://learn.microsoft.com/powershell/module/psreadline/about/about_psreadline | where PowerShell keeps history; default bindings |
| `about_Profiles` (`$PROFILE`) | https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_profiles | the block `install.ps1` writes; the test `$PROFILE` override |
| `Read-Host` | https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/read-host | the installer's prompts |
| `System.Management.Automation.Language.Parser` | https://learn.microsoft.com/dotnet/api/system.management.automation.language.parser | the syntax check in `/verify` and the lint hook |

## Platform and tools

| Topic | Source | When |
|---|---|---|
| WSL interop (`wslpath`, running `.exe` from WSL, `\\wsl.localhost`) | https://learn.microsoft.com/windows/wsl/filesystems · https://learn.microsoft.com/windows/wsl/wsl-config | `_dev_open` on WSL, the PowerShell suite's paths |
| VS Code CLI and Remote WSL | https://code.visualstudio.com/docs/editor/command-line · https://code.visualstudio.com/docs/remote/wsl | `dev -c` / `-Code` |
| `xdg-open` · macOS `open` | https://www.freedesktop.org/wiki/Software/xdg-utils/ · https://ss64.com/mac/open.html | `_dev_open` off WSL |
| ShellCheck (codes, `-S` severity) | https://www.shellcheck.net/wiki/ | any finding in `install.sh` / `tests/*.sh` |
| Python `pty` / `select` (the UX probe driver) | https://docs.python.org/3/library/pty.html · https://docs.python.org/3/library/select.html | `tests/zsh-ux.probe.py` |
| `script(1)` (the installer pty tests) | https://man7.org/linux/man-pages/man1/script.1.html | `pty()` in `tests/install-sh.test.sh` |
