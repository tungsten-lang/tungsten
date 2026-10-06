#!/bin/bash
# ev3.sh DATA [extra fit3 args]: replay evaluation (eval-only) of an init / fit with the V2 objective (reflex-compatible target); run from bits/tungsten-robolab
D=$1; shift
exec scratchpad/btl5/py scratchpad/btl5/fit3.py --data $D --stage 3 --eval-only --gmax 4 --target 0.41,-0.25 --vt 0.72,-0.92 --pos-dz 0.06 --vel-dz 0.25 --w-pos 3 --apex-min 0.50 --good-apex 0.45 --good-rad 0.2 --workers 6 "$@"
