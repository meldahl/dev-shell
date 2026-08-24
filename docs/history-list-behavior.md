# History list behaviour

[Home](../README.md) · [References](references.md) · **History list** · [Steering](../CLAUDE.md)

## Table of contents

- [Overview](#overview)
- [The contract](#the-contract)
  - [What the list shows](#what-the-list-shows)
  - [Keys](#keys)
  - [Colours](#colours)
  - [Switches](#switches)
- [Remaining differences from PowerShell](#remaining-differences-from-powershell)
- [How it is built](#how-it-is-built)
- [Enforcing checks](#enforcing-checks)
- [Decisions](#decisions)

## Overview

PowerShell shows PSReadLine's ListView — history predictions in a list under the line, filtered as you type, with a live `<i/N>` position header. The zsh side mirrors it with a ListView dev-shell draws and drives itself in the Zsh line editor — **no plugin**. This is the contract both sides are held to, the few differences that remain, and where each ruling is enforced. Rulings by Karl on 2026-08-23/24; a change here lands in the same commit as the code.

## The contract

### What the list shows

- Matching history appears **as you type, from the first character**, up to **ten** `> line` rows under a `<i/N>  <History(i/N)>` heading; nothing on an empty prompt.
- The typed text is matched as a **case-insensitive substring**; **prefix matches rank first**, then the rest, each **newest first**. No duplicates, no multi-line commands, and no line no longer than what you typed (it would add nothing) — the same cut PSReadLine makes.
- **Control characters are shown printable** (an ESC becomes `^[`), so a history line's own colour codes cannot repaint the list.
- The list is the prediction display — its top row is the suggestion. Where zsh-autosuggestions is loaded, its inline grey ghost is **turned off** while the list is active, so the two do not fight over the space (PowerShell's ListView likewise has no inline ghost).

### Keys

| Key | Effect |
|---|---|
| **Down** | select the next row; the line becomes that history entry; the header advances (`<1/N>`, `<2/N>`, …) |
| **Up** | select the previous row; **from the first row, return to the line you typed** with its cursor (the header shows `<-/N>`) — PSReadLine's original item, no extra row |
| Down past the last row / Up past the first | wrap through the typed line |
| **Enter** | run the current line (the selected entry, or what you typed) |
| **Esc** | dismiss the list and restore the typed line |
| **Tab** | open the project menu; the history list gives way to it |
| typing / editing | re-filters; selection resets to the typed line |
| Left / Right / Home / End | move the cursor (the list stays) |

Without `DEV_SHELL_KEYS` (set to 0), Up/Down/Esc keep their zsh defaults and the list still renders as a passive preview.

### Colours

- The **matched text** and the **selected row** are in the accent (`DEV_SHELL_ACCENT`, default 214, bold) — PowerShell's `Emphasis` and `ListPredictionSelected`. The `> ` marker and the heading are the metadata grey (`fg=244`). No background box.

### Switches

- `DEV_SHELL_UX=0`: no list and no menu styling (just the `dev` command); if zsh-autosuggestions is loaded its ghost is left on.
- `DEV_SHELL_KEYS=0`: the list renders but Up/Down/Esc stay at their zsh defaults.
- `DEV_SHELL_ACCENT`: the 256-colour index for the match and the selection.

## Remaining differences from PowerShell

- **Esc within ~30 ms of the next keystroke** can be read as the start of a key sequence rather than a lone Esc (dev-shell peeks after Esc to tell an arrow from a bare Esc). At human speed this never bites; only a machine typing instantly after Esc would.
- **Matching is a plain case-insensitive substring**, where PSReadLine's predictor has extra ranking heuristics; dev-shell keeps it to prefix-first, newest-first.

Everything else — the rows, the live `<i/N>` header that tracks the selection, the typed line restored on Up with no phantom row, the accent colours — matches.

## How it is built

Three layers in `zsh/dev-shell.zsh`, so each stays simple and testable:

- **Engine** (`_dev_hl_search`, `_dev_hl_move`) — pure logic over the history and the selection state (`_dev_hl_matches`, `_dev_hl_sel` where −1 is the typed line, `_dev_hl_top` for the scroll window). `_dev_hl_search` does the substring/prefix/newest-first/dedup match capped at `_DEV_HL_MAX`; `_dev_hl_move` walks the selection through the virtual list `[query, match0…]` with wrapping and scrolls the window. No terminal needed — unit-tested in plain zsh.
- **Renderer** (`_dev_hl_render`) — a pure function of that state: builds `POSTDISPLAY` (the `<i/N>…<History(i/N)>` heading, right-spread, and the visible window of `> row`s) and the `region_highlight` entries (marker and heading grey, match and selected row in the accent). Offsets index the combined buffer + POSTDISPLAY. It clears its own highlights by **offset** — everything at or past the buffer length — because ZLE 5.8 strips the `memo` tag that would otherwise mark them; this is what stopped the earlier "random colouring" from stale entries piling up.
- **Controller** — the ZLE widgets and the `line-pre-redraw` hook (`_dev_hl_hook`). The hook decides **from which widget just fired**, never by comparing the buffer: an editing widget re-searches from the buffer (query reset), the list's own navigation and cursor moves just redraw, and completion/accept/history hide the list. `_dev_hl_down`/`_dev_hl_up` move the selection and copy it onto the line (restoring the typed line at −1); `_dev_hl_escape` peeks the byte after Esc to dispatch an arrow versus dismiss on a lone Esc; `_dev_hl_tab` suspends the list (until the next edit) so the project menu owns the screen. zsh-autosuggestions' ghost is suppressed while the list is on (`_ZSH_AUTOSUGGEST_DISABLED`, checked by existence).

This split is what makes the widget-gated recompute possible — the old plugin-based version compared the buffer to guess "did the user edit?", which raced with nav-set buffers and corrupted the selection.

## Enforcing checks

The **engine and renderer** are unit-tested in plain zsh by `tests/engine.test.zsh` (search order, dedup, the query-length cut, selection wrap, the highlight offsets landing on the right text, the scroll window) — no terminal, so the core is provably solid. The **controller** is checked live by `tests/zsh-ux.probe.py`, driven by `tests/install-sh.test.sh` B14 (`full`, keys on) and B15 (`nokeys`). It drives an interactive zsh through a pty and renders the real terminal grid with a small VT emulator, so overlapping redraws resolve to the final screen. Named checks:

| Ruling | Check |
|---|---|
| nothing on an empty prompt; rows from the first characters, prefix-first, no numbers | `no history list on the empty prompt`, `'pw' lists matching history rows as '> line'`, `prefix match ranks before the substring match`, `no event numbers on the rows` |
| live header | `heading shows <-/N> with the match count`, `Down selects the first row (header <1/2>…)`, `Down again advances the selection (header <2/2>)`, `Up walks back (header <1/2>)`, `Up from the first row returns to the typed line (header <-/2>)` |
| Enter runs; virtual original | `Down + Enter runs the first (prefix) match 'pwd'`, `Down then Up + Enter runs the typed line 'pw' (virtual original)` |
| Esc | `Esc dismisses the list (header gone)`, `Esc restored the typed line: the run line was 'pwX'` |
| colours | `matched text highlighted in the accent`, `Down selects the first row … row in the accent` |
| raw escapes | `raw ANSI escapes in history do not bleed into the list` |
| Tab menu coexists | `'dev ' lists the history rows starting with it`, `Tab opens the PROJECT menu…`, `Tab hides the history list (no <History> heading with the menu)` |
| no plugin; cd quiet | `dev-shell needs no plugin (the ListView render is dev-shell's own function)`, `cd does not error` |
| keys off | B15 `nokeys: Up/Down/Esc are not bound to the list widgets` (and the list-content checks run in this mode too) |

## Decisions

- 2026-08-23 — a history list as you type, chosen for PSReadLine parity over an fzf Ctrl-R list.
- 2026-08-24 — after Karl's feedback that a plugin-based list could not track the header or restore the line, dev-shell **draws and drives its own ListView** in ZLE (dropping zsh-autocomplete): a live `<i/N>` header, the typed line as a real virtual original (Up restores it, no phantom row), Esc to dismiss. The PowerShell `dev` menu shows one `name │ on branch` row per project to match.
- 2026-08-24 — the ListView is the prediction display; zsh-autosuggestions' inline ghost is **suppressed while the list is on** (they conflict for `POSTDISPLAY`, and PowerShell's ListView has no inline ghost). The plugin stays installed for `DEV_SHELL_UX=0`.
