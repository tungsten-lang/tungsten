# AV quality and delivery improvements

Worktree: `~/tungsten-worktrees/av-pipeline-quality`, branch `codex/av-pipeline-quality`.
Base: `728199bcc`. Scope: requested follow-up items 2, 3, 5, 6, 7, 8, 9, 10.

- [x] Clean baseline and matching final stage-identity result
- [x] 2 Content-bound verification and coherent release-bundle promotion
- [x] 3 Native 10-bit decode/scale/encode path
- [x] 5 Rational-rate, cut, geometry and delivery-format orchestration
- [x] 6 Durable source/options-bound encoded-segment checkpoints and resume
- [x] 7 Metal 10-bit plane scaling with CPU agreement
- [x] 8 Visual residuals, contact sheets, temporal QC and share checks
- [x] 9 Process-group cancellation, stage deadlines and native wait cleanup
- [x] 10 Hermetic fixtures, fault tests and focused CI coverage

Builds run only in this isolated worktree. Existing film publications remain in place
until their replacement bundles are verified and promoted explicitly.


Validated in this isolated worktree for scoped main integration. The source commit
and main merge are recorded in Git history. The films' shared toolkit pointer
remains unchanged.
No production film media was rendered, published or staged by these checks.

## Verification

- Full Python suite with `RUN_AV_NATIVE=1`: **31/31 passed**, no skips.
  Includes generated fonts, NTSC seek/clock tests, background/flicker diagnostics,
  release rollback, candidate mutation, cancellation, and source-pointer races.
  The native fixture renders a non-default `custom/edit.json` preview cut at
  30000/1001 into PCM MOV master/Short/share deliveries: 60 frames, 96096 samples.
  It verifies and promotes a bundle, stages that exact source release, and rejects
  an incomplete replacement. Native worker tests cover both Process.spawn and
  OS.system descendants ignoring TERM.
- `media_transcode_spec.w`: **44/44**, `media_delivery_spec.w`: **20/20**
  (including four real 7680x4320 frames).
- `media_precision_spec.w`: **21/21**. Both 1- and 2-channel P010 identity paths
  retain fine codes; Metal Lanczos/bicubic/bilinear fractional crops agree with
  CPU within one 10-bit code. Includes depth conversion, padding, invalid strides,
  decoder cancellation, a stalled-decoder deadline and Main10-to-ProRes output.
- `media_resume_spec.w`: **11/11**. Real interruption/recovery at 30000/1001,
  a partial final GOP, sample-exact audio and later sync flash, chapters/drop-frame
  timecode, cache corruption, lock contention, changed source/options and
  cancellation including a fully reused cache. Native handle counts return to 0.
- Retry transaction and Process.spawn argv ownership focused specs passed.
- Portable delivery contract passed compiled, native-interpreted and Ruby lanes.
- Core reference generator check and `git diff --check` passed.
- Final isolated build completed and matched the clean baseline's line:
  `WARNING stage 1 and stage 2 .ll differ!`. Neither build was VERIFIED.
- Focused GitHub Actions workflow added for Linux/macOS toolkit tests and macOS
  native tests. Remote CI has not been run from this worktree.

Logs: `/tmp/avq-python-final.log`, `/tmp/avq-{transcode,delivery,precision,resume,retry,process-spec}.log`,
`/tmp/avq-parity-{compiled,native,ruby}.log`, `/tmp/avq-final-build.log`.

## Operational contracts

Existing authored scene generators default to their declared 24-fps clock;
non-24-fps generation requires an env-v1 generator or explicit matching
`scene_rate`. Rational-rate studio frame assets and all toolkit time/path/mix
calculations use the selected cut. Audio remains 48 kHz and a fractional sample
cut length is rejected. QC is sampled background verification, with adjacent
reference frames and normalized masks; it does not certify every picture.
Source files must remain immutable during a resumable job. For a coherent
multi-file release read, resolve `current` once and use its manifest/files.
See `tools/tw/README.md` and `doc/media.md` for configuration and APIs.
