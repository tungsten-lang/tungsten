use flipfleet_ternary_worker

arguments = argv()
moves = 2000000 ## i64
if arguments.size() > 0
  moves = arguments[0].to_i()
if moves < 1
  moves = 1

-> fftb_run(label, n, seed_kind, moves, seed) (String i64 i64 i64 i64) i64
  capacity = fft_default_capacity(n) ## i64
  state = i64[fft_state_size(capacity)]
  rank = 0 - 1 ## i64
  if seed_kind == 0
    rank = fft_init_naive(state, n,capacity,seed,3)
  if seed_kind == 2
    rank = fft_init_strassen(state, capacity,seed,3)
  if seed_kind == 3
    rank = fft_init_laderman(state, capacity,seed,3)
  if rank < 1
    << "TERNARY_BENCH " + label + " seed-error"
    return 0 - 1
  start = ccall("__w_clock_ms") ## i64
  drops = fft_walk(state, moves) ## i64
  elapsed = ccall("__w_clock_ms") - start ## i64
  if elapsed < 1
    elapsed = 1
  rate = moves * 1000 / elapsed ## i64
  exact = fft_verify_current_exact(state) * fft_verify_best_exact(state) ## i64
  << "TERNARY_BENCH tensor=" + label + " seed_rank=" + rank.to_s() + " current=" + state[5].to_s() + " best=" + state[6].to_s() + " moves=" + moves.to_s() + " ms=" + elapsed.to_s() + " rate=" + rate.to_s() + "/s accepted=" + state[10].to_s() + " flips=" + state[13].to_s() + " splits=" + state[15].to_s() + " combines=" + state[17].to_s() + " drops=" + drops.to_s() + " exact=" + exact.to_s()
  exact

ok2 = fftb_run("2x2",2,2,moves,2026071402) ## i64
ok3 = fftb_run("3x3",3,3,moves,2026071403) ## i64
ok2n = fftb_run("2x2-naive",2,0,moves,2026071412) ## i64
ok3n = fftb_run("3x3-naive",3,0,moves,2026071413) ## i64
if ok2 != 1 || ok3 != 1 || ok2n != 1 || ok3n != 1
  exit(1)
