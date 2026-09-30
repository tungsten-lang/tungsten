# Corrections to earlier project documents (found while drafting the papers, 2026-09-29)

The papers state the corrected facts. The documents below still carry the old wording; none of the
corrections changes a rank, an exactness result or a classification. Pointers are to the audit fact sheets
kept with the campaign working directory (`paper-notes/04-verification-boards-lineage.md`, `02-projection-and-basis.md`,
`07-earlier-stages.md`).

## In the archive (`tungsten-lang/metaflip-archives`, release `evidence-2026-09-29`)

1. **`records.tsv`, `chain` of two rows.** 9x9x9/482 is labelled `live fleet checkpoint`; it is a walk from a public
   scheme (`public seed -> walk`). 13x13x13/1402 is labelled `live fleet checkpoint`; its tensor is the July
   certificate itself (RT sha `b491b7b8...` equals the bundle-C row), so the label is `July certificate`.
   The results paper applies both corrections (`scripts/gen_results_data.py`).
2. **Bundle A README and `A.log`: "the other 11 are equal-rank variants".** Six are (they carry the note written by
   `flag_variants.py`). The other five are the first pass's board seeds: lower-rank constructions that used local
   4x4x8 and 12x15x16 witnesses which the manifest does not list; eight records depend on them. They are exact,
   but their leaf provenance is incomplete.
3. **Verification scope.** The release's verification logs A, A_walks, B, C and D were produced with `--no-ruby`; the shipped Ruby logs cover the 691 records held in bundles and the 661 chain heads. The Ruby check of all 985 distinct bundle tensors, of the 102 committed certificates and of the two fleet checkpoints (1,089 tensors, all exact) is `bits/tungsten-metaflip/papers/verification/ruby_all_20260929.log` (script `papers/scripts/ruby_verify_all.py`), and the closure rebuild (259 of 267 rows byte-identical, 8 rows lost to three unrecovered leaves) is `papers/verification/rebuild_closure_20260929.log`. The archive's index has no prior-art column: `papers/results/data/prior_art_flags.tsv` flags 87 records superseded and 112 matched by published constructions (`papers/results/sections/persistence.tex`).

## In `bits/tungsten-metaflip/tools/RECORD-HUNT-2026-09-26.md`

4. **"the projection cascade has converged on this witness set" (4 children worth walking).** Not supported: the selection rule
   compared each child with a board that already contained it, which excluded at least 48 round-3 children that
   qualified under the rule's intent (none of them walked). See the methods paper, section on self-referential selection.
5. **"(1/2, 1/4, 1/8)" as the even denominators of rational schemes that do not reduce modulo two.** Illustrative only: 20 of the
   278 even-denominator files also use denominators such as 6, 10, 12 or 16. The conclusion (none of the 20 odd-only files
   is below our scheme for its format) is unchanged.
6. **"17 Perminov rational schemes at or below a GF(2)-valid-only record".** True only when the two files under `/known/`
   (13x13x13/1379 and 15x15x15/1977) are counted; the scoreboard, which excludes `/known/`, gives 15.
7. **"still exact and attributed" for the five board-leaf rows** (see 2).
8. **"the four fleet checkpoints were Ruby-checked".** No log of such a check existed when this was written; the four
   checkpoints were checked in Ruby on 2026-09-29 afterwards (all exact).

## In `benchmarks/matmul/metaflip/` (July block-composition notes)

9. **`BLOCK_COMPOSITION_RECORDS.md`: "six support-distinct orientations" of the d450 outer scheme.** The scheme is invariant
   under transposition, so only three of the six images are distinct (as term sets and as support patterns).
10. **`BLOCK_COMPOSITION.md:211` calls the 7x7x7 leaf "rank-248"; `flipfleet_block_compose.w:195` loads the rank-247 file.**
   Immaterial: no July recipe uses a 7x7x7 leaf.
11. **`CERT/block47-exact-20260923/README.md`: "thirty-nine block formulas".** The manifest has 46 rows.
12. **The July "strict" classification used Lille ranks as GF(2) comparators for some shapes**; the 2026-09-29 board treats the
    Lille digest as field-unspecified. The two classifications differ for rows such as 12x15x17, 13x13x18 and 15x15x17.
