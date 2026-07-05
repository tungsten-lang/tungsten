#!/bin/bash
# slot.sh <slot 0..17> <prefix s3|s5> <csv>
SLOT=$1; PFX=$2; CSV=$3
idx=0
for B in $(seq 1 30); do
  for r in $(seq 1 16); do
    if [ $((idx % 18)) -eq $SLOT ]; then
      SEED=$((B * 1000 + r * 7 + 5))
      OUT=~/.mmwork/sweep_shape/tmp_${PFX}_${SLOT}.out
      ~/.mmwork/campaign/${PFX}_b$B $SEED > $OUT 2>&1
      LINES=$(grep -o 'FOUND mv=[0-9]* rank=[0-9]*' $OUT | sed 's/FOUND mv=//; s/ rank=/,/')
      if [ -n "$LINES" ]; then
        echo "$LINES" | while IFS=, read mv rk; do echo "$B,$SEED,$rk,$mv" >> $CSV; done
      else
        echo "$B,$SEED,none,none" >> $CSV
      fi
    fi
    idx=$((idx + 1))
  done
done
rm -f ~/.mmwork/sweep_shape/tmp_${PFX}_${SLOT}.out
