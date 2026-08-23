#!/usr/bin/env python3
"""Drive an interactive zsh through a pty and check dev-shell's line UX.

usage: zsh-ux.probe.py HOME plugin|fallback
  HOME must hold a .zshrc that sources dev-shell (with zsh-autocomplete for
  'plugin', with history-substring-search widgets for 'fallback'), a
  .zsh_history with 'dev reader', 'dev api -c', 'pwd', and a DEV_ROOT with the
  short-named projects 'api' and 'web' (web being a git repo on feat/x).
Prints PASS/FAIL lines and a RESULT line; exits 1 on any failure.
"""
import os, pty, re, select, sys, time

home, mode = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    os.environ["HOME"] = home
    os.environ["TERM"] = "xterm-256color"
    os.environ["LINES"] = "40"
    os.environ["COLUMNS"] = "100"
    for k in ("ZDOTDIR", "ZSH", "ZSH_CUSTOM"):
        os.environ.pop(k, None)
    os.chdir(home)
    os.execvp("zsh", ["zsh", "-il"])

def drain(seconds):
    buf = b""
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.1)
        if fd not in ready:
            continue
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        buf += data
    return buf

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07|\x1b[=>]|\x1b\([AB]")
def clean(raw):
    return ANSI.sub("", raw.decode("utf-8", "replace")).replace("\r", "")

def rows(text):
    """History-list rows: an event number, two spaces, the line."""
    return [l.strip() for l in text.split("\n") if re.search(r"(?:^|\s)\d+\s{2}\S", l)]

def send(keys, wait):
    os.write(fd, keys)
    raw = drain(wait)
    return raw, clean(raw)

# The marker is split in the typed text ("MA""RK") so the echo of the command
# never contains it; only the printed result does.
def query(zsh_expr):
    _, text = send(b'print -r -- "MA""RK:' + zsh_expr + b'"\n', 2.0)
    m = re.search(r"^MARK:(.*)$", text, re.M)
    return m.group(1) if m else ""

passed = failed = 0
def check(name, cond, context=""):
    global passed, failed
    print(("  PASS: " if cond else "  FAIL: ") + name)
    if cond:
        passed += 1
        return
    failed += 1
    for line in context.split("\n")[-12:]:
        print("    |" + line.rstrip()[:110])

start = clean(drain(4.0))
check("startup prints a prompt", "PS> " in start, start)

if mode == "plugin":
    check("no history list on the empty prompt", not rows(start), start)

    raw, text = send(b"dev ", 2.5)
    check("'dev ' lists the history rows starting with it",
          any("dev reader" in r for r in rows(text)) and any("dev api -c" in r for r in rows(text)), text)

    raw, text = send(b"\t", 2.0)
    check("Tab opens the PROJECT menu, header not truncated by short names", "PROJECT  │ BRANCH" in text, text)
    check("menu lists the projects with the branch column", "api" in text and "on feat/x" in text, text)
    check("selected project row in the accent", b"\x1b[1;38;5;214m" in raw, text)

    send(b"\x1b[B", 1.0)   # Down: next project
    raw, text = send(b"\r", 2.0)
    send(b"\x15", 1.0)
    check("Enter in the project menu accepts only (line not run: still in $HOME)",
          "no such project" not in text and query(b"$PWD") == home, text)
    raw, text = send(b"pw", 2.5)
    check("recolour survives a Tab earlier on the line (hook kept)", b"\x1b[1;38;5;214m" in raw and b"30;103" not in raw, repr(raw[-300:]))
    send(b"\x15", 1.0)

    raw, text = send(b"pw", 2.5)
    check("'pw' lists the history row 'pwd'", any("pwd" in r for r in rows(text)), text)
    check("match recoloured to the accent, no black-on-yellow", b"\x1b[1;38;5;214m" in raw and b"30;103" not in raw, repr(raw[-300:]))
    raw, text = send(b"\x1b[B", 1.5)
    check("Down: selected history row carries the accent", b"\x1b[1;38;5;214m" in raw, repr(raw[-300:]))
    raw, text = send(b"\x1b", 1.5)
    check("Esc leaves the list without running it (no pwd output)", home not in text, text)
    raw, text = send(b"d", 2.0)
    check("typing continues after Esc (pwd row listed again)", any("pwd" in r for r in rows(text)), text)
    send(b"\x15", 1.0)
    raw, text = send(b"pw", 2.5)
    send(b"\x1b[B", 1.5)
    raw, text = send(b"\r", 2.5)
    check("Down + Enter runs the picked history line (pwd output + new prompt)", home in text and "PS> " in text, text)

    send(b"dev", 1.5)
    raw, text = send(b"\x1b[A", 2.5)
    check("Up opens the history menu filtered by the typed prefix",
          any("dev reader" in r for r in rows(text)) and any("dev api -c" in r for r in rows(text)), text)
    raw, text = send(b"\r", 2.5)
    check("Enter in the Up history menu runs the selected line (new prompt)", "PS> " in text, text)
    send(b"\x15", 1.0)

    send(b"dev ", 2.0)
    send(b"\x12", 2.0)      # Ctrl-R: this line's live list becomes completions
    raw, text = send(b"\x1b[B", 2.0)
    check("after Ctrl-R, Down enters the live completion list (PROJECT table)", "PROJECT  │ BRANCH" in text, text)
    raw, text = send(b"\r", 2.0)
    send(b"\x15", 1.0)
    check("Enter there accepts only (line not run: still in $HOME)", "no such project" not in text and query(b"$PWD") == home, text)

    binds = query(b"$(bindkey '^[OA')|$(bindkey '^[[A')|$(bindkey '^[OB')|$(bindkey '^[[B')|$(bindkey '^I')|$(bindkey -M menuselect '^M')")
    check("Up (both forms) -> _dev_history_menu", binds.count("_dev_history_menu") == 2, binds)
    check("Down (both forms) -> _dev_list_select", binds.count("_dev_list_select") == 2, binds)
    check("Tab -> _dev_menu_complete", "_dev_menu_complete" in binds, binds)
    check("menuselect Enter is accept-line or .accept-line (set by the menu opener)", "accept-line" in binds.split("|")[-1], binds)
    styles = query(b"$(zstyle -L ':completion:*' menu)|$(zstyle -L ':autocomplete:*' min-input)|$(zstyle -L ':autocomplete:*' default-context)|$(zstyle -L ':autocomplete:history-incremental-search-backward:*' list-lines)|$([[ -o hist_find_no_dups ]] && print on)")
    check("no 'menu' zstyle from dev-shell with the plugin", "menu select" not in styles, styles)
    check("min-input 1, history default-context, 10 list-lines, hist_find_no_dups",
          "min-input 1" in styles and "history-incremental-search-backward" in styles and "list-lines 10" in styles and styles.endswith("on"), styles)

    # Last, since the cd lands in history and would be picked by the Up menu above.
    raw, text = send(b"cd dev\r", 2.5)
    check("cd does not trip the plugin's recent-dirs hook (data dir created)", "chpwd_recent" not in text and "no such file" not in text, text)
else:
    binds = query(b"$(bindkey '^[OA')|$(bindkey '^[[A')|$(bindkey '^[OB')|$(bindkey '^[[B')|$(bindkey '^I')")
    check("fallback: Up (both forms) -> history-substring-search-up", binds.count("history-substring-search-up") == 2, binds)
    check("fallback: Down (both forms) -> history-substring-search-down", binds.count("history-substring-search-down") == 2, binds)
    check("fallback: Tab stays expand-or-complete", "expand-or-complete" in binds, binds)
    styles = query(b"$(zstyle -L ':completion:*' menu)")
    check("fallback: 'menu select' zstyle set", "menu select" in styles, styles)
    raw, text = send(b"dev \t", 2.5)
    check("fallback: Tab menu shows the PROJECT header, not truncated by short names", "PROJECT  │ BRANCH" in text, text)
    raw, text = send(b"\t", 1.5)   # zsh's auto_menu: the second Tab starts menu selection
    check("fallback: second Tab selects a row in the accent", b"\x1b[1;38;5;214m" in raw, text)
    send(b"\x07\x15", 1.0)

send(b"exit\n", 1.0)
try:
    os.waitpid(pid, 0)
except ChildProcessError:
    pass
print(f"RESULT({mode}): {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
