# AV pipeline implementation

Request: `/Users/erik/videos/AV_PIPELINE_REQUESTS.md` (2026-10-31).
Worktree: `/Users/erik/tungsten-worktrees/av-pipeline-requests`.
Branch: `codex/av-pipeline-requests`, base `75855afae`.
Implementation and verification used this isolated worktree; no build was run
in the shared `~/tungsten` checkout.

- [x] Clean baseline build, then matching post-change stage-identity result
- [x] 1 Main10 profile / bit-depth validation; ProRes sample-entry checks
- [x] 2 Shared film + Short banding checks, caption masks and failure thresholds
- [x] 3 Bounded encode retry/backoff with atomic destination replacement
- [x] 4 Bounded asynchronous decoding; ordering, early close and error teardown
- [x] 5 Existing studio chapters/share wiring verified; shared toolkit adopts it
- [x] 6 Video edits flattened by default in studio; strict no-edit PCM MOV mode
- [x] 7 Real-frame ProRes, Main10 and 8K target probes
- [x] 8 HEVC Main/Main10 level pinning, verified in emitted hvcC
- [x] 9 Shared explicit-font / HarfBuzz ancient-script outlines
- [x] 10 Shared toolkit installed; four source films migrated with backups

## Verification

- `bin/tungsten build --no-bits`: clean baseline and final build both printed
  `WARNING stage 1 and stage 2 .ll differ!`. Both completed successfully. This
  is the same stage-identity *result*, not a VERIFIED fixed point or identical
  stage hashes. Logs: `/tmp/av-pipeline-{baseline,final-build}.log`.
- Existing `spec/core/media_transcode_spec.w`: **44/44**.
- New `spec/core/media_delivery_spec.w`: **20/20**, including all four ProRes
  targets, Main10, four 7680x4320 frames, explicit HEVC Main/Main10 level 4.1,
  mismatching-level rejection, exact PCM audio/video sync with no edit lists,
  signed-ctts video with AAC priming retained, callback teardown and no native
  handle leaks. Log: `/tmp/av-delivery-spec.log`.
- `spec/core/media_retry_spec.w`: deterministic two-retry recovery, bounded
  exhaustion, preservation of an existing output and temporary-file cleanup.
- `spec/parity/media_delivery_contract_spec.w`: compiled, native-interpreted
  and Ruby validation helpers all pass (including equivalent level labels).
  Media encoding itself remains compiled-only. Ruby verification used isolated
  runtime gems under `/tmp/av-ruby-gems`; no global Ruby installation was changed.
- Shared toolkit Python checks: **10/10**, including synthetic banding/dither,
  caption/blur margins, missing-background failure, exact NTSC frame selection,
  four ancient scripts, missing-glyph rejection, migration ordering and publication
  failure behavior. Tests are under `apps/studio/tools/tw/tests/`.
- Existing film and Short smoke samples: two frames each from ancient Egypt,
  ancient Mesopotamia, ancient China and Biblical Wisdom: **8/8 reports pass**.
  Reports: `/tmp/av-real-banding/`. These samples are not whole-film certification;
  normal render/publish gates use the configured full sample selection.
- Tiny studio episode: 48 real rendered/encoded frames, two chapters; mux,
  Main10 share override, studio verify **16/16**, strict PCM MOV mux, and public
  `media verify --no-edit-lists` all pass. Actual strict output has **0 edts boxes**.
  Log: `/tmp/av-studio-integration-final.log`.
- Shared `tw_mix.w`, `tw_bg.w` and `tw_jpeg.w` compiled and ran. The mix preserved
  the source's PCM bytes exactly and padded to 96,000 samples; JPEG dimensions
  checked. Migrated `tools/tw_mix.w` compatibility import lowers successfully.
- `ruby scripts/gen_core_doc.rb --check`: current (677 classes/traits).
- `git diff --check`: clean.

## Decoder measurement

Frozen release binary `/tmp/av-decode-bench`, frozen 20-second 1080p HEVC Main10
clip `/tmp/av-decoder-source.mp4`, 480 decoded frames per trial. Three serial and
three asynchronous trials, interleaved; frame indices checked on every read.

| Mode | Median seconds | Median fps |
| --- | ---: | ---: |
| Former per-frame wait (`TUNGSTEN_MEDIA_DECODER_SERIAL=1`) | 0.7130 | 673.2 |
| Bounded asynchronous batches | 0.3988 | 1203.5 |

This is **1.79x decoder throughput** on this local clip, not an end-to-end share
encode speed claim. Results: `/tmp/av-decode-results.json`. Reproduce with
`benchmarks/media/decode_bench.w` and a release build.

## HEVC pinning evidence

The runtime advertised only AutoLevel enums, but explicit names such as
`HEVC_Main10_4_1` were accepted and emitted general_level_idc **123**; 4.0 emitted
120, 5.1 emitted 153, while AutoLevel emitted 93 for the same 720p pictures.
A bogus string was accepted by SetProperty but emitted the auto level, which
is why the implementation verifies hvcC on each segment's first output.
The probe sources/logs are `/tmp/av-vt-level-{probe,encode}.{m,log}`.

## Delivery limitation

AAC priming/trimming edits cannot simply be deleted while retaining sample-exact
sync. `edit_lists: :audio` removes the video edit with signed ctts and keeps AAC
edits. Strict `edit_lists: false` supports PCM in MOV and chapters starting at
frame 0; it rejects unrepresentable edits. Studio CLI:

```sh
studio mux episode.json --out master.mov --audio-codec pcm --no-edit-lists
studio verify master.mov --resolved timeline.resolved.json --no-edit-lists
```

## Shared toolkit migration

`~/videos/tools/tw` points to the versioned `apps/studio/tools/tw` directory here.
Migrated films:

- `civilizations-in-mathematics/ancient-egypt`
- `civilizations-in-mathematics/ancient-mesopotamia`
- `profiles-in-philosophy/ancient-china`
- `profiles-in-philosophy/biblical-wisdom`

Each keeps `tools/tw.json` plus compatibility wrappers/symlinks. The common render,
Short orchestration, thumbnail, publish, plate, mix, JPEG and animation-cache tools
are shared. Authored scene/compositor code, narrative importers and per-film data
preparation remain film sources. Biblical Wisdom's repeated layout/cue passes and
Egypt's numerical/Satori gate were preserved. Other films retain their current
scripts and can be migrated with the checked installer after their settings are
reviewed; they were not silently replaced by a generic layout.

Original files: `~/videos/tools/tw-migration-backups/20261031T130117587576/`.
No existing film media was re-rendered, published or staged for this migration.
Commit and merge state is recorded in Git. No remote push was performed.
