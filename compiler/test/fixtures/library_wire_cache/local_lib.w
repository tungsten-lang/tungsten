fn library_cache_double(x)
  x * 2

+ LibraryCacheBox
  -> new(@value)

  ro :value

  -> plus(x)
    @value + x
