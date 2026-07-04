# Comparable trait
#
# Include in classes that implement <=> to get <, <=, >, >=, ==
trait Comparable
  -> <(other)
    self.<=>(other) < 0

  -> <=(other)
    self.<=>(other) <= 0

  -> >(other)
    self.<=>(other) > 0

  -> >=(other)
    self.<=>(other) >= 0

  -> ==(other)
    self.<=>(other) == 0
