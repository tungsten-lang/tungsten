-> scale(value, factor = 2) (i64 i64) i64
  value * factor
-> default_all(factor = 6) (i64) i64
  factor

+ DefaultArguments
  ro :value
  -> new(@value = 3) (i64)

  -> times(value, factor = 4) (i64 i64) i64
    value * factor

  -> .times(value, factor = 5) (i64 i64) i64
    value * factor

<< scale(7)
<< scale(7, 3)
<< DefaultArguments.times(7)
<< DefaultArguments.times(7, 3)
object = DefaultArguments.new
<< object.value
<< object.times(7)
<< object.times(7, 3)
<< DefaultArguments.new(9).value

<< default_all()
