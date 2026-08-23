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

- Matching history appears **as you type, from the first character**, up to **ten rows** under the line, each `> line … [History]` under a `<-/N>   <History(N)>` heading — PSReadLine's ListView, mirrored by dev-shell's own history completer. Nothing shows on an empty prompt.
- The typed text is matched as a **substring**, case-insensitively; **prefix matches rank first**, then the rest, each **newest first** (PowerShell's history predictor). No duplicates, no multi-line commands.
- The **matched text** and the **selected row** are in the accent; there are no event numbers and no background box.
- A picked line is inserted **without a trailing `;`**; **Enter runs it**.
- **Ctrl-R** is the plugin's reverse-search toggle within the list; the list stays history.

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

The typed line is a **virtual last row**: menu selection wraps first↔last, so **Up from the first match returns to what you typed** (and Down past the last match reaches it too), restoring the line — PSReadLine's original-input item. The list appears while typing, so the caret is at the end of the line; it returns there.

### Colours

- The **matched text** and the **selected row** take the accent (`DEV_SHELL_ACCENT`, default 214, bold) — PowerShell's `Emphasis` and `ListPredictionSelected`. The `> ` marker, the `[History]` tag and the heading are the metadata grey.
- No background box anywhere (the same stance as the Tab menu: recolour, don't box).

### Without zsh-autocomplete

Up/Down search history by what is already typed (history-substring-search) when that plugin is loaded; Tab is zsh's menu selection; nothing else changes. Everything is guarded, so a missing plugin only removes the feature.

### Switches

- `DEV_SHELL_UX=0`: none of the above is configured (the plugin, if loaded, keeps its own defaults); `install.sh --ux off` enables history-substring-search instead of zsh-autocomplete.
- `DEV_SHELL_KEYS=0`: dev-shell binds no Up/Down keys.

## Known gaps against PowerShell

- **The `<-/N>` index does not track the selection.** PSReadLine updates it to `<3/10>` as you move; the zsh heading is drawn once (compsys's `-X` explanation is static), so it always reads `<-/N>` with the right total but not the live position.
- **The virtual original is a visible last row** (`> your text`, dim, no tag). PSReadLine keeps it off-screen; here it is what makes Up-from-the-first-row work.
- **Deep in-list walks reset in fast succession is fine, but the plugin re-renders the list on every event**, so a very slow keystroke cadence can drop a selection back to the first row; at human speed the arrows hold.
- **Esc waits `KEYTIMEOUT`** (zsh's default 0.4 s) before acting, since arrow keys start with the same byte.
- **Startup cost**: zsh-autocomplete adds roughly 0.7–0.9 s to a new shell on a WSL2 machine.

## How it is built, and what it leans on

All in the `_dev_has_autocomplete` branch of `zsh/dev-shell.zsh`, each with a comment stating the coupling:

- History mode = `zstyle ':autocomplete:*' default-context history-incremental-search-backward`, `list-lines 10`, `min-input 1`, `add-semicolon no`, `setopt hist_find_no_dups`.
- **The list itself:** dev-shell owns `_autocomplete__history_lines`, replacing the plugin's (forked from zsh-autocomplete `027cdab` and reshaped). It matches the word at the cursor as a case-insensitive substring against the history values (`${(k)history[(R)…]}`, newest first via `(On)`), keeps the words around the cursor fixed, builds `> line … [History]` rows with an ellipsis, colours match and selected row via `_comp_colors`, draws the `<-/N>` heading through `-X`, and appends the typed line as a hidden-in-count last match for the virtual original. Defined at the first precmd, after the plugin's compinit declares the original for autoloading — **re-check it when the plugin updates.**
- Tab (`_dev_menu_complete`): the plugin would menu-select the history list already on screen, so dev-shell lists the plain completions first (`zle list-choices` with a local, empty `curcontext` — compsys's own context variable) and then `zle menu-select -w`. Verified alternatives: `zle -Rc` does not invalidate the on-screen list within the same widget; the plugin's private `_autocomplete__partial_list` would, but is internal.
- Enter (`_dev_menu_enter run|accept`): `menuselect` cannot hand Enter to a user widget — it leaves the menu and re-dispatches the key — so the widget that **opens** a menu binds `^M` first: `.accept-line` (run) for a history list, `accept-line` (accept only) for a completion menu; Down decides by the plugin's global `curcontext` (history unless Ctrl-R toggled the line).
- Esc: `bindkey -M menuselect '^[' send-break`.
- The plugin's recent-dirs feature writes to `${XDG_DATA_HOME:-~/.local/share}/zsh` without creating it; dev-shell creates the directory unless cdr was pointed elsewhere (the plugin's `enabled`/`recent-dirs` switches are read at source time, before dev-shell loads).

## Enforcing checks

`tests/zsh-ux.probe.py`, driven by `tests/install-sh.test.sh` B14 (plugin) and B15 (fallback); names as printed by the suite:

| Ruling | Check |
|---|---|
| nothing on an empty prompt; rows from the first characters | `no history list on the empty prompt`, `'dev ' lists the history rows starting with it`, `'pw' lists the history row 'pwd'` |
| Tab → project menu, header intact, accent row | `Tab opens the PROJECT menu, header not truncated by short names`, `menu lists the projects with the branch column`, `selected project row in the accent` |
| Enter accepts in a completion menu, runs from a history list | `Enter in the project menu accepts only (line not run: still in $HOME)`, `Down + Enter runs the picked history line`, `Enter in the Up history menu runs the selected line`, `Enter there accepts only (line not run: still in $HOME)` (after Ctrl-R) |
| Esc leaves; typing continues | `Esc leaves the list without running it (no pwd output)`, `typing continues after Esc` |
| rows, heading, ordering, no event numbers | `'pw' lists matching history rows as '> line [History]'`, `prefix match ranks before the substring match`, `heading shows <-/N> and <History(N)>`, `no event numbers on the rows` |
| colours | `match highlighted in the accent, not black-on-yellow`, `Down selects a row in the accent` |
| virtual original | `Down + Enter runs the first (prefix) match 'pwd'`, `Down then Up returns to the typed line 'pw'` (the fuller row-2/row-3/wrap walk is manual — the plugin's re-render defeats a slow pty cadence) |
| Up menu | `Up opens the history menu filtered by the typed prefix` |
| dev-shell owns the completer | `dev-shell owns the history completer`; fallback: `dev-shell does not own the history completer` |
| bindings and styles | `Up (both forms) -> _dev_history_menu`, `Down (both forms) -> _dev_list_select`, `Tab -> _dev_menu_complete`, `menuselect Enter is accept-line or .accept-line`, `no 'menu' zstyle from dev-shell with the plugin`, `min-input 1, history default-context, 10 list-lines, hist_find_no_dups` |
| recent-dirs directory | `cd does not trip the plugin's recent-dirs hook (data dir created)` |
| fallback | B15: `Up (both forms) -> history-substring-search-up`, `Down (both forms) -> history-substring-search-down`, `Tab stays expand-or-complete`, `'menu select' zstyle set`, `second Tab selects a row in the accent` |

## Decisions

- 2026-08-23 — zsh-autocomplete in history mode chosen by Karl for as-you-type parity over an fzf Ctrl-R list, with the measured costs accepted (startup, fuzzy matching, plugin-fixed chrome).
- 2026-08-23 — Enter runs from a history list and only accepts from a completion menu; Esc leaves; Tab keeps the project menu; Up/Down owned by the plugin, substring search as the fallback.
- 2026-08-23 — after Karl's first look, dev-shell **owns the history completer** to match PSReadLine: `> line [History]` rows, `<-/N> <History(N)>` heading, substring matching, no event numbers, accent colours, and a virtual original row so Up-from-the-first-row restores the typed line. The PowerShell `dev` menu became one `name │ on branch` row per project to match the zsh menu.
