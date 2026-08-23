# History list behaviour

[Home](../README.md) · [References](references.md) · **History list** · [Steering](../CLAUDE.md)

## Table of contents

- [Overview](#overview)
- [The contract](#the-contract)
  - [What the list shows](#what-the-list-shows)
  - [Keys](#keys)
  - [Colours](#colours)
  - [Without zsh-autocomplete](#without-zsh-autocomplete)
  - [Switches](#switches)
- [Known gaps against PowerShell](#known-gaps-against-powershell)
- [How it is built, and what it leans on](#how-it-is-built-and-what-it-leans-on)
- [Enforcing checks](#enforcing-checks)
- [Decisions](#decisions)

## Overview

PowerShell shows PSReadLine's ListView — history predictions in a list under the line, filtered as you type. The zsh side mirrors it with zsh-autocomplete in history mode, configured and partly re-shaped by `zsh/dev-shell.zsh`. This is the contract both sides are held to, the gaps that cannot be closed, and where each ruling is enforced. Rulings made by Karl on 2026-08-23; when one changes, this file changes in the same commit as the code.

## The contract

### What the list shows

- Matching history appears **as you type, from the first character**, up to **ten rows** under the line; nothing is shown on an empty prompt (PowerShell: ListView, `MaximumHistoryCount`-style cap of 10 items).
- **No duplicates**: the same command line appears once (PowerShell's `HistoryNoDuplicates`; zsh's `hist_find_no_dups`).
- A picked line is inserted **without a trailing `;`**.
- Each new command line starts in history mode. **Ctrl-R** switches that line to live completions (the PROJECT table appears as you type `dev `); Enter or a new line returns to history mode.

### Keys

| Key | In the list is on screen | Inside the list (menu selection) |
|---|---|---|
| **Down** | enters the list, first row selected | next row |
| **Up** | opens the **history menu** (all matches, arrow-navigable) | previous row |
| **Enter** | runs the line as typed | **runs** the selected history line (PowerShell: Enter executes); in a **completion** menu — the PROJECT table after Tab or after Ctrl-R — it only **accepts** the entry (PowerShell's MenuComplete) |
| **Esc** | — | **leaves** the list and restores the line (PowerShell's Esc dismisses its list) |
| **Tab** | opens the **project menu** even while the live list shows history | next item |
| typing | keeps filtering | leaves the list and keeps filtering |
| Ctrl-G / Ctrl-C | — | leave, restoring the line |

### Colours

- The **matched text** and the **selected row** take the accent (`DEV_SHELL_ACCENT`, default 214, bold) — PowerShell's `Emphasis` and `ListPredictionSelected`. Rows are otherwise plain; the event number column is dim.
- No background box anywhere (the same stance as the Tab menu: recolour, don't box).

### Without zsh-autocomplete

Up/Down search history by what is already typed (history-substring-search) when that plugin is loaded; Tab is zsh's menu selection; nothing else changes. Everything is guarded, so a missing plugin only removes the feature.

### Switches

- `DEV_SHELL_UX=0`: none of the above is configured (the plugin, if loaded, keeps its own defaults); `install.sh --ux off` enables history-substring-search instead of zsh-autocomplete.
- `DEV_SHELL_KEYS=0`: dev-shell binds no Up/Down keys.

## Known gaps against PowerShell

- **No heading or counter** (`<History(10)>`, `<-/10>`, `[History]` tags): zsh-autocomplete passes an empty description and compsys then renders no heading; there is no hook for a counter.
- **Event numbers** in a dim column; PowerShell shows none.
- **Fuzzy matching**: the plugin matches the typed characters as a subsequence (`pw` lists `playwright` after `pwd`); PowerShell matches the typed text as a whole.
- **After the Up menu**, that line's live list shows completions until the next line.
- **Esc waits `KEYTIMEOUT`** (zsh's default 0.4 s) before acting, since arrow keys start with the same byte.
- **Startup cost**: zsh-autocomplete adds roughly 0.7–0.9 s to a new shell on a WSL2 machine.

## How it is built, and what it leans on

All in the `_dev_has_autocomplete` branch of `zsh/dev-shell.zsh`, each with a comment stating the coupling:

- History mode = `zstyle ':autocomplete:*' default-context history-incremental-search-backward`, `list-lines 10`, `min-input 1`, `add-semicolon no`, `setopt hist_find_no_dups`.
- Tab (`_dev_menu_complete`): the plugin would menu-select the history list already on screen, so dev-shell lists the plain completions first (`zle list-choices` with a local, empty `curcontext` — compsys's own context variable) and then `zle menu-select -w`. Verified alternatives: `zle -Rc` does not invalidate the on-screen list within the same widget; the plugin's private `_autocomplete__partial_list` would, but is internal.
- Enter (`_dev_menu_enter run|accept`): `menuselect` cannot hand Enter to a user widget — it leaves the menu and re-dispatches the key — so the widget that **opens** a menu binds `^M` first: `.accept-line` (run) for a history list, `accept-line` (accept only) for a completion menu; Down decides by the plugin's global `curcontext` (history unless Ctrl-R toggled the line).
- Esc: `bindkey -M menuselect '^[' send-break`.
- Colours (`_dev_history_colours`): the plugin hard-codes `30;103` (black on yellow) and keeps no selected-row style for the list (its filter retains only an unprefixed `ma=`, which `_setup` does not produce for a tagged group). `_main_complete` has already turned `_comp_colors` into `ZLS_COLORS` when the post-functions run, so a `comppostfuncs` function rewrites it; compinit empties that array and the plugin runs compinit at the first precmd, so the hook is re-registered at every precmd, and `_dev_menu_complete` keeps a local copy across zsh's own `list-choices`.
- The plugin's recent-dirs feature writes to `${XDG_DATA_HOME:-~/.local/share}/zsh` without creating it; dev-shell creates the directory unless cdr was pointed elsewhere (the plugin's `enabled`/`recent-dirs` switches are read at source time, before dev-shell loads).

## Enforcing checks

`tests/zsh-ux.probe.py`, driven by `tests/install-sh.test.sh` B14 (plugin) and B15 (fallback); names as printed by the suite:

| Ruling | Check |
|---|---|
| nothing on an empty prompt; rows from the first characters | `no history list on the empty prompt`, `'dev ' lists the history rows starting with it`, `'pw' lists the history row 'pwd'` |
| Tab → project menu, header intact, accent row | `Tab opens the PROJECT menu, header not truncated by short names`, `menu lists the projects with the branch column`, `selected project row in the accent` |
| Enter accepts in a completion menu, runs from a history list | `Enter in the project menu accepts only (line not run: still in $HOME)`, `Down + Enter runs the picked history line`, `Enter in the Up history menu runs the selected line`, `Enter there accepts only (line not run: still in $HOME)` (after Ctrl-R) |
| Esc leaves; typing continues | `Esc leaves the list without running it (no pwd output)`, `typing continues after Esc` |
| Up = history menu; Ctrl-R = live completions | `Up opens the history menu filtered by the typed prefix`, `after Ctrl-R, Down enters the live completion list (PROJECT table)` |
| colours | `match recoloured to the accent, no black-on-yellow`, `Down: selected history row carries the accent`, `recolour survives a Tab earlier on the line (hook kept)` |
| bindings and styles | `Up (both forms) -> _dev_history_menu`, `Down (both forms) -> _dev_list_select`, `Tab -> _dev_menu_complete`, `menuselect Enter is accept-line or .accept-line`, `no 'menu' zstyle from dev-shell with the plugin`, `min-input 1, history default-context, 10 list-lines, hist_find_no_dups` |
| recent-dirs directory | `cd does not trip the plugin's recent-dirs hook (data dir created)` |
| fallback | B15: `Up (both forms) -> history-substring-search-up`, `Down (both forms) -> history-substring-search-down`, `Tab stays expand-or-complete`, `'menu select' zstyle set`, `second Tab selects a row in the accent` |

## Decisions

- 2026-08-23 — zsh-autocomplete in history mode chosen by Karl for as-you-type parity over an fzf Ctrl-R list, with the measured costs accepted (startup, fuzzy matching, plugin-fixed chrome).
- 2026-08-23 — Enter runs from a history list and only accepts from a completion menu; Esc leaves; Tab keeps the project menu; Up/Down owned by the plugin, substring search as the fallback; colours recoloured to the accent after Karl's first look.
