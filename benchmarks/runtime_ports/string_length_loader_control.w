# Loader-impact control: same user-class shape as the probes, but no ubiquitous
# size/length call name that can trip the one-shot String source gate.
+ StringLengthGate
  -> value
    7

value = StringLengthGate.new.value
if value != 7
  exit(1)
