# Native AV library port

Native source is integrated into `/Users/erik/tungsten` on main, merge commit
`35b6c990b`. The clean build/test toolchain is in
`/Users/erik/tungsten-worktrees/av-native`. The installed AV package resolves
directly to `/Users/erik/tungsten/bits/tungsten-av`.

- [x] Flat native library files directly under `bits/tungsten-av/lib/`
- [x] Individual `Tungsten:Bit:Command` subclasses and package discovery
- [x] Reuse tungsten-bit Bitfile parser; AV schema and profile dependency plans
- [x] Native snapshots, locks, resource budgets and process supervision
- [x] Native source/timeline rendering, audio preparation and metadata
- [x] Native final-file audio, text, anomaly and banding QC
- [x] Native bounded bitrate search and verified atomic releases
- [x] Init/files/status/verify/qc/share/short/quality/publish/stage/gc commands
- [x] Remove Python runtime modules, environment selection and dependencies
- [x] Native unit/integration/crash checks with Python absent from PATH
- [x] Installed package imports and rendering outside the source checkout
- [x] Documentation, CLI activation and four film toolchain-path migrations
- [x] Shared Bitfile parser parity on compiled, native interpreted and Ruby engines
- [x] Commit and integrate into main while preserving unrelated edits

Shared Bitfile namespace tests passed 22 checks on each of the compiled, native interpreted and Ruby engines. The conditional-capture/lexical-scope regression also passed all three. The combined-main typed-array guard check passed 594 assertions.

Final focused checks passed: 34 native unit checks; 7 banding checks; 6 source
acceptance checks; installed timeline/alternate Short, exact-font caption burn,
encoded ROI/anomaly QC, resume and frozen verification; audio PCM formats;
3 crash/cancellation checks; C companion source/header cache invalidation;
public library imports; bundled Bit:Command imports on all three engines;
package namespace dispatch and packaging. The package archive includes flat
`lib/*.w`, command classes and `native/platform.c`. Ruby drives development
checks only. FFmpeg/FFprobe remain explicit independent media/QC tools.

The port exposed File path/link gaps, grouped ternary/suffix precedence,
typed default argument and boxed static-return bugs, Regex VM sentinel and
bounded repetition/line-anchor bugs, stale companion caches, foreign-checkout
runtime selection, bundled-bit imports, Ruby namespaced superclass parsing,
long JSON numeric accumulation, conditional closure parameter capture, and lexical class lookup inside interpreted closures. These are fixed at their sources with
focused regressions. File paths, grouped ternaries, typed defaults, namespaced
inheritance and JSON numeric precision passed compiled, native interpreted and
Ruby checks. Regex passed compiled/native interpreted checks and a Ruby literal
semantic reference; Ruby's CoreRegex bytecode bridge remains unsupported.
The full JSON spec passes compiled/native interpreted; Ruby's existing raw
string-pointer bridge failure was reproduced at clean HEAD. The focused numeric
regression passes Ruby as well.

Clean HEAD and final builds both print `WARNING stage 1 and stage 2 .ll differ`.
The final build completed; it is not reported as `VERIFIED`. Evidence is in
`/tmp/av-native-baseline-build.log` and `/tmp/av-native-main-merged-build.log`.

The active `/Users/erik/.local/bin/bit` points to this tested worktree. Four
existing film Bitfiles now select this toolchain. Previous settings and their
hashes are backed up under `/tmp/av-native-activation-20261101T085706Z/`.
Read-only plans are valid for all four films. At the final check, Mesopotamia
and China satisfy disk estimates; Egypt and Biblical Wisdom are blocked by
their disk-budget gates. No full film render was requested or run in this port.

Main integration preserved the byte-identical staged patch and all 225 existing
dirty paths. Overlapping working edits were merged; the in-progress Regex split
was retained and the AV fixes were applied to its existing worker. Backups,
prepared results and the audit manifest are under
`/tmp/av-main-integration-20261101T160619Z/`.

The AV package loads from main through the tested isolated compiler/rendering
toolchain. The existing guard against selecting `~/tungsten` as an AV execution
toolchain remains in place. No compiler binary in the dirty shared checkout was
replaced. Installed package resolution also recognizes `tungsten-NAME` folders
whose Bitfile declares the shorter command namespace `NAME`.
