# Item 23: inspect claims and replay evidence

Proposal. Use one structured view contract shared by CLI and Notes. It should
answer "what was checked, against which inputs, under which assumptions?"
without requiring the reader to inspect implementation objects.

```json
{
  "schema_version": 1,
  "kind": "certificate",
  "claim": "The supplied matrix has rank 7 over GF(2)",
  "scope": "matrix artifact sha256:...",
  "level": "finite_checked",
  "verification": {"status": "passed", "verifier": "gf2-rank/v1", "evidence": "sha256:..."},
  "assumptions": [],
  "dependencies": [],
  "artifacts": [{"role": "input", "path": "matrix.bin", "sha256": "..."}]
}
```

Levels reuse `doc/certified-mathematics.md`: finite checked, arithmetic checked,
trusted theorem import, kernel checked, conditional and heuristic. They are
not a single numeric confidence scale. A kernel-checked conditional theorem
can still require an assumption; verification status and claim status must
be independent fields. Missing evidence is unknown, not failed or passed.

Notes presentation:

1. Exact claim, mathematical domain/scope, level and current replay status.
2. Assumptions and theorem imports immediately below the claim, with links to
   their own records. A dependency graph shows the first unresolved obligations.
3. Artifact hashes, producer/verifier versions, transcript and last replay time.
4. An explicit "Replay verification" action using a locally configured verifier,
   with a new result record instead of overwriting old evidence.

Rendering reads the record; it does not call `verified?` implicitly or run a
command embedded in an imported document. Hash agreement establishes artifact
identity, not mathematical truth. "Certified" is available only when the
claim's required dependency closure has a matching successful unconditional
verification under the displayed trust base. Cycles, missing nodes and unknown
levels cannot promote a claim. Trusted theorem imports stay visibly trusted.

Suggested object facade: `certificate.inspection_record` returns this data;
`certificate.to_notes` projects it into a Notes certificate block. Start with
one existing finite certificate and one conditional certificate to make the
contrast testable. Acceptance: dependency failure propagates, changed input
hashes invalidate replay, finite rank evidence never implies an unrelated
global theorem, and opening a saved Notes document does not run a verifier.
