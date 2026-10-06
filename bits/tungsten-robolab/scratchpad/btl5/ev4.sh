#!/bin/bash
# ev4.sh DATA [extra fit3 args]: replay evaluation / fit of stage 4 (the right hand's second stroke): target = the left hand's sweet spot of the stage-2 deliveries
D=$1; shift
exec scratchpad/btl5/py scratchpad/btl5/fit3.py --data $D --stage 4 --init-stage 2 --require 4 --require-ok 3 --xlo 0.1 --xhi 0.7 --ylo=-0.55 --yhi 0.0 --vzmin=-0.1 --gmax 4 --target=-0.09,0.30 --vt=-1.58,1.58 --pos-dz 0.04 --vel-dz 0.2 --w-pos 4 --w-vel 1 --apex-min 0.68 --good-apex 0.58 --good-rad 0.14 --workers 6 "$@"
