"""Find the seeds whose pass k is received (outcome ok, gate crossed, no body hit) under a params file.
   .venv/bin/python scratchpad/btl2/pool.py ctl params s0 s1 secs k [overrides] [workers]"""
import sys
sys.path.insert(0, "scratchpad/btl2")
from multiprocessing import Pool
from common import load, parse_over, run_seed
def main():
    ctl, pfile, s0, s1, secs, k = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5]), int(sys.argv[6])
    over = sys.argv[7] if len(sys.argv) > 7 else ""
    workers = int(sys.argv[8]) if len(sys.argv) > 8 else 2
    params = load(pfile); params.update(parse_over(over))
    with Pool(workers) as p:
        res = p.map(run_seed, [(ctl, params, s, secs) for s in range(s0, s1)])
    good, recv1 = [], []
    for r in res:
        pl = r["pass_log"]
        if len(pl) >= 1 and pl[0]["outcome"] == "ok" and pl[0]["gate"] and pl[0]["body"] == 0:
            recv1.append(r["seed"])
        if len(pl) >= k and all(pl[i]["outcome"] == "ok" and pl[i]["gate"] and pl[i]["body"] == 0 for i in range(k)):
            good.append(r["seed"])
    print("pass 1 received:", len(recv1), "/", len(res))
    print(f"passes 1..{k} all received: {len(good)} / {len(res)}")
    print(",".join(str(s) for s in good))
if __name__ == "__main__":
    main()
