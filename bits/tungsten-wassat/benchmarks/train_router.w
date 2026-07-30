# Compiled offline Wassat formula-router trainer.
#
#   bin/tungsten -o /tmp/wassat-router-train \
#     bits/tungsten-wassat/benchmarks/train_router.w
#   /tmp/wassat-router-train training.csv [generated_router.w]
#
# The optional output is written only when the validation-selected model is a
# DecisionTreeClassifier and clears RouterTrainer's conservative baseline
# gate. Test metrics are evaluated only after selection is locked.

use ./router_trainer

args = argv()
if args.size < 1 || args.size > 2
  << "usage: train_router <training.csv> [generated_router.w]"
  exit(1)

loaded = RouterTrainer.load_csv(args[0])
if !loaded[:ok]
  << "router CSV error: " + loaded[:error]
  exit(1)

result = RouterTrainer.train(loaded[:rows])
RouterTrainer.report(result).each -> (line)
  << line
if !result[:ok]
  exit(1)

if args.size == 2
  if result[:export] == nil
    << "no source written: export gate did not pass"
    exit(2)
  wrote = write_file(args[1], result[:export][:source])
  if !wrote
    << "could not write generated source: " + args[1]
    exit(1)
  << "wrote_generated_source=" + args[1]
