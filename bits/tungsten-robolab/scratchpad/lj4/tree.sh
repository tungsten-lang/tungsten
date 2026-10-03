#!/bin/sh
# list the descendants of a pid (mine) : tree.sh <pid>
p=$1
echo $p
for c in $(pgrep -P $p); do /Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj4/tree.sh $c; done
