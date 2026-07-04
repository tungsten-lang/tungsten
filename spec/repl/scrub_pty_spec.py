#!/usr/bin/env python3
"""PTY regression tests for the compiled REPL's live scrubbing (bin/tungsten-compiler --wit).

These drive the REPL through a pseudo-terminal and replay the emitted bytes into
a tiny terminal-screen emulator, so they can assert on what is actually VISIBLE
on screen (in-place repaint vs. duplicated output) — something a raw byte stream
can't distinguish. Run from the repo root:  python3 spec/repl/scrub_pty_spec.py

Covers regressions reported against the inspector/scrub work:
  - `? <expr>` then blank-Enter scrubs the command line IN PLACE (no second copy).
  - scrubbing twice re-scrubs in place (does not reprint the whole inspection).
  - nudging updates the inspection in place (date rollover, IPv4 octets, clamps).
"""
import pty, os, time, select, re, struct, fcntl, termios, sys

BIN = "./bin/tungsten-compiler"
ESC = b"\x1b"
UP, DOWN, LEFT, RIGHT = ESC + b"[A", ESC + b"[B", ESC + b"[D", ESC + b"[C"


def run(cmds, settle=0.55, rows=50, cols=100):
    """Spawn the REPL under a PTY, feed `cmds`, return the raw output bytes."""
    pid, fd = pty.fork()
    if pid == 0:
        os.execv(BIN, [BIN, "--wit"])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    out = bytearray()

    def drain(t):
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try:
                    out.extend(os.read(fd, 8192))
                except OSError:
                    return

    drain(0.7)
    for c in cmds:
        os.write(fd, c)
        drain(settle)
    try:
        os.close(fd)
    except OSError:
        pass
    return bytes(out)


def screen(data):
    """Replay output bytes into a screen grid; return the final visible lines."""
    s = data.decode("utf-8", "replace")
    grid, row, col, maxrow, i = {}, 0, 0, 0, 0
    while i < len(s):
        c = s[i]
        if c == "\x1b":
            m = re.match(r"\x1b\[([0-9;?]*)([A-Za-z])", s[i:])
            if not m:
                i += 1
                continue
            arg, cmd = m.group(1), m.group(2)
            i += m.end()
            n = int(arg) if arg.isdigit() else 1
            if cmd == "A":
                row = max(0, row - n)
            elif cmd == "B":
                row += n
            elif cmd == "C":
                col += n
            elif cmd == "D":
                col = max(0, col - n)
            elif cmd == "J":  # erase cursor..end of screen
                for (r, cc) in list(grid):
                    if r > row or (r == row and cc >= col):
                        del grid[(r, cc)]
            elif cmd == "K":  # erase cursor..end of line
                for (r, cc) in list(grid):
                    if r == row and cc >= col:
                        del grid[(r, cc)]
            continue
        if c == "\r":
            col = 0
        elif c == "\n":
            row += 1
            maxrow = max(maxrow, row)
        else:
            grid[(row, col)] = c
            col += 1
            maxrow = max(maxrow, row)
        i += 1
    lines = []
    for r in range(maxrow + 1):
        cols = [cc for (rr, cc) in grid if rr == r]
        lines.append("".join(grid.get((r, cc), " ") for cc in range(max(cols) + 1)).rstrip() if cols else "")
    return lines


FAILS = []


def check(name, cond, detail=""):
    print(("PASS  " if cond else "FAIL  ") + name + (("  — " + detail) if detail and not cond else ""))
    if not cond:
        FAILS.append(name)


# ── 1. `? <date>` + blank-Enter scrubs the command line in place ────────────
lines = screen(run([b"? 2026-12-25\n", b"\n", b"q"]))
full = "\n".join(lines)
check("date inspect+scrub: exactly one inspection on screen (in place)",
      full.count("  result ") == 1, f"result lines={full.count('  result ')}")
