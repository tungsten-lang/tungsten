# Bit AV implementation

Worktree: `/Users/erik/tungsten-worktrees/bit-av`, branch `codex/bit-av`.
Scope: generic `bit NAME SUBCOMMAND` dispatch from package `commands/`, project-root
Bitfile AV plans, useful AV commands, and the ten approved follow-up improvements.

- [x] Map existing command and Bitfile contracts; document the AV file map
- [x] Generic package command discovery, nested commands, packaging and help
- [x] Declarative Bitfile profiles, validation, migration and examples
- [x] 1 Doctor and read-only execution plans
- [x] 2 Input snapshots and automatic resume implementation identity
- [x] 3 Explicit BT.709 colour validation and unsupported HDR rejection
- [x] 4 Preserve 10-bit 4:2:2 for ProRes
- [x] 5 Configurable final-file audio QC
- [x] 6 Caption/script layout and encoded-text QC
- [x] 7 Timeline-aware whole-film anomaly scan
- [x] 8 Resource-budgeted concurrency and queue reporting
- [x] 9 Share bitrate search with reference-quality probes
- [x] 10 Abrupt-crash recovery and malformed-input/native sanitizer tests
- [x] Focused verification, baseline/final build comparison and CI
- [x] Make the validated CLI available and migrate configured film Bitfiles safely

Existing film media and unrelated shared-checkout changes must remain intact.

Final verification:

- 27 AV package tests passed together, then the focused 19-test unit suite passed
  after adding retained-release GC protection (28 distinct AV tests total).
- 31 original toolkit tests passed, including their native integrations.
- Native media regressions: 44 transcode + 20 delivery + 21 precision + 11 resume
  checks, plus the retry/delivery transaction spec.
- Delivery-contract parity passed compiled, native-interpreted and Ruby paths.
- Package namespace integration passed raw argv, nesting, help, dependency/lock
  precedence, installed fallback and archive contents.
- 601 malformed TWMS/metadata cases passed ASan + UBSan.
- Core documentation is current; git diff --check is clean.
- Final isolated build has the same pre-existing WARNING stage-identity line and
  the same stage hashes as the clean baseline; it is not a VERIFIED build.

The installed `/Users/erik/.local/bin/bit` symlink selects this worktree. Its
persistent Python environment is `build/av-python`. The four film-root Bitfiles
select this toolchain, retain existing scientific source gates, and deliver to
`render/av` without replacing the legacy workflow. Doctor and plan pass for
Egypt, Mesopotamia and China. Biblical Wisdom's plan is reviewable, but its full
render's estimated disk budget exceeds free space. No production film was
rendered or staged during implementation.

Scope details: colour support explicitly validates/rejects unsupported contracts;
it does not tone-map HDR. Text QC checks declared font layout and encoded ROI
retention, without an OCR claim. Bitrate search selects the lowest tested passing
candidate, with final-file gates still required. Crash/sanitizer evidence is a
bounded test campaign, not exhaustive validation.

Implementation was completed on `codex/bit-av`. Main integration uses a scoped
merge with staged/unstaged patch and working-file comparisons to preserve
unrelated work. Builds and validation run in isolated worktrees, with no shared
compiler rebuild.
