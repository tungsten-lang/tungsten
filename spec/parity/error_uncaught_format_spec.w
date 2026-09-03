## parity xfail uncaught error transcripts differ: interpreter prints "error: <msg>" with a bare "--> file" locator, compiled prints "unhandled exception: <msg>" with a source excerpt and a backtrace
# Errors: an uncaught raise at top level — message shape, locator, exit code.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "before"
raise "unhandled boom"
<< "after"
