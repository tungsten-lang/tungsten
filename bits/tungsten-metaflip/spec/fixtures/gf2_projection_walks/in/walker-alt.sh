#!/bin/sh
name=$(basename "$2" -seed.mfw)
cp "$ALT/$name.mfw" "$3"
