# Debuggable trait
#
# Include in classes whose inspect output is precise enough to debug from
# (quoting, escapes, structure). The default falls back to the printable
# form; conformers override it with the exact rendering.
trait Debuggable
  -> inspect
    to_s
