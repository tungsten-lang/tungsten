#!/bin/sh
# summarize.sh ROWS.tsv...: one line per (label, task) of the rows written by job.sh.
# Columns: label task runs hits exact errors, then over the hits: median, minimum and maximum of the program's CPU seconds at the
# hit, the median of the flips and of the retired instructions to the hit, the median CPU seconds of the whole adapter tree, then ert_cpu_s (sum over runs of
# min(T, B), T the program's clock at the hit, divided by the hits), walks (programs or walks started) and hits_per_walk.
LC_ALL=C awk -F'\t' '
  function sort(a, n,   i, j, t) {
    for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t }
  }
  function med(a, n) { sort(a, n); return (n % 2) ? a[(n + 1) / 2] : (a[n / 2] + a[n / 2 + 1]) / 2 }
  FNR == 1 && $1 == "label" { next }
  {
    key = $1 SUBSEP $2
    if (!(key in seen)) { seen[key] = 1; order[++nkeys] = key }
    runs[key]++
    if ($6 != "ok") { err[key]++; next }
    if ($7 == "true") {
      hits[key]++
      if ($15 == "true") ex[key]++
      c[key, hits[key]] = $9; f[key, hits[key]] = $10; tt[key, hits[key]] = $13; ins[key, hits[key]] = $16
      ert[key] += $9
    } else ert[key] += $4
    if ($17 != "NA") walks[key] += $17
  }
  END {
    printf "label\ttask\truns\thits\texact\terrors\tmed_tool_cpu_s\tmin_tool_cpu_s\tmax_tool_cpu_s\tmed_flips\tmed_instr\tmed_tree_cpu_s\tert_cpu_s\twalks\thits_per_walk\n"
    for (k = 1; k <= nkeys; k++) {
      key = order[k]; split(key, kk, SUBSEP); n = hits[key] + 0
      delete a; delete b; delete d; delete e
      for (i = 1; i <= n; i++) { a[i] = c[key, i]; b[i] = f[key, i]; d[i] = tt[key, i]; e[i] = ins[key, i] }
      if (n) { m1 = med(a, n); mn = a[1]; mx = a[n]; m2 = med(b, n); m3 = med(d, n); m4 = med(e, n) }
      printf "%s\t%s\t%d\t%d\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", kk[1], kk[2], runs[key], n, ex[key] + 0, err[key] + 0, \
        (n ? sprintf("%.4f", m1) : "NA"), (n ? sprintf("%.4f", mn) : "NA"), (n ? sprintf("%.4f", mx) : "NA"), (n ? sprintf("%.0f", m2) : "NA"), \
        (n && m4 != "NA" ? sprintf("%.0f", m4) : "NA"), (n ? sprintf("%.3f", m3) : "NA"), (n ? sprintf("%.4f", ert[key] / n) : "inf"), \
        (key in walks ? sprintf("%d", walks[key]) : "NA"), (key in walks && walks[key] > 0 ? sprintf("%.5f", n / walks[key]) : "NA")
    }
  }' "$@"
