# @resources
#   https://www.cs.utexas.edu/users/EWD/transcriptions/EWD08xx/EWD831.html
+ Range
  is Enumerable

  field :val1
  field :val2

  # Endpoints — `start` is the lower bound, `finish` the upper. Whether
  # `finish` is included is encoded in the range literal (`..` inclusive
  # vs `...` exclusive); the inclusive/exclusive distinction lives in
  # the runtime's iteration logic, not in the field set, so methods that
  # depend on it (last/max/include?/each/to_a) live with the runtime.

  -> start
    val1

  -> finish
    val2

  -> first
    val1

  -> min
    val1

  -> sum
