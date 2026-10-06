"""Identity check of the chained replay on recorded G starts: event ticks, table activations and the ball path against the closed loop."""
import os, pickle, sys, time
import numpy as np
sys.path.insert(0, "scratchpad/btl6")
import chainrep as C

recdir, pfile, s0, seeds = sys.argv[1], sys.argv[2], int(sys.argv[3]), [int(x) for x in sys.argv[4].split(",")]
rec0 = pickle.load(open(os.path.join(recdir, f"rec_{seeds[0]}.pkl"), "rb"))
ch = C.Chain(pfile, rec0)
tot = {"n": 0, "ev_ok": 0, "act_max": 0.0, "ball_max": 0.0}
for sd in seeds:
    rec = pickle.load(open(os.path.join(recdir, f"rec_{sd}.pkl"), "rb"))
    st = ch.prep(rec, s0)
    if st is None:
        print(sd, "no chain"); continue
    t1 = time.time()
    run = ch.run(st)
    dt = time.time() - t1
    if run is None:
        print(sd, "run failed"); continue
    trig, rel, n = run["trig"], run["rel"], run["n"]
    rr = st["rec_rel"]
    ks = st["ks"]
    exp_trig = {s: ks[s] for s in (3, 4) if s in ks and s > s0}
    msg = f"{sd} n {n} t {dt:.2f}s trig {trig} (rec {exp_trig}) rel {rel} (rec {rr})"
    # table activations vs the recorded activations of the stroking arm at the stage's live ticks
    amax = 0.0
    for s, ss in run["stage"].items():
        if s == 2:
            continue
        arm = ch.idx["r" if C.HAND[s] == "r" else "l"]
        for j in range(len(ss["live"])):
            if ss["live"][j] and ss["t0"] + j < len(st["acts"]):
                amax = max(amax, float(np.max(np.abs(st["acts"][ss["t0"] + j][arm] - ss["A"][:, j]))))
    # ball path
    bm = float(np.max(np.abs(run["out"]["pos"][:min(n, len(st["ball_rec"]))] - st["ball_rec"][:min(n, len(st["ball_rec"]))])))
    msg += f" | table-vs-record max {amax:.2e} | ball path max dev {bm:.2e}"
    print(msg, flush=True)
