use flipfleet_ternary_worker

-> fftt_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

cap2 = fft_default_capacity(2) ## i64
strassen = i64[fft_state_size(cap2)]
rank = fft_init_strassen(strassen, cap2, 12345, 3) ## i64
z = fftt_expect("Strassen rank seven", rank == 7) ## i64
z = fftt_expect("Strassen exact over integers", fft_verify_current_exact(strassen) == 1 && fft_verify_best_exact(strassen) == 1)
z = fftt_expect("Strassen canonical U/V", fft_first_sign(strassen[strassen[32]], strassen[strassen[33]]) == 1 && fft_first_sign(strassen[strassen[34]], strassen[strassen[35]]) == 1)

# Gauge normalization is semantic, not cosmetic: negate U and W together and
# require the canonical representation to return byte-for-byte.
old_up = strassen[strassen[32]] ## i64
old_un = strassen[strassen[33]] ## i64
old_wp = strassen[strassen[36]] ## i64
old_wn = strassen[strassen[37]] ## i64
strassen[strassen[32]] = old_un
strassen[strassen[33]] = old_up
strassen[strassen[36]] = old_wn
strassen[strassen[37]] = old_wp
z = fftt_expect("gauge canonicalization succeeds", fft_canonicalize_slot(strassen, 0) == 1)
z = fftt_expect("gauge canonicalization unique", strassen[strassen[32]] == old_up && strassen[strassen[33]] == old_un && strassen[strassen[36]] == old_wp && strassen[strassen[37]] == old_wn)

# Signed vector arithmetic rejects +/-2 but permits exact cancellation.
z = fftt_expect("ternary addition", fft_vector_add(strassen, 1,2, 4,1, 1) == 1 && strassen[44] == 4 && strassen[45] == 2)
z = fftt_expect("coefficient two rejected", fft_vector_add(strassen, 1,0, 1,0, 1) == 0)
z = fftt_expect("signed cancellation", fft_vector_add(strassen, 1,0, 0,1, 1) == 1 && (strassen[44] | strassen[45]) == 0)

# A malformed but structurally ternary term list must fail the n^6 gate.
strassen[strassen[36]] = strassen[strassen[36]] ^ 2
z = fftt_expect("integer verifier catches corruption", fft_current_exact_error(strassen) > 0)
z = fft_restore_best(strassen)
z = fftt_expect("best restores exact state", fft_verify_current_exact(strassen) == 1)

# Plain split/combine is an exact planted round trip.
z = fftt_expect("partition split", fft_split_partition(strassen, 0,0,1) == 1 && strassen[5] == 8)
z = fftt_expect("partition split exact", fft_verify_current_exact(strassen) == 1)
combined = fft_try_combine(strassen) ## i64
z = fftt_expect("combine closes planted debt", combined != 0 && strassen[5] == 7)
z = fftt_expect("combine round trip exact", fft_verify_current_exact(strassen) == 1)

cap3 = fft_default_capacity(3) ## i64
laderman = i64[fft_state_size(cap3)]
rank = fft_init_laderman(laderman, cap3, 987654, 3)
z = fftt_expect("Laderman rank 23", rank == 23)
z = fftt_expect("Laderman exact over integers", fft_verify_current_exact(laderman) == 1 && fft_verify_best_exact(laderman) == 1)

# This deterministic donor split opens a factor-sharing door from irreducible
# rank-23 Laderman; the following signed subtraction flip changes the scheme
# while preserving every one of the 729 coefficients.
z = fftt_expect("donor split opens door", fft_split_with_donor(laderman, 0,1,0) == 1 && laderman[5] == 24)
z = fftt_expect("donor split exact", fft_verify_current_exact(laderman) == 1)
before_density = laderman[20] ## i64
flipped = fft_basis_flip_pair(laderman, 0,1,0,1,1) ## i64
z = fftt_expect("signed basis flip accepted", flipped > 0)
z = fftt_expect("signed basis flip exact", fft_verify_current_exact(laderman) == 1)
z = fftt_expect("signed basis flip moved", laderman[20] != before_density || laderman[13] > 0)

# A short planted walk must exercise all three move families without losing
# the integer tensor invariant.  Exactness is checked at both current and best.
z = fft_walk(laderman, 20000)
z = fftt_expect("bounded walk current exact", fft_verify_current_exact(laderman) == 1)
z = fftt_expect("bounded walk best exact", fft_verify_best_exact(laderman) == 1)
z = fftt_expect("walk exercised flips", laderman[12] > 0 && laderman[13] > 0)
z = fftt_expect("walk exercised splits", laderman[14] > 0 && laderman[15] > 0)
z = fftt_expect("walk exercised combines", laderman[16] > 0 && laderman[17] > 0)

# Exercise the actual top bit of the promised envelope.  This is not a 7x7
# search benchmark; it guards the two-mask representation and native i64 path
# against silently truncating coordinate 48.
cap7 = fft_default_capacity(7) ## i64
naive7 = i64[fft_state_size(cap7)]
rank7 = fft_init_naive(naive7, 7,cap7,777777,2) ## i64
last7 = rank7 - 1 ## i64
z = fftt_expect("7x7 signed-mask envelope", rank7 == 343 && ((naive7[naive7[32]+last7] >> 48) & 1) == 1 && ((naive7[naive7[34]+last7] >> 48) & 1) == 1 && ((naive7[naive7[36]+last7] >> 48) & 1) == 1)
z = fftt_expect("7x7 naive integer gate", fft_verify_best_exact(naive7) == 1)

<< "PASS ternary worker: strassen=7 laderman=23 moves=" + laderman[9].to_s() + " accepted=" + laderman[10].to_s() + " flips=" + laderman[13].to_s() + " splits=" + laderman[15].to_s() + " combines=" + laderman[17].to_s() + " best=" + laderman[6].to_s()
