# Deliberately non-String receiver. This quantifies the conservative false
# positive of the sound broad size-name gate in a minimal output.
+ StringLengthGate
  -> size
    7

value = StringLengthGate.new.size
if value != 7
  exit(1)
