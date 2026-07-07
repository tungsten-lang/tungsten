"""flipfleet — a flip-graph matmul search with a live TUI and an exploit/explore
reseed strategy, plus per-new-best performance benchmarking.

STRATEGY ("converge", Erik 2026-07-06):
  * EXPLOIT — the instant the fleet finds a new best rank, every *other* walker is
    reseeded onto that new best (the walker that found it keeps going). The fleet
    piles onto the frontier.
  * EXPLORE — when a walker exhausts its own sawtooth (cal2zone2 CYCLEOUT after 4
    cycles with no descent), it is reseeded from a FRESH naive scheme instead of
    the best — re-injecting diversity so the fleet doesn't collapse onto one basin.
  Note (design caveat): reseed-all-on-best is aggressive exploitation and tends to
  converge fast — possibly onto the same wall (we watched reset-to-fleet-best pull
  all 18 walkers onto 101). The naive-wrap is the counter-pressure; the TUI lets
  you watch that exploit/explore tension live.

BENCHMARK: every new fleet best is scored for ACTUAL work, not just rank —
  ops = bits - rank - outputs  (base-case GF(2) op count, mults+adds)
  omega = log_n(rank)          (asymptotic recursion exponent)
so you can see whether descending rank is climbing or sliding the performance curve.

HOOKS: the search continuously writes <run_dir>/status.json and events.log. The
built-in curses TUI renders them; any other tool (or an agent) can read the same
files to watch progress.

Usage:
  python3 flipfleet.py [--walkers 18] [--secs 0] [--tui]     # run (+ optional TUI)
  python3 flipfleet.py --attach <run_dir>                    # TUI only, attach to a run
"""
import argparse
import glob
import json
import math
import os
import random
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
from bench_decomp import cost, parse_scheme, naive_scheme  # noqa: E402
from bucket_gen import gen as bucket_gen  # noqa: E402

N = M = P = 5
RECORD = 93
CAP_MOVES = 50_000_000_000_000          # INTEGER — a float cap emits a float literal and nan-boxes
RUN_DIR = os.path.join(HERE, "runs", "flipfleet_555")


# ---- scheme IO --------------------------------------------------------------
def write_dump(terms, path):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(f"{len(terms)}\n")
        for u, v, w in terms:
            f.write(f"{u} {v} {w}\n")
    os.replace(tmp, path)                 # atomic — no torn reads by the walker


def read_dump(path):
    try:
        lines = open(path).read().splitlines()
        rank = int(lines[0])
        terms = [tuple(int(x) for x in ln.split()) for ln in lines[1:1 + rank]]
        return (rank, terms) if len(terms) == rank else (None, None)
    except Exception:
        return None, None


def tail_has(path, needle, n=8):
    try:
        return any(needle in ln for ln in open(path).read().splitlines()[-n:])
    except Exception:
        return False


