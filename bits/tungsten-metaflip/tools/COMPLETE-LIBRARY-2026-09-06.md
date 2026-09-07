# Complete-library comparison and recursive reuse

The retained research audit is
`benchmarks/matmul/metaflip/complete_library_audit_2026_09_06/README.md` at the
repository root. No coefficients were promoted to this bit.

- Verified minimum-rank F2 witnesses now cover all 680 canonical shapes through
  dimension 16; 1,083 tied sources passed, and four inconsistent metadata ties
  remain excluded without leaving any shape uncovered.
- All 27 prior outer-basis candidates survive a stronger recursive comparison.
- Recursive reuse gives an additional 14×14×16 rank-1,918 candidate, from 7×274;
  previous local rank 1,922, pinned F2 catalog rank 1,943. No world-record claim.
- A separate Python tensor verifier and recursive DP check the retained data.
- `catalog_minima_library.py` adds a repeatable pinned-source import with exact
  field, Git-blob, tensor, tie, and coverage gates. The importer now supports
  fully expanded sparse factors with unused circuit annotations.

Do not interpret the 93 shapes below the pinned catalog after recursive closure
as 93 discoveries: 67 already follow from the strengthened previous basis.
The source/model scope and all negative admission results are in the audit.
