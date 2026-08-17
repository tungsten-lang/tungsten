use local_lib

fn library_cache_local_entry(x)
  LibraryCacheBox.new(x).plus(library_cache_double(x))

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

<< library_cache_local_entry(14)
