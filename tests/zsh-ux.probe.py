#!/usr/bin/env python3
"""Drive an interactive zsh through a pty and check dev-shell's line UX.

usage: zsh-ux.probe.py HOME full|nokeys
  HOME holds a .zshrc that sources dev-shell (no plugin needed; zsh-
  autosuggestions optional), a .zsh_history whose newest lines are
  'dev reader', 'dev api -c', 'pwd', 'echo pwd', 'git status', 'dev web',
  'pwd' and a raw-escape line, and a DEV_ROOT with the short-named projects
  'api' and 'web' (web a git repo on feat/x). PATH holds a stub 'code' that
  prints CODE-RAN, so a history line running 'dev api -c' is inert and visible.
    full   - DEV_SHELL_KEYS=1: Up/Down/Esc drive the history list
    nokeys - DEV_SHELL_KEYS=0: the list still shows, keys stay zsh defaults

A small VT emulator renders the actual terminal grid, so overlapping redraws
resolve to the final screen rather than a scraped byte stream. Colour is checked
on the raw bytes (the accent SGR appearing at all). Exits 1 on any failure.
"""
import os, pty, re, select, signal, sys, time

home, mode = sys.argv[1], sys.argv[2]
COLS, LINESN = 95, 40

pid, fd = pty.fork()
if pid == 0:
    os.environ["HOME"] = home
    os.environ["TERM"] = "xterm-256color"
    os.environ["LINES"] = str(LINESN)
    os.environ["COLUMNS"] = str(COLS)
    os.environ["PATH"] = home + "/bin:/usr/bin:/bin"
    for k in ("ZDOTDIR", "ZSH", "ZSH_CUSTOM"):
        os.environ.pop(k, None)
    os.chdir(home)
    os.execvp("zsh", ["zsh", "-il"])

