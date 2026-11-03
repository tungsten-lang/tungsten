# Robolab challenger results page

A portable, static report for the independent 27 September 2026 challenger campaign. Open `dist/index.html` directly, or serve the directory with video byte-range support:

```sh
.venv/bin/python results-page/serve.py --port 8769
```

Run from the Robolab root. The local page is at http://127.0.0.1:8769.

The page follows the supplied dark progress-report reference. It includes the five end-of-round-3 worktree champions, all 22 non-promotion arena comparisons, fresh validation and residual ablations, five playable champion videos, and readable report/evidence pages. It describes the campaign's frozen historical baselines; it does not claim to represent the main checkout's current board.

`build_data.py` exports data and assets from the existing audited campaign. To refresh those exports without changing the interface:

```sh
.venv/bin/python results-page/build_data.py
```

No external libraries, fonts, services, or build step are required to view the result. Keep the whole `dist` directory together. Existing research artifacts are read only. No commits were made.

Checked in the in-app browser at desktop and 390 px mobile width: all videos load; playback and jump-video selection work; the round filter and residual selector update; no page overflow or browser console errors. All five videos respond correctly to HTTP byte-range requests. Local asset references and the 22-entry evidence export were also checked.

The follow-up section separately presents nine main-arena cross-evaluations captured on September 28. `build_followup.py` adds round-4 results only when its summary exists and its audit passes. The original 22-entry ledger is preserved as a historical snapshot. Report, evidence, parameter and video links use normal navigation for artifact hosts that block downloads.

Round 5 is exported by `build_followup.py` only after its 24-check audit passes. `dist/round5.js` adds all 12 arena entries, 15 fresh validation/ablation groups, and the explicit inconclusive P6 result. No round-5 candidate qualifies for promotion. The portable bundle now contains 51 files; latest publication is not yet confirmed.

A guarded round-6 renderer is prepared and remains hidden until its summary and passing audit exist. The report opener now labels the original campaign as historical. The current bundle contains 52 files, superseding the earlier file count.

Round 6 is now audited and visible: six arena entries, nine fresh-validation groups, three direct family comparisons, and both 3 s and 8 s marks. None qualifies for promotion against both required incumbents. The current bundle has 56 files; desktop/mobile and all asset references pass. The next experiment is private and is not presented as a result.


Final campaign export (round 7): 67 files, 20 selected contenders, 52 arena entries and eight preserved promotion videos. Round 7 wins the P6 robustness comparison at 1.33965625 m (32/32, paired +0.0243125 m, 0/4000 sampled sign flips). Its longer recovery limitations remain visible. All 90 asset references pass; ZIP bytes match dist/. Desktop, 390 px mobile, expanded comparisons, report navigation, and the complete 20.033-second champion playback pass. Final evidence: ../out/gpt_campaign_final/{requirements_audit,bundle_verification,browser_verification}.json. Latest URL: http://127.0.0.1:8769/index.html#round7. The original published artifact predates these follow-ups; publication of the latest bundle is unconfirmed.

Round 8 export: 74 files, 58 arena entries, 22 selected candidates; no new promotion. All 101 asset references and ZIP parity pass. Desktop/390px mobile, expanded comparisons and report navigation pass. Latest local URL: http://127.0.0.1:8769/index.html#round8. The report also clarifies the conditional arms-only score and original right-hand phase baseline. The continuing improvement goal remains active.

Round 9 export: 86 files, 118 verified asset references, 64 arena entries, 24 selected candidates and nine promotion videos. The temporal crossover wins the 25-start trial at 9.08 versus 7.52 (paired +1.56, p=0.0065); the ten-start comparison and arms-only penalty do not qualify. All 32 fresh selected runs eventually lose control. All 30 research checks, desktop/390 px mobile layout, expanded details, report/evidence navigation and complete 15.033-second playback pass. Exact ZIP parity is recorded in out/competitor_dribble_round9/bundle_verification.json; browser checks are in page_verification.json. Latest local URL: http://127.0.0.1:8769/index.html#round9. Latest external publication and main import remain unconfirmed.

Round10 preparation adds a hidden audited-only renderer. The current portable bundle has87files and119verified references; only nine completed rounds remain visible. Actual R10 result rendering will be checked after training, validation, judging and audit. Preparation evidence is in out/competitor_dribble_round10/preparation/.

Round 10 is exported with 36 passing research checks, no promotions, 26 selected contenders and 70 arena entries. The bundle contains 93 files and128 verified references with exact ZIP parity. JavaScript syntax and deferred loading pass. Final R10 browser visual/interaction QA is pending because the browser runtime became unavailable; earlier R9 checks do not establish R10 rendering. Evidence: out/competitor_dribble_round10/{audit,bundle_verification,page_verification}.json. Latest local anchor is #round10; external publication remains unconfirmed.

R11 preparation is guarded and hidden until its audit passes. The current97-file bundle preserves70 completed arena entries and adds a scoped, source-pinned consumed-trace batting diagnostic: interior stride quiet improves while the99ms onset interval remains. The diagnostic figure was visually inspected. All135 references and exactZIP parity pass; currentpagebrowserQA remains pending whilebrowserunavailable. Latest bundle evidence: out/competitor_dribble_round11/preparation/bat-diagnostic-update/bundle_verification.json.

The latest98-file/137-reference bundle includes batting threshold sensitivity and the exact duplicate-preparation check. Two pitch seeds share one pre-release trajectory; temporal’s quiet-interval benefit is threshold-sensitive, and both corrections increase acceleration slightly. This qualifies the diagnostic rather than claiming improved smoothness. ZIP parity passes; browser QA remains pending. Evidence: out/competitor_dribble_round11/preparation/bat-sensitivity-update/bundle_verification.json.

Round 12 is visible after its focused audit passes: two bias-free fingered DribbleV3 retrains, six non-promoting arena entries, 64-start validation, and 30-second diagnostics. All three local and current-main incumbent replays match exactly. No champion changed. Refresh with `build_data.py`; the latest section is `#round12`.

Round 12 is visible after its focused audit passes: two bias-free fingered DribbleV3 retrains, six non-promoting arena entries, 64-start validation, and 30-second diagnostics. All three local and current-main incumbent replays match exactly. No champion changed. Refresh with `build_data.py`; the latest section is `#round12`.
