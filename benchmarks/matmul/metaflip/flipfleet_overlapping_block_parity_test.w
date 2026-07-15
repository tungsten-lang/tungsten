use flipfleet_overlapping_block_parity

-> ffobpt_expect(name, condition)
  if condition
    << "PASS " + name
    return 0
  << "FAIL " + name
  exit(1)
  1

root = "benchmarks/matmul/metaflip/"

# Enumerate and exactly validate the bounded primitive mask catalogue.
count = ffobp_bounded_count(3, 3, 3, 128) ## i64
ffobpt_expect("enumerates 81 lifted four-cycles", count == 81)
identity = ffobp_bounded_at(3, 3, 3, 0)
ffobpt_expect("four-block index identity exact", ffobp_identity_zero(identity) == 1)
subset = 1 ## i64
proper_zero = 0 ## i64
while subset < 15
  proper_zero += ffobp_subset_zero(identity, subset)
  subset += 1
ffobpt_expect("four-cycle primitive", proper_zero == 0)

partition = i64[3]
gain = ffobp_best_partition(identity, partition) ## i64
ffobpt_expect("raw block-rank imbalance 7 to 1", gain == 6 && partition[1] == 7 && partition[2] == 1)
expensive = ffobp_materialize_naive(identity, partition[0])
cheap = ffobp_materialize_naive(identity, 15 ^ partition[0])
ffobpt_expect("opposite sides tensor-equal", expensive != nil && cheap != nil && ffobp_same_tensor(expensive, cheap) == 1)
ffobpt_expect("raw macro ranks retained", expensive.rank() == 7 && cheap.rank() == 1)
ffobpt_expect("parity cancellation explains apparent gain", ffobp_parity_rank(expensive) == 1 && ffobp_parity_rank(cheap) == 1)

# The macro backend is not limited to schoolbook blocks: embed Strassen into
# non-contiguous masks and independently compare all represented tensor cells.
strassen = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
embedded = ffobp_embed_leaf(strassen, 3, 3, 3, 5, 3, 6)
embedded_reference = ffobp_naive_block(3, 3, 3, 5, 3, 6)
ffobpt_expect("non-contiguous exact leaf embedding", embedded != nil && embedded.rank() == 7 && embedded_reference.rank() == 8 && ffobp_same_tensor(embedded, embedded_reference) == 1)
ffobpt_expect("leaf embedding rejects boundary mismatch", ffobp_embed_leaf(strassen, 3, 3, 3, 1, 3, 6) == nil)

# Plant the expensive overlapping-block representation in schoolbook 3x3,
# then let the bounded catalogue discover and replace it one identity at a
# time.  The intermediate rank is deliberately nominal: four terms cancel in
# GF(2), but retaining them models independently supplied rectangular leaves.
naive3 = ffobp_naive(3, 3, 3)
ffobpt_expect("small baseline exact", naive3.rank() == 27 && ffbc_verify_exact(naive3) == 1)
planted3 = ffobp_replace(naive3, cheap, expensive, 0)
ffobpt_expect("small planted macro exact", planted3 != nil && planted3.rank() == 33 && ffbc_verify_exact(planted3) == 1)
reduced3 = ffobp_find_bounded_reduction(planted3, 1)
ffobpt_expect("small bounded macro reduction", reduced3 != nil && reduced3.rank() == 27 && ffbc_verify_exact(reduced3) == 1)

# Full 7x7 reconstruction: append the raw eight-term zero macro to the saved
# rank-248 certificate, retain its nominal rank, then rediscover the expensive
# side and return to 248.  This exercises 49-bit factors and complete tensor
# reconstruction rather than relying on the index-mask proof alone.
record7 = ffbc_load_exact(root + "matmul_7x7_rank248_d2952_sedoglavic_gf2.txt", 7, 7, 7, 320)
ffobpt_expect("full rank-248 record exact", record7 != nil && record7.rank() == 248)
identity7 = ffobp_bounded_at(7, 7, 7, 0)
all7 = ffobp_materialize_naive(identity7, 15)
ffobpt_expect("full lifted zero macro exact", all7 != nil && all7.rank() == 8 && ffobp_verify_scheme_zero(all7) == 1 && ffobp_parity_rank(all7) == 0)
augmented7 = ffobp_append_zero(record7, all7)
ffobpt_expect("full raw macro splice exact", augmented7 != nil && augmented7.rank() == 256 && ffbc_verify_exact(augmented7) == 1)
ffobpt_expect("full parity rank accounted", ffobp_parity_rank(augmented7) == 248)
reduced7 = ffobp_find_bounded_reduction(augmented7, 1)
ffobpt_expect("full bounded macro returns rank 248", reduced7 != nil && reduced7.rank() == 248 && ffbc_verify_exact(reduced7) == 1)

<< "overlapping block parity: primitive=4 blocks raw-side=7->1 parity-side=1->1 full=256->248"
<< "flipfleet_overlapping_block_parity_test: all checks passed"
