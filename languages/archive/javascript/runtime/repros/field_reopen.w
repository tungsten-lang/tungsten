# Reopening a parent class to add a field after a subclass declared its own fields makes
# the two fields share storage in compiled code.
+ Base
  rw :a
  -> new
+ Kid < Base
  rw :k
  -> new(@k)
+ Base
  rw :late
kd = Kid.new("kid field")
kd.late = 42
<< kd.k