check("date scrub: edits the `wit> ? 2026-12-25` command line (no `scrub>` copy)",
      any("? 2026-12-25" in l and "wit" in l for l in lines) and "scrub>" not in full,
      "command line not reused as the scrub header")

# ── 2. nudging updates the inspection in place (date rollover) ──────────────
lines = screen(run([b"? 2026-12-25\n", b"\n", UP, b"q"]))
full = "\n".join(lines)
check("date nudge: one inspection, day rolls 25->26 in place",
      full.count("  result ") == 1 and "[26]" in full and "day      bits 27..23  26" in full
      and "day      bits 27..23  25" not in full)

# ── 3. scrubbing TWICE re-scrubs in place (no reprint) ─────────────────────
lines = screen(run([b"? 2026-12-25\n", b"\n", b"q", b"\n", b"q"]))
full = "\n".join(lines)
check("scrub twice: still one inspection on screen (re-scrubbed in place)",
      full.count("  result ") == 1, f"result lines={full.count('  result ')}")

# ── 4. IPv4: four octets are independent fields, clamped 0..255 ────────────
lines = screen(run([b"scrub 192.168.1.1\n", UP, UP, LEFT, UP, b"q"]))
full = "\n".join(lines)
check("ipv4 scrub: last octet nudged twice, third octet once (192.168.2.3)",
      "192.168.2.3" in full, "octets not independently scrubbable")
lines = screen(run([b"scrub 1.2.3.255\n", UP, UP, b"q"]))
check("ipv4 scrub: octet clamps at 255 (no overflow)", "1.2.3.255" in "\n".join(lines))

# ── 5. numeric scrub re-evaluates live ─────────────────────────────────────
lines = screen(run([b"scrub 2 + 3\n", UP, UP, b"q"]))
full = "\n".join(lines)
check("numeric scrub: 2 + 3 -> 2 + 5 with result 7", "2 + 5" in full and "  result   7" in full)

# ── 6. `=` (unshifted +) nudges up just like `+` ───────────────────────────
lines = screen(run([b"scrub 2 + 3\n", b"=", b"=", b"q"]))
check("`=` key nudges up like `+` (2 + 3 -> 2 + 5)", "2 + 5" in "\n".join(lines))

# ── 7. non-holiday date reserves a blank subheader line (layout constant) ──
holiday = screen(run([b"? 2026-12-25\n", b"q"]))
plain = screen(run([b"? 2026-06-15\n", b"q"]))
def cal_offset(lines):
    for idx, l in enumerate(lines):
        if l.strip().startswith("Su   Mo"):
            return idx - next(i for i, x in enumerate(lines) if "result" in x)
    return None
check("non-holiday date keeps the calendar at the same offset as a holiday date",
      cal_offset(holiday) == cal_offset(plain), f"holiday={cal_offset(holiday)} plain={cal_offset(plain)}")
check("holiday date still shows the name (Christmas)", any("Christmas" in l for l in holiday))

# ── 8. July 4th shows the fireworks art panel ──────────────────────────────
lines = screen(run([b"? " + b"2026" + b"-07-04\n", b"q"]))
full = "\n".join(lines)
check("July 4th renders fireworks art (\\|/ … /|\\)", "\\|/" in full and "/|\\" in full)

# ── 9. 5-week month is padded to the same scene height as a 6-week month ────
def scene_height(expr):
    ls = screen(run([expr, b"q"]))
    top = next(i for i, l in enumerate(ls) if "result" in l)
    bot = next(i for i, l in enumerate(ls) if l.startswith("u0x"))
    return bot - top
h5 = scene_height(b"? 2026-12-25\n")   # December 2026 = 5 weeks
h6 = scene_height(b"? 2026-08-15\n")   # August 2026   = 6 weeks
check("5-week month padded to the same scene height as a 6-week month",
      h5 == h6, f"5-week={h5} 6-week={h6}")

print()
if FAILS:
    print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
    sys.exit(1)
print("all scrub PTY tests passed")
