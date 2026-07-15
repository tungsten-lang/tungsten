use flipfleet_ternary_sign_isotropy

-> fftsign_expect(label, condition) (String bool) i64
  if ! condition
    << "FAIL " + label
    exit(1)
  1

capacity = 32 ## i64
source = i64[fft_state_size(capacity)]
z = fftsign_expect("Strassen seed",fft_init_strassen(source,capacity,2026071601,3) == 7) ## i64
z = fftsign_expect("Strassen exact before signed isotropy",fft_current_exact_error(source) == 0)
rank = source[5] ## i64
density = source[20] ## i64
fingerprint = fft_current_fingerprint(source) ## i64

supports = i64[3 * rank]
slot = 0 ## i64
while slot < rank
  factor = 0 ## i64
  while factor < 3
    base = 32 + 2 * factor ## i64
    supports[3*slot+factor] = source[source[base]+slot] | source[source[base+1]+slot]
    factor += 1
  slot += 1

# This action flips one i coordinate, one j coordinate, and a different k
# coordinate.  It changes signed factors but cannot change their supports.
z = fftsign_expect("nonidentity sign conjugation",fftsi_raw(source,1,2,1) == 1)
z = fftsign_expect("rank invariant",source[5] == rank)
z = fftsign_expect("density invariant",source[20] == density)
z = fftsign_expect("signed presentation changes",fft_current_fingerprint(source) != fingerprint)
slot = 0
while slot < rank
  factor = 0
  while factor < 3
    base = 32 + 2 * factor
    z = fftsign_expect("GF2 support unchanged",(source[source[base]+slot] | source[source[base+1]+slot]) == supports[3*slot+factor])
    factor += 1
  slot += 1
z = fftsign_expect("integer tensor exact after signed isotropy",fft_current_exact_error(source) == 0)

# The same diagonal signs are their own inverse even after per-term gauge
# canonicalization.
z = fftsign_expect("sign conjugation inverse",fftsi_raw(source,1,2,1) == 1)
z = fftsign_expect("inverse restores canonical fingerprint",fft_current_fingerprint(source) == fingerprint)
z = fftsign_expect("inverse remains exact",fft_current_exact_error(source) == 0)
z = fftsign_expect("all-zero masks are identity",fftsi_raw(source,0,0,0) == 0)
z = fftsign_expect("common all-coordinate sign is kernel",fftsi_raw(source,3,3,3) == 0)
z = fftsign_expect("out-of-range mask rejected",fftsi_raw(source,4,0,0) < 0)

# Exercise every deterministic trial mask on the larger Laderman scheme.  A
# second application must restore precisely the starting canonical endpoint.
laderman = i64[fft_state_size(64)]
z = fftsign_expect("Laderman seed",fft_init_laderman(laderman,64,2026071602,3) == 23)
laderman_fp = fft_current_fingerprint(laderman) ## i64
laderman_density = laderman[20] ## i64
masks = i64[3]
trial = 0 ## i64
while trial < 18
  z = fftsi_trial_masks(3,trial,masks)
  z = fftsign_expect("trial action",fftsi_raw(laderman,masks[0],masks[1],masks[2]) == 1)
  z = fftsign_expect("trial density",laderman[20] == laderman_density)
  z = fftsign_expect("trial inverse",fftsi_raw(laderman,masks[0],masks[1],masks[2]) == 1)
  z = fftsign_expect("trial fingerprint inverse",fft_current_fingerprint(laderman) == laderman_fp)
  trial += 1
z = fftsign_expect("Laderman remains exact",fft_current_exact_error(laderman) == 0)

<< "PASS ternary diagonal sign isotropy: exact/involutive, support+density invariant, and literally invisible after GF2 support projection"
