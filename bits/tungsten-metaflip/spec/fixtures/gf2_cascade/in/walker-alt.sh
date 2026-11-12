#!/bin/sh
out=$(basename "$3")
cat "$ALT/$out.stdout"
cp "$ALT/$out" "$3"
