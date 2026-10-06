#!/bin/bash
# usage: pause.sh stop|cont out/btl5/<name>.pid   -- SIGSTOP / SIGCONT my own process (pid in the file) and its direct children (the pool workers), by pid
SIG=$([ "$1" = stop ] && echo STOP || echo CONT)
P=$(cat "$2")
CH=$(pgrep -P "$P" | tr '\n' ' ')
kill -$SIG $P $CH
echo "$SIG $P $CH"
