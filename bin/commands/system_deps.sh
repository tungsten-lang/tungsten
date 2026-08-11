#!/bin/sh

# Print Homebrew's actual prefix for the installation or a formula. Homebrew
# uses different roots on Apple Silicon, Intel, Linux, and custom installs.
tungsten_homebrew_prefix() {
  command -v brew >/dev/null 2>&1 || return 1
  if [ "$#" -eq 0 ]; then
    brew --prefix 2>/dev/null
  else
    brew --prefix "$1" 2>/dev/null
  fi
}
