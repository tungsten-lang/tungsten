# Small public verification facade over the square and rectangular scheme
# engines.  The underlying state implementation remains in scheme.w because
# initialization, adoption, and exactness share one tightly coupled layout.

use scheme
use rect

-> metaflip_verify_square(path, n) (String i64) i64
  if n < 2 || n > 7
    return 0
  capacity = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(capacity)]
  loaded = ffw_load_scheme_cap(state, path, n, capacity, 1, 15, 1000, 1000, 250) ## i64
  if loaded < 1
    return 0
  ffw_verify_best_exact(state, n)

-> metaflip_verify_rect(path, n, m, p) (String i64 i64 i64) i64
  if ffr_supported(n, m, p) == 0
    return 0
  capacity = ffr_default_capacity(n, m, p) ## i64
  state = i64[ffr_state_size(capacity)]
  loaded = ffr_load_scheme_cap(state, path, n, m, p, capacity, 1, 15, 1000, 1000, 250) ## i64
  if loaded < 1
    return 0
  ffr_verify_best_exact(state, n, m, p)
