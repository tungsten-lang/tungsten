"""Compare branching policies on the same native proof-producing Wassat kernel."""
import argparse
from collections import deque
import json
import math
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile

BIT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BIT / "competition"))
from check_output import check_output


def luby(index):
    level = (index + 1).bit_length() - 1
    if index + 1 == 1 << level:
        return 1 << (level - 1)
    return luby(index - (1 << level) + 1)


class BranchingPolicy:
    def __init__(self, name):
        self.name = name
        self.effort = [0, 0]
        self.rewards = [0.0, 0.0]
        self.recent = deque(maxlen=10)
        self.momentum = 1.0

    def choose(self, interval, segments):
        if self.name in ("evsids", "vmtf"):
            return int(self.name == "vmtf")
        if interval <= 2 or self.name == "round-robin":
            return (interval - 1) % 2
        means = [reward / count for reward, count in zip(self.rewards, self.effort)]
        coefficient = 4.0
        if self.name == "duration":
            coefficient = 2 * sum(means) * self.momentum / (1 + math.log2(segments))
        score = [mean + math.sqrt(coefficient * math.log(sum(self.effort)) / count)
                 for mean, count in zip(means, self.effort)]
        return int(score[1] > score[0])

    def observe(self, arm, segments, conflicts, decisions):
        if self.name not in ("duration", "ucb"):
            return
        weight = segments if self.name == "duration" else 1
        reward = math.log(max(1.0, decisions / weight)) / math.log(conflicts / weight)
        self.rewards[arm] += weight * reward / (1 + math.log2(weight))
        self.effort[arm] += weight
        self.recent.append(reward)
        self.momentum *= 1.1 if reward > sum(self.recent) / len(self.recent) else 0.9


def run(args, cnf, name, directory):
    policy = BranchingPolicy(name)
    conflicts = decisions = 0
    trace = []
    model = directory / "model.out"
    proof = directory / "proof.drat"
    proof.write_bytes(b"")
    with model.open("wb") as out, subprocess.Popen(
        [args.kernel, cnf, proof], stdin=subprocess.PIPE, stdout=out,
        stderr=subprocess.PIPE, text=True
    ) as process, selectors.DefaultSelector() as selector:
        selector.register(process.stderr, selectors.EVENT_READ)
        try:
            while conflicts < args.conflicts:
                interval = len(trace) + 1
                segments = luby(interval)
                arm = policy.choose(interval, segments)
                budget = min(args.unit * segments, args.conflicts - conflicts)
                process.stdin.write(f"{arm} {budget}\n")
                process.stdin.flush()
                if not selector.select(args.slice_timeout):
                    raise TimeoutError(f"Timed out waiting for {cnf}, interval {interval}")
                fields = process.stderr.readline().split()
                if len(fields) != 4 or fields[0] != "slice":
                    raise RuntimeError(f"Missing kernel counters for {cnf}: {fields}")
                status, total_conflicts, total_decisions = map(int, fields[1:])
                dc, dd = total_conflicts - conflicts, total_decisions - decisions
                trace.append([segments, arm, dc, dd])
                conflicts, decisions = total_conflicts, total_decisions
                if status or conflicts >= args.conflicts:
                    break
                if dc != budget:
                    raise RuntimeError(f"Incomplete interval for {cnf}: {dc} of {budget} conflicts")
                policy.observe(arm, segments, dc, dd)
            process.stdin.close()
            code = process.wait(timeout=args.slice_timeout)
            if code != {-1: 20, 0: 0, 1: 10}[status]:
                raise RuntimeError(f"Kernel status mismatch for {cnf}: {code}")
        finally:
            if process.poll() is None:
                process.kill()
    if code == 10:
        check_output(cnf, model, "SAT", 10)
    elif code == 20:
        check = subprocess.run([args.checker, cnf, proof], capture_output=True, check=True)
        if not any(line.startswith(b"s VERIFIED") for line in check.stdout.splitlines()):
            raise RuntimeError(f"Proof verification failed for {cnf}")
    return dict(file=cnf.name, policy=name, rc=code, verified=code in (10, 20),
                conflicts=conflicts, decisions=decisions, intervals=len(trace), trace=trace)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cnf", nargs="+", type=Path)
    parser.add_argument("--kernel", required=True, type=Path)
    parser.add_argument("--checker", type=Path, default=BIT.parent / "tungsten-wrat/bin/wrat")
    parser.add_argument("--unit", type=int, default=64)
    parser.add_argument("--conflicts", type=int, default=32768)
    parser.add_argument("--slice-timeout", type=float, default=60)
    parser.add_argument("--policy", nargs="+", choices=("evsids", "vmtf", "round-robin", "ucb", "duration"),
                        default=("round-robin", "ucb", "duration"))
    args = parser.parse_args()
    if args.unit < 2 or args.conflicts < 1 or args.slice_timeout <= 0:
        parser.error("unit must be at least two and both budgets must be positive")
    args.kernel = args.kernel.resolve()
    with tempfile.TemporaryDirectory() as work:
        for cnf in args.cnf:
            for name in args.policy:
                print(json.dumps(run(args, cnf, name, Path(work))), flush=True)
