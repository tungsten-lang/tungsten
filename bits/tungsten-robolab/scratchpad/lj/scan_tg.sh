#!/bin/sh
# scan il_tg on the 96 validation starts (b15, p95pn_a)
cd /Users/erik/tungsten/bits/tungsten-robolab
for tg in 0.64 0.67 0.70 0.73; do
  .venv/bin/python playground/long_jump_eval.py long_jump_p95_robust --params params/long_jump_p95pn_a.txt --controller bin/challengers/long_jump_run-b15 --task long_jump_p95e --seeds 7001-7096,401-416 --workers 4 --set il_tg=$tg,il_zl=0.44387629375771404 --out out/long_jump_run/val112_p95pn_a_tg$tg.json > out/long_jump_run/val112_p95pn_a_tg$tg.log 2>&1
done
echo done > out/long_jump_run/scan_tg.done
