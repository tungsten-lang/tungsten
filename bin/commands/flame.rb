# tungsten flame — thin dispatch shim into the pure-Tungsten bit.
#
# All implementation lives in bits/tungsten-flame/lib/*.w. This Ruby
# file is dispatch glue only: it loads the Tungsten Ruby interpreter
# and hands flame.w the original ARGV.

$LOAD_PATH.unshift(File.join(ROOT, "implementations/ruby/lib"))
require "tungsten"

# --alloc: arm the runtime allocation profiler in the profiled child.
# The env var is read by sampler.w (xctrace --env injection) and by the
# runtime itself when flame profiles an in-process build.
ENV["TUNGSTEN_FLAME_ALLOC"] = "1" if ARGV.include?("--alloc")

flame_w = File.join(ROOT, "bits/tungsten-flame/lib/flame.w")
begin
  Tungsten::Interpreter.new.run(File.read(flame_w), file_path: flame_w)
rescue SystemExit
  # flame.w exits explicitly; propagate
  raise
end
