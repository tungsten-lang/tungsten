use robolab/body
use robolab/skill
use robolab/sensors
use robolab/skills/gpt_temporal

+ GptSink
  -> emit(message)

-> gpt_frame(t)
  Frame.new(Schema.new(4), [t, ~0.3, ~0.4, ~0.6, ~0.7, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0])

-> ensure_gpt(label, condition)
  if !condition
    << "FAIL [label]"
    exit(1)

sink = GptSink.new
bounds = [~0.6, ~0.4, ~0.2, ~0.1]
[~0.0, ~1.0].each ->(mode)
  zero = GptTemporalResidual.new(Skill.new(Body.new, {"gpt_temporal": mode}), bounds)
  i = 0
  while i < 20
    zero.update(gpt_frame(i * ~0.02), sink, [~0.3, ~-0.1, ~0.8, ~0.5, ~-0.5, ~0.2], i % 4)
    unchanged = zero.output.all? ->(v) v == ~0.0
    ensure_gpt("zero head leaves every target unchanged", unchanged)
    i += 1
  weights = {"gpt_temporal": mode}
  i = 0
  while i < 20
    weights["gpt_w[i]"] = ~1000.0
    i += 1
  bounded = GptTemporalResidual.new(Skill.new(Body.new, weights), bounds)
  bounded.update(gpt_frame(~0.0), sink, [~100.0, ~-100.0, ~100.0, ~-100.0, ~100.0, ~-100.0], 1)
  i = 0
  while i < 4
    ensure_gpt("correction is bounded even with out-of-box weights", bounded.output[i].abs <= bounds[i])
    i += 1

weights = {"gpt_temporal": ~1.0, "gpt_w1": ~1.0}
a = GptTemporalResidual.new(Skill.new(Body.new, weights), bounds)
b = GptTemporalResidual.new(Skill.new(Body.new, weights), bounds)
a.update(gpt_frame(~0.0), sink, [~1.0, ~1.0, ~1.0, ~1.0, ~1.0, ~1.0], 0)
b.update(gpt_frame(~0.0), sink, [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0], 0)
a.update(gpt_frame(~0.02), sink, [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0], 0)
b.update(gpt_frame(~0.02), sink, [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0], 0)
ensure_gpt("temporal history changes output with identical current input", (a.output[0] - b.output[0]).abs > ~0.000001)
held = a.output[0]
a.update(gpt_frame(~0.025), sink, [~1.0, ~1.0, ~1.0, ~1.0, ~1.0, ~1.0], 0)
ensure_gpt("sample interval holds output until next causal update", a.output[0] == held)
<< "50 checks passed: zero head, bounded output, temporal history, sample clock"
