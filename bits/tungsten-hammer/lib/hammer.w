# Hammer — High-performance HTTP benchmark tool
#
# CLI entry point: parses argv via Argon (manpage-as-schema) and dispatches
# to the C engine (lib/hammer.c) or the experimental Tungsten engine.
# All library logic lives in lib/core.w (`use hammer/core` from outside).

use argon
use core

manpage = read_file(__DIR__ + "/../man/hammer.1.wd")
cli = Argon.new(manpage)
opts = cli.parse(ARGV)

if opts.flag?("help") || opts.flag?("h")
  opts.help!

url = opts.command
if !url
  << "Error: URL required"
  << ""
  opts.help!

connections = opts.get("connections")
duration    = opts.get("duration")
workers     = opts.get("workers")
pipeline    = opts.get("batch")

# Protocol: h10/1.0 → 0, h11/1.1 → 1, h2/2 → 2
# Argon casts option values (-p 2 → Int, -p 1.0 → Float); normalize to string.
proto = opts.get("protocol").to_s
case proto
  when "h10", "1.0", "1" then protocol = 0  # cast turns "1.0" into Float; to_s gives "1"
  when "h11", "1.1"      then protocol = 1
  when "h2", "2"         then protocol = 2
  else
    << "Unknown protocol: " + proto
    << "Supported: h10, h11, h2"
    exit(1)

forge_mode = 0
if opts.flag?("forge")
  forge_mode = 1
  pipeline = 1

max_mode = 0
if opts.flag?("max")
  max_mode = 1

if opts.flag?("tungsten")
  if protocol != 1
    << "--tungsten currently supports HTTP/1.1 only"
    exit(1)
  if forge_mode == 1
    << "--tungsten does not support --forge yet"
    exit(1)
  Hammer.run_tungsten(url, connections, duration, workers, pipeline)
else
  # w_hammer_run returns req/s on success, nil on failure (bad URL, DNS, ...)
  result = ccall("w_hammer_run", url, connections, duration, workers, protocol, pipeline, forge_mode, max_mode)
  exit(1) if result == nil
