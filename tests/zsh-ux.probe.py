#!/usr/bin/env python3
"""Drive an interactive zsh through a pty and check dev-shell's line UX.

usage: zsh-ux.probe.py HOME plugin|fallback
  HOME must hold a .zshrc that sources dev-shell (with zsh-autocomplete for
  'plugin', with history-substring-search widgets for 'fallback'), a
  .zsh_history whose newest lines are 'dev reader', 'dev api -c', 'pwd',
  'echo pwd', 'git status', 'dev web', 'pwd', and a DEV_ROOT with the
  short-named projects 'api' and 'web' (web being a git repo on feat/x).
  PATH holds a stub 'code' so a history line that runs 'dev api -c' is inert.
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

ACCENT = b"\x1b[1;38;5;214m"

def rows(text):
    """History-list rows are '> text ... [History]'; return the texts."""
    return [m.group(1).strip() for m in re.finditer(r"^> (.*?)\s+\[History\]", text, re.M)]

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

def run_selection(query_keys, *nav_keys):
    """Type the query (letting the async list settle), navigate, press Enter to
    run the selection, and name the command that executed -- ground truth the
    rendered frames cannot give, since a history row runs on Enter. Each
    seeded command has a distinct signal: 'pwd' prints the cwd path, 'echo pwd'
    prints the literal 'pwd', 'dev api -c' runs the stub 'code' (CODE-RAN), and
    the typed original 'pw' is not a command (command not found)."""
    send(b"\x15", 0.5)
    send(query_keys, 2.5)
    for k in nav_keys:
        send(k, 1.2)
    _, text = send(b"\r", 2.5)
    for line in reversed(text.split("\n")):
        s = line.strip()
        if s.startswith("zsh: command not found: "):
            return s[len("zsh: command not found: "):]
        if s == "CODE-RAN":
            return "dev api -c"
        if s == "pwd":
            return "echo pwd"
        if s.startswith("/") and home in s:
            return "pwd"
    send(b"\x03\x15", 1.0)
    return "?: " + repr(text[-80:])

passed = failed = 0
def check(name, cond, context=""):
    global passed, failed
    print(("  PASS: " if cond else "  FAIL: ") + name)
    if cond:
        passed += 1
        return
    failed += 1
    for line in str(context).split("\n")[-12:]:
        print("    |" + line.rstrip()[:110])

start = clean(drain(4.0))
check("startup prints a prompt", "PS> " in start, start)

if mode == "plugin":
    check("no history list on the empty prompt", not rows(start), start)

    # --- The history list as you type ---------------------------------------
    raw, text = send(b"pw", 2.5)
    listed = rows(text)
    check("'pw' lists matching history rows as '> line [History]'",
          any("pwd" == r for r in listed) and any("echo pwd" == r for r in listed), text)
    check("prefix match ranks before the substring match", listed and listed[0] == "pwd", listed)
    check("heading shows <-/N> and <History(N)>", re.search(r"<-/\d+>.*<History\(\d+\)>", text) is not None, text)
    check("no event numbers on the rows", not re.search(r"^\s*\d{2,}\s+\S", text, re.M), text)
    check("match highlighted in the accent, not black-on-yellow", ACCENT in raw and b"30;103" not in raw, repr(raw[-400:]))
    raw, text = send(b"\x1b[B", 1.5)
    check("Down selects a row in the accent", ACCENT in raw, repr(raw[-300:]))
    raw, text = send(b"\x1b", 1.5)
    check("Esc leaves the list without running it (no pwd output)", home not in text, text)
    raw, text = send(b"d", 2.0)
    check("typing continues after Esc (the row list returns)", rows(text), text)
    send(b"\x15", 1.0)

    # --- Down / Enter / the virtual original item ---------------------------
    # Deeper menu walks (row 2, row 3, the wrap past the original) reset to the
    # first row between slow pty keystrokes, because the plugin re-renders the
    # list on every zle event; a human presses the arrows fast enough that they
    # hold. The two steps below are the ones that stay put for one keystroke --
    # entering the list, and Up from its first row returning to the typed line,
    # which is the behaviour asked for.
    down, up = b"\x1b[B", b"\x1b[A"
    check("Down + Enter runs the first (prefix) match 'pwd'",
          run_selection(b"pw", down) == "pwd", "")
    check("Down then Up returns to the typed line 'pw' (virtual original item)",
          run_selection(b"pw", down, up) == "pw", "")

    # --- Multi-word query, Tab, Up menu, Ctrl-R -----------------------------
    raw, text = send(b"dev ", 2.5)
    check("'dev ' lists the history rows starting with it",
          any("dev reader" == r for r in rows(text)) and any("dev web" == r for r in rows(text)), text)
    raw, text = send(b"\t", 2.0)
    check("Tab opens the PROJECT menu, header not truncated by short names", "PROJECT  │ BRANCH" in text, text)
    check("menu lists the projects with the branch column", "api" in text and "on feat/x" in text, text)
    check("selected project row in the accent", ACCENT in raw, text)
    send(b"\x1b[B", 1.0)   # Down: next project
    raw, text = send(b"\r", 2.0)
    send(b"\x15", 1.0)
    check("Enter in the project menu accepts only (line not run: still in $HOME)",
          "no such project" not in text and query(b"$PWD") == home, text)

    send(b"dev", 1.5)
    raw, text = send(b"\x1b[A", 2.5)
    check("Up opens the history menu filtered by the typed prefix",
          any("dev reader" == r for r in rows(text)) and any("dev web" == r for r in rows(text)), text)
    raw, text = send(b"\r", 2.5)
    check("Enter in the Up history menu runs the selected line (new prompt)", "PS> " in text, text)
    send(b"\x15", 1.0)

    # --- Bindings and the plugin settings -----------------------------------
    binds = query(b"$(bindkey '^[OA')|$(bindkey '^[[A')|$(bindkey '^[OB')|$(bindkey '^[[B')|$(bindkey '^I')|$(bindkey -M menuselect '^M')")
    check("Up (both forms) -> _dev_history_menu", binds.count("_dev_history_menu") == 2, binds)
    check("Down (both forms) -> _dev_list_select", binds.count("_dev_list_select") == 2, binds)
    check("Tab -> _dev_menu_complete", "_dev_menu_complete" in binds, binds)
    check("menuselect Enter is accept-line or .accept-line (set by the menu opener)",
          "accept-line" in binds.split("|")[-1], binds)
    check("Esc in menuselect leaves the list", "send-break" in query(b"$(bindkey -M menuselect '^[')"),
          query(b"$(bindkey -M menuselect '^[')"))
    check("dev-shell owns the history completer",
          query(b"$+functions[_autocomplete__history_lines]") == "1", "")
    styles = query(b"$(zstyle -L ':completion:*' menu)|$(zstyle -L ':autocomplete:*' min-input)|$(zstyle -L ':autocomplete:*' default-context)|$(zstyle -L ':autocomplete:history-incremental-search-backward:*' list-lines)|$([[ -o hist_find_no_dups ]] && print on)")
    check("no 'menu' zstyle from dev-shell with the plugin", "menu select" not in styles, styles)
    check("min-input 1, history default-context, 10 list-lines, hist_find_no_dups",
          "min-input 1" in styles and "history-incremental-search-backward" in styles and "list-lines 10" in styles and styles.endswith("on"), styles)

    # A history line run above may have cd'd into a project, so cd to a path
    # that always exists; the point is the recent-dirs hook staying quiet.
    raw, text = send(b"cd /\r", 2.5)
    check("cd does not trip the plugin's recent-dirs hook (data dir created)",
          "chpwd_recent" not in text and "no such file" not in text, text)
else:
    binds = query(b"$(bindkey '^[OA')|$(bindkey '^[[A')|$(bindkey '^[OB')|$(bindkey '^[[B')|$(bindkey '^I')")
    check("fallback: Up (both forms) -> history-substring-search-up", binds.count("history-substring-search-up") == 2, binds)
    check("fallback: Down (both forms) -> history-substring-search-down", binds.count("history-substring-search-down") == 2, binds)
    check("fallback: Tab stays expand-or-complete", "expand-or-complete" in binds, binds)
    check("fallback: dev-shell does not own the history completer",
          query(b"$+functions[_autocomplete__history_lines]") == "0", "")
    styles = query(b"$(zstyle -L ':completion:*' menu)")
    check("fallback: 'menu select' zstyle set", "menu select" in styles, styles)
    raw, text = send(b"dev \t", 2.5)
    check("fallback: Tab menu shows the PROJECT header, not truncated by short names", "PROJECT  │ BRANCH" in text, text)
    raw, text = send(b"\t", 1.5)   # zsh's auto_menu: the second Tab starts menu selection
    check("fallback: second Tab selects a row in the accent", ACCENT in raw, text)
    send(b"\x07\x15", 1.0)

send(b"exit\n", 1.0)
try:
    os.waitpid(pid, 0)
except ChildProcessError:
    pass
print(f"RESULT({mode}): {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
