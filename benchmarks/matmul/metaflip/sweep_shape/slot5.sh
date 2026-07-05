#!/bin/bash
SLOT=$1
idx=0
for B in $(seq 1 30); do
  for r in $(seq 1 16); do
    if [ $((idx % 18)) -eq $SLOT ]; then
      SEED=$((B * 1000 + r * 11 + 2))
      OUT=~/.mmwork/sweep_shape/tmp5_${SLOT}.out
      ~/.mmwork/campaign/s5_b$B $SEED > $OUT 2>&1
      BEST=$(grep -oE 'DONE best=[0-9]+' $OUT | grep -oE '[0-9]+')
      echo "$B,$SEED,${BEST:-crash}" >> ~/.mmwork/sweep_shape/r5best.csv
    fi
    idx=$((idx + 1))
  done
done
rm -f ~/.mmwork/sweep_shape/tmp5_${SLOT}.out
