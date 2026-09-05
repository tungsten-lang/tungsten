# Compile the old scan controller alongside current Core and compare traces.
# Usage: ruby benchmarks/calculus/trace_parity.rb /absolute/compiler
require "open3"
require "tmpdir"

compiler = ARGV.fetch(0)
root = File.expand_path("../..", __dir__)
baseline = "e7d019a73f97cf0714cde2e37b8eff6073748d7d"
source, status = Open3.capture2e("git", "-C", root, "show",
                              "#{baseline}:core/calculus/gauss_kronrod.w")
abort source unless status.success?
source = source.gsub(/\bgk15_/, "reference_gk15_")
               .gsub(/\bintegrate_gk15\b/, "reference_integrate_gk15")
probe = <<~'W'
  -> trace_check(kind, n)
    before_trace = []
    after_trace = []
    before_callback = -> (x)
      before_trace.push(x)
      kind == 0 ? Math.sin(~1000000.0*x) : (x-~0.123456789).abs
    after_callback = -> (x)
      after_trace.push(x)
      kind == 0 ? Math.sin(~1000000.0*x) : (x-~0.123456789).abs
    original = Calculus.reference_integrate_gk15(before_callback, ~0.0, ~1.0, ~1.0e-30, ~0.0, n, 30*n)
    revised = Calculus.integrate_gk15(after_callback, ~0.0, ~1.0, ~1.0e-30, ~0.0, n, 30*n)
    raise "different sample trace" if before_trace != after_trace
    raise "different integral" if original.value != revised.value
    raise "different error" if original.error_estimate != revised.error_estimate
    raise "different companion" if original.companion_value != revised.companion_value
    raise "different absolute integral" if original.absolute_integral_estimate != revised.absolute_integral_estimate
    raise "different status" if original.status != revised.status
    raise "different evaluations" if original.evaluations != revised.evaluations
    raise "different intervals" if original.intervals != revised.intervals
    << ["trace parity", kind, n, revised.status, revised.evaluations]
  trace_check(0, 64)
  trace_check(0, 256)
  trace_check(1, 32)
W

Dir.mktmpdir("calculus-trace-") do |directory|
  input = File.join(directory, "trace.w")
  output = File.join(directory, "trace")
  File.write(input, "use calculus\n#{source}\n#{probe}")
  environment = {"TUNGSTEN_ROOT" => root, "BIT_HOME" => File.join(root, "bits")}
  abort "Trace compilation failed" unless system(environment, compiler, "compile",
                                                 input, "--no-lto", "--out", output)
  abort "Trace parity failed" unless system(output)
end
