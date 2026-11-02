# Native AV library port

Native source and active execution are in `/Users/erik/tungsten` on main.
The installed launcher `/Users/erik/.local/bin/bit` points to its `bin/bit`,
and the four existing film Bitfiles select `/Users/erik/tungsten`.
Initial port verification used an isolated worktree; it is no longer selected
for AV execution.

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

Initial port checks passed: 34 native unit checks; 7 banding checks; 6 source
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

The initial port's clean HEAD and final builds both print
`WARNING stage 1 and stage 2 .ll differ`. The port build completed; it is not
reported as `VERIFIED`. Evidence is in
`/tmp/av-native-baseline-build.log` and `/tmp/av-native-main-merged-build.log`.

The November 1 activation selected the port worktree for the launcher and four
film Bitfiles. Those settings and their hashes are backed up under
`/tmp/av-native-activation-20261101T085706Z/`. At that check, all four read-only
plans were valid; two were blocked by disk-budget gates. This historical
activation was replaced by the main-checkout selection below.

Main integration preserved the byte-identical staged patch and all 225 existing
dirty paths. Overlapping working edits were merged; the in-progress Regex split
was retained and the AV fixes were applied to its existing worker. Backups,
prepared results and the audit manifest are under
`/tmp/av-main-integration-20261101T160619Z/`.

On November 2, the user explicitly authorized removing the main-checkout guard
and switching execution to `/Users/erik/tungsten`. The guard is removed. The
launcher and all four project selections were switched atomically, with their
previous settings backed up under `/tmp/av-main-execution-switch-20261102T065446Z/activation.json`.
Installed package resolution recognizes `tungsten-NAME` folders whose Bitfile
declares the shorter command namespace `NAME`.

Main-execution verification resolves all 20 implementation paths under
`/Users/erik/tungsten`. All four film plans pass preflight with that toolchain.
The six native source acceptance checks pass, including rendering, delivery,
verification, failed-QC preservation and bounded quality search with Python
absent. The timeline fixture passes its initial render, alternate Short,
exact-font burn, encoded ROI/anomaly QC, resume and frozen verification.
Earlier attempts correctly stopped with `toolchain changed during job` during
concurrent edits; the implementation-identity check remains enabled. A full
live-checkout bootstrap attempt failed in the excluded Unicode/encoding work.
The scoped stable-source snapshot builds with the same stage-identity warning
as clean HEAD. These checks do not certify the in-flight group. No full film
render was requested or run.
