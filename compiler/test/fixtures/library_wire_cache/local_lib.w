fn library_cache_double(x)
  x * 2

+ LibraryCacheBox
  -> new(@value)

  -> value
    @value

  -> plus(x)
    @value + x
