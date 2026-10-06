#!/bin/bash
# ev3v1.sh DATA [extra fit3 args]: stage 3 with the FULL-ENERGY objective (V1): the ball the stage-2 / stage-4 right hand's table works from (arrival (0.44, -0.26), velocity (1.5, -1.5), apex >= 0.68)
D=$1; shift
exec scratchpad/btl5/py scratchpad/btl5/fit3.py --data $D --stage 3 --gmax 4 --target 0.44,-0.26 --vt 1.5,-1.5 --pos-dz 0.04 --vel-dz 0.2 --w-pos 4 --w-vel 1 --apex-min 0.68 --good-apex 0.58 --good-rad 0.14 --workers 6 "$@"