# ---- the search fleet -------------------------------------------------------
class Fleet:
    def __init__(self, run_dir, nwalkers, secs, strategy="converge", cycles=4):
        self.dir = run_dir
        self.nw = nwalkers
        self.secs = secs
        self.strategy = strategy
        self.cycles = cycles            # sawtooth cycles before a walker CYCLEOUTs -> reseed
        self.record = os.path.join(run_dir, "records")
        os.makedirs(run_dir, exist_ok=True)
        os.makedirs(self.record, exist_ok=True)
        for f in glob.glob(os.path.join(run_dir, "*")):
            if os.path.isfile(f):
                os.remove(f)
        self.status_path = os.path.join(run_dir, "status.json")
        self.events_path = os.path.join(run_dir, "events.log")
        self.curve_path = os.path.join(run_dir, "perf_curve.csv")
        self.events = []
        self.perf = []
        self.best = None                  # (rank, terms)
        self.reseeds = 0
        self.naive_wraps = 0
        self.new_bests = 0
        self.last_converge = 0.0
        self.procs = [None] * (nwalkers + 1)
        self.logs = {}
        self.launched_at = [0.0] * (nwalkers + 1)
        self.reseeded_at = [0.0] * (nwalkers + 1)

    def log(self, msg):
        line = f"[{time.strftime('%H:%M:%S')}] {msg}"
        self.events.append(line)
        self.events = self.events[-40:]
        with open(self.events_path, "a") as f:
            f.write(line + "\n")

    def reseed_file(self, i):
        return os.path.join(self.dir, f"reseed_{i}.txt")

    def dump_file(self, i):
        return os.path.join(self.dir, f"cpu_{i}.txt")

    def build_walker(self):
        binp = os.path.join(self.dir, "walker")
        src = bucket_gen(N, M, P, RECORD - 1, seed=None, cap=CAP_MOVES,
                         adaptive_esc="cal2zone2", band=1, thr0=7,
                         world_record=RECORD, tiegap=20000,
                         record_bandq=10_000_000_000, runtime_seed=True)
        open(binp + ".w", "w").write(src)
        r = subprocess.run(["bin/tungsten", "-o", binp, binp + ".w",
                            "--release", "--native", "--fast", "--lto"],
                           cwd=ROOT, capture_output=True, text=True, timeout=1200)
        if r.returncode != 0:
            raise RuntimeError("walker compile failed:\n" + r.stdout + r.stderr)
        self.bin = binp

    def launch(self, i, salt):
        if i in self.logs:
            try:
                self.logs[i].close()
            except Exception:
                pass
        lf = open(os.path.join(self.dir, f"cpu_{i}.log"), "a")
        self.logs[i] = lf
        self.procs[i] = subprocess.Popen(
            [self.bin, str(i * 97 + 13 + salt * 100003), self.dump_file(i),
             os.path.join(self.record, f"cpu{i}"), os.path.join(self.record, f"tie{i}"),
             self.reseed_file(i), str(self.cycles)],          # av0[5] = sawtooth cycles
            stdout=lf, stderr=subprocess.STDOUT)
        self.launched_at[i] = time.time()
        self.reseeded_at[i] = time.time()

    def score(self, rank, terms):
        c = cost(terms, N, M, P)
        return c

    def note_best(self, rank, terms, t):
        self.best = (rank, terms)
        self.new_bests += 1
        c = self.score(rank, terms)
        pt = {"t": round(t, 1), "rank": rank, "bits": c["bits"],
              "ops": c["ops"], "omega": round(c["omega"], 4)}
        self.perf.append(pt)
        with open(self.curve_path, "a") as f:
            if os.path.getsize(self.curve_path) == 0:
                f.write("t,rank,bits,ops,omega\n")
            f.write(f"{pt['t']},{rank},{c['bits']},{c['ops']},{pt['omega']}\n")
        self.log(f"NEW BEST rank={rank} bits={c['bits']} ops={c['ops']} omega={c['omega']:.3f}")
        # bank a copy of the record scheme
        write_dump(terms, os.path.join(self.record, f"best_rank{rank}.txt"))

    def run(self):
        self.log(f"flipfleet start: {self.nw} walkers, strategy={self.strategy}, "
                 f"cycles={self.cycles}, <{N},{M},{P}> record={RECORD}")
        self.build_walker()
        self.log("walker compiled (cal2zone2, band=1, --release --native --fast --lto)")
        naive = naive_scheme(N, M, P)
        self.best = (len(naive), naive)
        open(self.curve_path, "w").close()
        for i in range(1, self.nw + 1):
            write_dump(naive, self.reseed_file(i))
            self.launch(i, 0)
        self.log(f"launched {self.nw} walkers from naive (rank {len(naive)})")

        start = time.time()
        self.write_status(start, compiling=False)
        while self.secs == 0 or (time.time() - start) < self.secs:
            time.sleep(1.0)
            now = time.time()

            # -- find the fleet's current best across all dump files ----------
            best_rank, best_terms, finder = self.best[0], self.best[1], -1
            for i in range(1, self.nw + 1):
                rnk, trm = read_dump(self.dump_file(i))
                if rnk is not None and rnk < best_rank:
                    best_rank, best_terms, finder = rnk, trm, i

            # -- EXPLOIT: new fleet best -> reseed every OTHER walker onto it --
            if best_rank < self.best[0]:
                self.note_best(best_rank, best_terms, now - start)
                if now - self.last_converge > 3.0:      # debounce the fleet restart
                    self.last_converge = now
                    for i in range(1, self.nw + 1):
                        if i == finder:
                            continue
                        write_dump(best_terms, self.reseed_file(i))
                        if self.procs[i] and self.procs[i].poll() is None:
                            self.procs[i].kill()
                        self.launch(i, self.reseeds + 1)
                        self.reseeds += 1
                    self.log(f"EXPLOIT: reseeded {self.nw - 1} walkers onto rank {best_rank} "
                             f"(found by w{finder})")

            # -- EXPLORE: a walker exhausted its sawtooth (CYCLEOUT) -> naive --
            for i in range(1, self.nw + 1):
                pr = self.procs[i]
                if pr and pr.poll() is not None:
                    cyc = tail_has(os.path.join(self.dir, f"cpu_{i}.log"), "CYCLEOUT")
                    write_dump(naive_scheme(N, M, P), self.reseed_file(i))
                    self.launch(i, self.naive_wraps + self.reseeds + 1)
                    self.naive_wraps += 1
                    self.log(f"EXPLORE: w{i} {'CYCLEOUT' if cyc else 'exit'} -> "
                             f"fresh naive (wrap #{self.naive_wraps})")

            self.write_status(start, compiling=False)

        self.log("time box reached, stopping")
        for i in range(1, self.nw + 1):
            if self.procs[i]:
                self.procs[i].kill()
        self.write_status(start, done=True)

    def write_status(self, start, compiling=False, done=False):
        walkers = []
        for i in range(1, self.nw + 1):
            r, m = "?", 0
            try:
                for ln in reversed(open(os.path.join(self.dir, f"cpu_{i}.log")).read().splitlines()):
                    if ln.strip().startswith("mv="):
                        parts = dict(p.split("=") for p in ln.split() if "=" in p)
                        r, m = parts.get("best", "?"), int(parts.get("mv", 0))
                        break
            except Exception:
                pass
            walkers.append({"id": i, "rank": r, "mv": m,
                            "since_reseed": round(time.time() - self.reseeded_at[i], 0)})
        c = self.score(*self.best) if self.best else {}
        status = {
            "started": start, "elapsed": round(time.time() - start, 1),
            "done": done, "strategy": self.strategy, "format": f"{N}x{M}x{P}", "record": RECORD,
            "best": {"rank": self.best[0], "bits": c.get("bits"), "ops": c.get("ops"),
                     "omega": round(c.get("omega", float("nan")), 4)} if self.best else {},
            "walkers": walkers,
            "perf_curve": self.perf[-200:],
            "counters": {"reseeds": self.reseeds, "naive_wraps": self.naive_wraps,
                         "new_bests": self.new_bests},
            "events": self.events[-14:],
        }
        tmp = self.status_path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(status, f)
        os.replace(tmp, self.status_path)