class Screen:
    """Minimal VT: enough of the cursor/erase repertoire zsh and dev-shell emit
    that the final grid matches what a person would see."""
    def __init__(self):
        self.grid = [[" "] * COLS for _ in range(LINESN)]
        self.r = self.c = 0
    def _cell(self):
        while self.r >= LINESN:
            self.grid.pop(0)
            self.grid.append([" "] * COLS)
            self.r -= 1
    def feed(self, data):
        i, n = 0, len(data)
        while i < n:
            ch = data[i]
            if ch == "\x1b":
                i = self._esc(data, i)
                continue
            if ch == "\r":
                self.c = 0
            elif ch == "\n":
                self.r += 1; self._cell()
            elif ch == "\b":
                self.c = max(0, self.c - 1)
            elif ch == "\t":
                self.c = min(COLS - 1, (self.c // 8 + 1) * 8)
            elif ch == "\x07":
                pass
            elif ord(ch) >= 32:
                self._cell()
                if self.c >= COLS:
                    self.c = 0; self.r += 1; self._cell()
                self.grid[self.r][self.c] = ch
                self.c += 1
            i += 1
    def _esc(self, data, i):
        n = len(data)
        if i + 1 >= n:
            return n
        nxt = data[i + 1]
        if nxt == "]":                       # OSC ... BEL/ST
            j = i + 2
            while j < n and data[j] != "\x07":
                if data[j] == "\x1b" and j + 1 < n and data[j + 1] == "\\":
                    j += 1; break
                j += 1
            return j + 1
        if nxt in "=>":
            return i + 2
        if nxt in "([":
            if nxt == "(":
                return i + 3
            # CSI
            j = i + 2
            params = ""
            while j < n and (data[j].isdigit() or data[j] == ";" or data[j] == "?"):
                params += data[j]; j += 1
            if j >= n:
                return n
            final = data[j]
            self._csi(params, final)
            return j + 1
        return i + 2
    def _csi(self, params, final):
        nums = [int(x) for x in params.split(";") if x.isdigit()] if params and not params.startswith("?") else []
        a = nums[0] if nums else 0
        if final == "H" or final == "f":
            self.r = (nums[0] - 1) if len(nums) >= 1 else 0
            self.c = (nums[1] - 1) if len(nums) >= 2 else 0
            self.r = max(0, self.r); self.c = max(0, self.c); self._cell()
        elif final == "A": self.r = max(0, self.r - max(1, a))
        elif final == "B": self.r += max(1, a); self._cell()
        elif final == "C": self.c = min(COLS - 1, self.c + max(1, a))
        elif final == "D": self.c = max(0, self.c - max(1, a))
        elif final == "G": self.c = max(0, (a - 1) if a else 0)
        elif final == "d": self.r = max(0, (a - 1) if a else 0); self._cell()
        elif final == "J":
            self._cell()
            if a == 2:
                self.grid = [[" "] * COLS for _ in range(len(self.grid))]
            elif a == 1:
                for rr in range(self.r):
                    self.grid[rr] = [" "] * COLS
                for cc in range(self.c + 1):
                    self.grid[self.r][cc] = " "
            else:
                for cc in range(self.c, COLS):
                    self.grid[self.r][cc] = " "
                for rr in range(self.r + 1, len(self.grid)):
                    self.grid[rr] = [" "] * COLS
        elif final == "K":
            self._cell()
            if a == 2:
                self.grid[self.r] = [" "] * COLS
            elif a == 1:
                for cc in range(self.c + 1):
                    self.grid[self.r][cc] = " "
            else:
                for cc in range(self.c, COLS):
                    self.grid[self.r][cc] = " "
        # SGR (m) and everything else: ignore for layout
    def lines(self):
        return [("".join(row)).rstrip() for row in self.grid]

SCREEN = Screen()

def drain(seconds):
    buf = b""
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.08)
        if fd not in ready:
            continue
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        buf += data
    if buf:
        SCREEN.feed(buf.decode("utf-8", "replace"))
    return buf

def visible():
    return [ln for ln in SCREEN.lines() if ln.strip()]

def current():
    """The current prompt line and everything the list drew below it."""
    grid = SCREEN.lines()
    last = max((i for i, ln in enumerate(grid) if "PS>" in ln), default=0)
    return [ln for ln in grid[last:] if ln.strip()]

ACCENT = b"\x1b[38;5;214"          # region_highlight emits the accent as fg=214

def send(keys, wait):
    os.write(fd, keys)
    raw = drain(wait)
    return raw, visible()

def header(lines):
    for ln in lines:
        m = re.search(r"[<(](-|\d+)/(\d+)[)>]", ln)
        if m:
            return "<%s/%s>" % (m.group(1), m.group(2))
    return None

def rows(lines):
    return [ln[2:].strip() for ln in lines if ln.startswith("> ")]

def type_list(keys, wait=1.6):
    """Type a query and wait for the async-free list to settle in view."""
    os.write(fd, keys)
    raw = drain(wait)
    for _ in range(3):
        if header(current()) is not None:
            break
        raw += drain(0.8)
    return raw, current()

def query(zsh_expr):
    _, lines = send(b'print -r -- "MA""RK:' + zsh_expr + b'"\n', 2.0)
    for ln in lines:
        m = re.search(r"MARK:(.*)$", ln)
        if m:
            return m.group(1)
    return ""

def run_selection(query_keys, *nav_keys):
    send(b"\x15", 0.4)
    send(query_keys, 1.4)
    for k in nav_keys:
        send(k, 0.6)
    _, lines = send(b"\r", 2.0)
    for ln in reversed(lines):
        s = ln.strip()
        if s.startswith("zsh: command not found: "):
            return s[len("zsh: command not found: "):]
        if s == "CODE-RAN":
            return "dev api -c"
        if s == "pwd":
            return "echo pwd"
        if s.startswith("/") and home in s:
            return "pwd"
    send(b"\x03\x15", 0.5)
    return "?"

passed = failed = 0
def check(name, cond, context=""):
    global passed, failed
    print(("  PASS: " if cond else "  FAIL: ") + name)
    if cond:
        passed += 1
        return
    failed += 1
    ctx = context if isinstance(context, str) else "\n".join(context)
    for line in ctx.split("\n")[-14:]:
        print("    |" + line.rstrip()[:100])

drain(4.0)
start = visible()
check("startup prints a prompt", any("PS>" in ln for ln in start), start)
check("no history list on the empty prompt", header(start) is None, start)

# A raw ANSI escape in a history line must not repaint the list: control bytes
# show as printable '^[' text, never re-emitted raw. Checked first, fresh shell.
os.write(fd, b"color")
raw = drain(2.5)
for _ in range(3):
    if b"<History" in raw:
        break
    raw += drain(1.5)
check("raw ANSI escapes in history do not bleed into the list",
      b"<History" in raw and b"\x1b[31m" not in raw and b"^[[31m" in raw, repr(raw[-400:]))
send(b"\x15", 0.6)

raw, lines = send(b"pw", 1.6)
listed = rows(lines)
check("'pw' lists matching history rows as '> line'",
      "pwd" in listed and "echo pwd" in listed, lines)
check("prefix match ranks before the substring match", listed[:1] == ["pwd"], listed)
check("heading shows <-/N> with the match count", header(lines) == "<-/2>", lines)
check("no event numbers on the rows", not any(re.match(r"\s*\d{2,}\s", ln) for ln in listed), lines)
check("matched text highlighted in the accent", ACCENT in raw, repr(raw[-300:]))

if mode == "full":
    raw, _ = send(b"\x1b[B", 1.0)
    check("Down selects the first row (header <1/2>, row in the accent)",
          header(current()) == "<1/2>" and ACCENT in raw, current())
    raw, _ = send(b"\x1b[B", 1.0)
    check("Down again advances the selection (header <2/2>)", header(current()) == "<2/2>", current())
    raw, _ = send(b"\x1b[A", 1.0)
    check("Up walks back (header <1/2>)", header(current()) == "<1/2>", current())
    raw, _ = send(b"\x1b[A", 1.0)
    check("Up from the first row returns to the typed line (header <-/2>)", header(current()) == "<-/2>", current())
    send(b"\x15", 0.5)

    check("Down + Enter runs the first (prefix) match 'pwd'",
          run_selection(b"pw", b"\x1b[B") == "pwd", "")
    check("Down then Up + Enter runs the typed line 'pw' (virtual original)",
          run_selection(b"pw", b"\x1b[B", b"\x1b[A") == "pw", "")

    # Esc restores the typed line and dismisses the list. (A char typed within
    # 30ms of Esc would be read as a sequence byte; the gaps here are larger.)
    send(b"\x15", 0.4)
    send(b"pw", 1.2)
    send(b"\x1b[B", 0.7)            # select a row (buffer becomes 'pwd')
    raw, _ = send(b"\x1b", 0.9)  # Esc
    check("Esc dismisses the list (header gone)", header(current()) is None, current())
    send(b"X", 0.7)
    _, lines = send(b"\r", 1.8)
    check("Esc restored the typed line: the run line was 'pwX'",
          any("command not found: pwX" in ln for ln in lines), lines)
else:
    binds = query(b"$(bindkey '^[[A')|$(bindkey '^[OA')|$(bindkey '^[[B')|$(bindkey '^[')")
    check("nokeys: Up/Down/Esc are not bound to the list widgets",
          "_dev_hl_up" not in binds and "_dev_hl_down" not in binds and "_dev_hl_escape" not in binds, binds)
    # The list itself still renders on typing -- that is the top-of-run
    # "'pw' lists ..." check, which runs in this mode too.
    send(b"\x15", 0.5)

# Tab opens the project menu; the history list gives way to it.
send(b"\x15", 0.4)
raw, devlines = type_list(b"dev ")
check("'dev ' lists the history rows starting with it",
      "dev reader" in rows(devlines) and "dev web" in rows(devlines), devlines)
raw, _ = send(b"\t", 1.6)
menu = current()
check("Tab opens the PROJECT menu, header not truncated by short names",
      any("PROJECT  │ BRANCH" in ln for ln in menu), menu)
check("menu lists the projects with the branch column",
      any("api" in ln for ln in menu) and any("on feat/x" in ln for ln in menu), menu)
check("Tab hides the history list (no <History> heading with the menu)",
      not any("<History" in ln for ln in menu), menu)
if mode == "full":
    raw, _ = send(b"\x1b[B", 1.0)      # navigate inside the project menu
    check("navigating the project menu keeps the history list hidden",
          not any("<History" in ln for ln in current()), current())
    send(b"\x07", 0.6)                  # Ctrl-G: leave the menu
    raw, _ = send(b"x", 1.2)           # an edit brings the list back
    check("an edit after the menu brings the history list back",
          any("<History" in ln for ln in current()), current())
send(b"\x07\x15", 0.6)

# Option completion is styled like the project menu (OPTION │ DESCRIPTION), the
# same _dev_two_col helper -- not compsys's "-- desc".
raw, _ = send(b"dev api -\t", 1.6)
optmenu = current()
check("option completion shows an OPTION │ DESCRIPTION header (│, not --)",
      any("OPTION" in ln and "│" in ln and "DESCRIPTION" in ln for ln in optmenu), optmenu)
check("option rows show the option and its description",
      any("--code" in ln for ln in optmenu) and any("VS Code" in ln for ln in optmenu), optmenu)
send(b"\x07\x15", 0.6)

check("dev-shell needs no plugin (the ListView render is dev-shell's own function)",
      query(b"$+functions[_dev_hl_hook]") == "1", "")
check("the two-column menu helper is shared (projects and options)",
      query(b"$+functions[_dev_two_col]") == "1", "")

raw, lines = send(b"cd /\r", 1.4)
check("cd does not error", not any("no such file" in ln or "chpwd" in ln for ln in lines), lines)

send(b"exit\n", 0.6)
try:
    os.kill(pid, signal.SIGKILL)
except ProcessLookupError:
    pass
print(f"RESULT({mode}): {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
