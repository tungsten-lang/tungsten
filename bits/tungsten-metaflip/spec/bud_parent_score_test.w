use ../tools/bud_parent_score

-> bud_check(label, condition)
  if !condition
    << "FAIL bud parent score: " + label
    exit(1)
  1

z = bud_check("offline generic parents leave campaign allowlist unchanged",ffbp_supported(2,2,13) == 1 && ffr_supported(2,2,13) == 0 && ffrp_supported_label("2x2x13") == 0)
z = bud_check("other offline public parents",ffbp_supported(2,3,7) == 1 && ffbp_supported(2,4,8) == 1 && ffbp_supported(3,4,11) == 1 && ffbp_supported(4,4,10) == 1)
z = bud_check("offline shape width boundaries",ffbp_supported(7,8,7) == 1 && ffbp_supported(7,9,2) == 0 && ffbp_supported(2,2,16) == 0 && ffbp_supported(8,2,2) == 0 && ffbp_supported(1,2,2) == 0)

capacity = ffr_default_capacity(2,3,4) ## i64
words = ffr_state_size(capacity) ## i64
state = i64[words]
copy = i64[words]
keys = i64[capacity]
counts = i64[capacity]
rank = ffr_init_naive_cap(state,2,3,4,capacity,9917,4,4,1000,500) ## i64
z = bud_check("exact initialization",rank == 24 && ffr_verify_current_exact(state,2,3,4) == 1)
z = ffbp_copy(state,copy,words)
prices = i64[3 * 27]
axis = 0 ## i64
while axis < 3
  i = 1 ## i64
  while i < 27
    prices[axis * 27 + i] = i*i + axis*100
    i += 1
  axis += 1
z = bud_check("six U groups of four",ffbp_axis_cost(state,0,prices,27,keys,counts) == 96)
z = bud_check("twelve V groups of two",ffbp_axis_cost(state,1,prices,27,keys,counts) == 1248)
z = bud_check("eight W groups of three",ffbp_axis_cost(state,2,prices,27,keys,counts) == 1672)
z = bud_check("minimum and reused scratch",ffbp_cost(state,prices,27,keys,counts) == 96 && ffbp_cost(state,prices,27,keys,counts) == 96)
z = bud_check("price domain gate",ffbp_cost(state,prices,24,keys,counts) == 9223372036854775807)
i = 0 ## i64
while i < words
  z = bud_check("read-only scorer",state[i] == copy[i])
  i += 1
z = bud_check("walking accepts worse",ffbp_accept("walk",400,387,387,0) == 1)
z = bud_check("greedy quality gate",ffbp_accept("greedy",386,387,387,0) == 1 && ffbp_accept("greedy",387,387,387,0) == 1 && ffbp_accept("greedy",388,387,387,0) == 0)
z = bud_check("anneal cycle",ffbp_accept("anneal",395,387,387,64) == 1 && ffbp_accept("anneal",396,387,387,64) == 0 && ffbp_accept("anneal",388,395,387,80) == 0)
z = bud_check("invalid mode",ffbp_accept("bad",386,387,387,0) == 0)
z = bud_check("quality precedes primitive rank",ffbp_better(380,34,1000,387,32,156) == 1 && ffbp_better(388,31,100,387,32,156) == 0)

grid_capacity = ffr_default_capacity(3,3,3) ## i64
grid_words = ffr_state_size(grid_capacity) ## i64
grid_state = i64[grid_words]
grid_copy = i64[grid_words]
grid_keys = i64[grid_capacity]
grid_counts = i64[grid_capacity]
linear_prices = i64[3 * 32]
grid_prices = i64[3]
rank = ffw_init_naive_cap(grid_state,3,grid_capacity,9917,4,4,1000,500)
z = bud_check("square routed only by offline adapter",ffbp_supported(3,3,3) == 1 && ffr_supported(3,3,3) == 0 && rank == 27)
z = bud_check("square verifier",ffbp_verify(grid_state,3,3,3) == 1)
z = ffbp_copy(grid_state,grid_copy,grid_words)
axis = 0
while axis < 3
  i = 1
  while i < 32
    linear_prices[axis * 32 + i] = 100 * i
    i += 1
  grid_prices[axis] = 400
  axis += 1
z = bud_check("nonimproving grids preserve baseline",ffbp_grid_cost(grid_state,linear_prices,32,grid_keys,grid_counts,grid_prices) == 2700)
grid_prices[0] = 300
grid_prices[1] = 290
grid_prices[2] = 280
z = bud_check("one grid only and all orientations",ffbp_grid_cost(grid_state,linear_prices,32,grid_keys,grid_counts,grid_prices) == 2580)
z = bud_check("grid stride gate",ffbp_grid_cost(grid_state,linear_prices,27,grid_keys,grid_counts,grid_prices) == 9223372036854775807)
grid_prices[0] = 0
z = bud_check("disabled grid model",ffbp_grid_cost(grid_state,linear_prices,32,grid_keys,grid_counts,grid_prices) == 2700)
i = 0
while i < grid_words
  z = bud_check("read-only grid scorer",grid_state[i] == grid_copy[i])
  i += 1
<< "PASS exact read-only bud/grid scoring and parent acceptance controls"
