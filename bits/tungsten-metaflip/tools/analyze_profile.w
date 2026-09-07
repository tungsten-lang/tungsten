# Replay an attached Instruments counter trace through tungsten-flame.
use ../../tungsten-flame/lib/builder
use ../../tungsten-flame/lib/sampler
use ../../tungsten-flame/lib/xctrace_xml
use ../../tungsten-flame/lib/sidemap
use ../../tungsten-flame/lib/counter_rates
use ../../tungsten-flame/lib/hot_frames

args = ARGV
if args.size() < 4
  << "usage: analyze_profile XML BINARY LOAD_ADDRESS OUTPUT_PREFIX [rates|cache|stalls]"
  exit(1)
set = "rates"
if args.size() > 4
  set = args[4]
info = Tungsten:Flame:Sampler.counter_set_info(set)
if info == nil
  exit(1)
parts = args[1].split("/")
process_filter = "(" + parts[parts.size() - 1] + ", pid:"
metrics = Tungsten:Flame:XctraceXml.collapse_counter_profile(read_file(args[0]), args[1], args[2], info[1], process_filter)
names = Tungsten:Flame:Sidemap.load(args[1] + ".sidemap")
metrics.keys().each -> (metric)
  metrics[metric] = Tungsten:Flame:Sidemap.rewrite_folded(metrics[metric], names)
  write_file(args[3] + "." + metric + ".folded", metrics[metric])
<< Tungsten:Flame:CounterRates.report(metrics, 20, false)
<< "metrics=" + metrics.keys().join(",")
