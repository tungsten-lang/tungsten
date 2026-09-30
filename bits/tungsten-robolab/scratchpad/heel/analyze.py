import sys
import numpy as np
z = np.load(sys.argv[1]); A = z["arr"]; N = list(z["names"])
t0 = float(sys.argv[2]) if len(sys.argv) > 2 else 14.0
t1 = float(sys.argv[3]) if len(sys.argv) > 3 else 1e9
col = lambda n: A[:, N.index(n)]
sel = (col("t") >= t0) & (col("t") <= t1)
t = col("t")[sel]
dt = np.median(np.diff(t))
x = col("x")[sel]
speed = (x[-1] - x[0]) / (t[-1] - t[0])
print(f"window {t[0]:.1f}-{t[-1]:.1f} s, dt {dt*1000:.0f} ms, mean speed {speed:.2f} m/s")
def peaks(sig, prom=0.5, win_s=0.14):
    w = max(1, int(win_s / dt))
    idx = []
    for i in range(w, len(sig) - w):
        seg = sig[i - w:i + w + 1]
        if sig[i] == seg.max() and sig[i] - seg.min() > prom:
            if not idx or i - idx[-1] > w:
                idx.append(i)
    return np.array(idx, dtype=int)
for side in ("l", "r"):
    k = col(f"knee_{side}")[sel]; h = col(f"hip_{side}")[sel]
    hz = col(f"heel_{side}_z")[sel]; hdz = col(f"heel_{side}_dz")[sel]; hdx = col(f"heel_{side}_dx")[sel]
    dist = np.hypot(hdx, hdz)
    ip = peaks(k, 0.4)
    print(f"-- {side} leg: {len(ip)} swings; peak knee flexion per swing (deg):", np.round(np.degrees(k[ip]), 0).astype(int).tolist()[:10])
    print(f"   mean peak knee flexion {np.degrees(k[ip]).mean():.0f} deg (max {np.degrees(k[ip]).max():.0f}); "
          f"heel peak height {hz[ip].mean():.2f} m (pelvis z ~{col('pelvis_z')[sel].mean():.2f}); "
          f"heel-to-hip min distance at swing {dist[ip].mean():.2f} m; hip flexion at knee peak {np.degrees(h[ip]).mean():.0f} deg")
    # peak hip flexion (thigh forward) and its knee
    ih = peaks(h, 0.4)
    print(f"   peak hip flexion {np.degrees(h[ih]).mean():.0f} deg with knee {np.degrees(k[ih]).mean():.0f} deg at that instant")
