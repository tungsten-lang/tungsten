# Independent length-name false-positive probe for the shared one-shot gate.
+ StringLengthGate
  -> length
    7

value = StringLengthGate.new.length
if value != 7
  exit(1)