# ---- the TUI ----------------------------------------------------------------
def spark(vals, lo=None, hi=None, width=40):
    if not vals:
        return ""
    blocks = "▁▂▃▄▅▆▇█"
    lo = min(vals) if lo is None else lo
    hi = max(vals) if hi is None else hi
    if hi == lo:
        hi = lo + 1
    vals = vals[-width:]
    return "".join(blocks[min(7, max(0, int((v - lo) / (hi - lo) * 7)))] for v in vals)


def tui(status_path):
    import curses

    def draw(scr):
        curses.curs_set(0)
        scr.nodelay(True)
        try:
            curses.start_color(); curses.use_default_colors()
            curses.init_pair(1, curses.COLOR_YELLOW, -1)
            curses.init_pair(2, curses.COLOR_GREEN, -1)
            curses.init_pair(3, curses.COLOR_CYAN, -1)
            curses.init_pair(4, curses.COLOR_RED, -1)
        except Exception:
            pass
        A = lambda n: curses.color_pair(n)
        while True:
            ch = scr.getch()
            if ch in (ord("q"), ord("Q")):
                break
            try:
                s = json.load(open(status_path))
            except Exception:
                s = None
            scr.erase()
            h, w = scr.getmaxyx()
            if not s:
                scr.addstr(0, 0, "waiting for status.json …")
                scr.refresh(); time.sleep(0.5); continue
            b = s.get("best", {})
            done = s.get("done")
            title = f" flipfleet  <{s['format']}> GF(2)   strategy={s['strategy']} "
            scr.addstr(0, 0, title[:w - 1], A(1) | curses.A_BOLD)
            st = "DONE" if done else "LIVE"
            scr.addstr(0, max(0, w - len(st) - 1), st, A(4 if done else 2) | curses.A_BOLD)
            om = f"{b.get('omega'):.3f}" if isinstance(b.get("omega"), float) else "-"
            gap = (b.get("rank", 0) - s["record"]) if b.get("rank") else "?"
            scr.addstr(2, 0, f" best rank ", A(3))
            scr.addstr(2, 11, f"{b.get('rank','?')}", A(2) | curses.A_BOLD)
            scr.addstr(2, 18, f" (+{gap} to record {s['record']})   ops={b.get('ops','?')}  "
                              f"bits={b.get('bits','?')}  ω={om}")
            c = s.get("counters", {})
            scr.addstr(3, 0, f" elapsed {s['elapsed']:.0f}s   new-bests {c.get('new_bests',0)}   "
                             f"reseeds {c.get('reseeds',0)}   naive-wraps {c.get('naive_wraps',0)}")

            # perf curve sparklines (rank down, ops)
            pc = s.get("perf_curve", [])
            row = 5
            if pc:
                ranks = [p["rank"] for p in pc]
                opss = [p["ops"] for p in pc]
                scr.addstr(row, 0, " rank  " + spark(ranks, width=w - 20) +
                           f"  {ranks[0]}→{ranks[-1]}", A(2))
                scr.addstr(row + 1, 0, " ops   " + spark(opss, width=w - 20) +
                           f"  {opss[0]}→{opss[-1]}", A(1))
                row += 3
            scr.addstr(row, 0, " walkers (rank · Bmoves · since-reseed s):", A(3))
            row += 1
            cols = max(1, (w - 2) // 26)
            for idx, wk in enumerate(s["walkers"]):
                rr, cc = row + idx // cols, 1 + (idx % cols) * 26
                if rr >= h - 14:
                    break
                atr = A(2) if str(wk["rank"]).isdigit() and int(wk["rank"]) <= s["record"] + 8 else 0
                scr.addstr(rr, cc, f"w{wk['id']:02d} {str(wk['rank']):>3} "
                                   f"{wk['mv']/1e9:>5.1f}B {int(wk['since_reseed']):>4}s"[:25], atr)
            ev_row = min(h - 13, row + (len(s["walkers"]) + cols - 1) // cols + 1)
            scr.addstr(ev_row, 0, " events:", A(3))
            for j, e in enumerate(s.get("events", [])[-min(11, h - ev_row - 2):]):
                scr.addstr(ev_row + 1 + j, 1, e[:w - 2],
                           A(2) if "NEW BEST" in e else (A(1) if "EXPLOIT" in e else 0))
            scr.addstr(h - 1, 0, " q to quit — data from status.json (also readable by other tools) ",
                       curses.A_DIM)
            scr.refresh()
            time.sleep(0.5)

    curses.wrapper(draw)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--walkers", type=int, default=18)
    ap.add_argument("--secs", type=int, default=0, help="0 = run until stopped")
    ap.add_argument("--cycles", type=int, default=4,
                    help="sawtooth cycles a walker runs before CYCLEOUT -> reseed")
    ap.add_argument("--dir", default=RUN_DIR)
    ap.add_argument("--tui", action="store_true", help="run the search AND show the TUI")
    ap.add_argument("--attach", metavar="RUN_DIR", help="TUI only, attach to an existing run")
    args = ap.parse_args()

    if args.attach:
        tui(os.path.join(args.attach, "status.json"))
        return

    fleet = Fleet(args.dir, args.walkers, args.secs, cycles=args.cycles)
    if args.tui:
        import threading
        t = threading.Thread(target=fleet.run, daemon=True)
        t.start()
        while not os.path.exists(fleet.status_path):
            time.sleep(0.3)
        tui(fleet.status_path)
    else:
        print(f"run dir: {args.dir}\nstatus:  {fleet.status_path}\nattach:  "
              f"python3 {os.path.basename(__file__)} --attach {args.dir}", flush=True)
        fleet.run()


if __name__ == "__main__":
    main()
