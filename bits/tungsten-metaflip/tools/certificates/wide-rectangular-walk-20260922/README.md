# Rectangular wide-walk certificates (GF(2))

`9x5x20-r623.mfw` is a complete 623-term tensor decomposition of
matrix multiplication over GF(2), in MFW1 factor order `U(9x5) V(5x20)
W(9x20)`. Its canonical SHA-256 is
`04deeee17b7cd975f233aa9d952d988409266d2b91d60f44252df940925f0df5`.
This is a one-term improvement on the rank-624 structured-parent candidate;
it is not an optimality or global novelty claim.

The first pass used every one of the 81 compact portfolio rows as an exact
seed, with 10 million directed moves and nonce 19071 per row. Exactly three
rows dropped rank in that finite pass: 9x5x20, 12x10x20, and 16x28x25.
The other 78 did not drop in this budget; that is not evidence of optimality.

`12x10x20-r1448.mfw` is a complete 1448-term decomposition in factor order
`U(12x10) V(10x20) W(12x20)`, with canonical SHA-256
`ce1223857ec1c7bf2215b248a5cbeb42c4171df2c648ee7d752fd9f822741df8`.
It improves the structured-parent rank 1464 by 16 terms. Among the verified
rank-1448 continuations, this retained representation has the lowest density
(74455); density was an archive tie-break, not a walk acceptance gate.

`16x28x25-r6223.mfw.gz.b64` retains a complete 6223-term tensor with SHA-256
`049d2676a8f0e9c560026c5ad511faadc14debd415cc5d6d6c97e3407f3e3923`
after base64 and gzip decoding. Its factor order is `U(16x28) V(28x25)
W(16x25)`. It improves the rank-6225 structured-parent candidate by two
terms. The 1.77 MB MFW1 text is stored as about 186 KB of encoded compressed
text so the repository need not carry the full-width archive verbatim.

`12x10x25-r1836.mfw.gz.b64` retains a complete 1836-term tensor, canonical
SHA-256 `9f6e46e1cbbf99417ab2f1ae3c36a92260809ef313e6540eabcaa065baab7c58`,
in factor order `U(12x10) V(10x25) W(12x25)`. It comes from exact replay of the
`10x12x25` structured-parent row followed by an axis-0 reverse shared-factor
refactor. The refactor preserves rank and lowers density from 92102 to 91648;
density was an archive tie-break, not a search acceptance gate. Matched 50
million-move walks from both the original and refactored seeds, plus two
20-million-move walks from other refactors, found no lower rank in those
finite budgets.

Two exact coordinate projections of these retained tensors, followed by
GF(2) duplicate cancellation and shared-factor compression, improve further
rectangles. Deleting coordinate 19 (zero-based) of the output axis of the
12x10x20 certificate gives a rank-1421 tensor. Two exact same-rank refactors
(axis 0 forward, then axis 1 forward) give the retained
`12x10x19-r1421.mfw.gz.b64`, SHA-256
`a184dc5aeb7a90d5e88af72a4ec4eb73f58888ea9ce0caa5159b533ed0724de5`,
density 69756. The pinned catalog plus compact-parent portfolio priced that
shape at 1451. Deleting coordinate 27 of the middle axis of the 16x28x25
certificate gives an exact rank-6129 seed. A directed 10-million-move walk
with nonce 19071, then four 50-million-move continuations with nonces
19072 through 19075, reached rank 6080. Two exact same-rank refactors
(axis 0 reverse, then axis 2 forward) give the retained
`16x27x25-r6080.mfw.gz.b64`, SHA-256
`7d6bdd7c300602617ad8f9c52b3638210391699394e69c55d7b86dc12bfd2ce3`,
density 231672; the previous finite composition price was 6195. Both tensors
were separately expanded by the Ruby verifier and the independent Python
certificate test. These are exact GF(2) decompositions, not global record or
optimality claims.

Replaying the `16x25x32` structured-parent row produces an exact rank-7055
tensor in factor order `U(16x32) V(32x25) W(16x25)`. Coordinate projection,
exact shared-factor refactors, and bounded directed walks produce
`16x31x25-r6916.mfw.gz.b64`, canonical SHA-256
`a31cfc6638245c110fcba943c4ed948889915210be74ced9d2c8f12b057e4e41`,
density 267253. Continuing through a projected 16x30x25 intermediate produces
`16x29x25-r6534.mfw.gz.b64`, canonical SHA-256
`bb01d2f6b1516808bc22a9edfd3ca2a0b36da9ea9c440a46846a07a22c0cad78`,
density 254205. The intermediate reached rank 6745, but is not retained as a
rank candidate: the pinned GF(2) catalog already has rank 6690 for 16x25x30.
Both retained tensors were independently expanded by the Ruby verifier and
the focused Python certificate test.

Replaying the `8x20x30` structured-parent row yields rank 2803. Deleting
coordinate 14 of its middle axis, cancelling equal GF(2) terms, and applying
exact shared-factor compression yields `8x19x30` at rank 2743. Two exact
refactors lower it to 2729. Bounded walks of 50 million moves (nonce 19073)
and 100 million moves (nonce 19077) lower it to 2724 and 2723, respectively.
The retained same-rank refactor is `8x19x30-r2723.mfw.gz.b64`, SHA-256
`519e99587c73888bbc011a5a11c7342fcae631e79d591b077e52d3749772fc7a`,
density 84555. The prior pinned GF(2) catalog-plus-portfolio composition price
was 2766. This certificate is checked by both full-tensor verifiers; the
finite walk is not an optimality proof.

Deleting last-axis coordinate 16 from the same exact `8x20x30` parent and
compressing equal GF(2) terms gives `8x20x29:2744`. A 50-million-move walk
(nonce 19233) lowers this to 2726, and a 100-million-move continuation
(nonce 19235) reaches the retained `8x20x29:2724`, SHA-256
`b1f26cb283b84ba01d699007abe162318569afa6e9c3fdcdb02fbf44577e0a16`.
Both full-tensor verifiers accept it. The prior pinned closure price was 2745;
the current Lille table lists 2800. Direct and 19-context basis projection
screens of the retained tensor found no further closure improvement in their
bounded runs.

A different projection of the same exact `8x20x30` parent gives a verified
`7x20x30:2638` seed. A 50-million-move directed walk (nonce 19237) reaches
rank 2623; a 100-million-move continuation (nonce 19239) reaches the retained
`7x20x30:2622`, canonical SHA-256
`2321df5be27cdd71032b79a94adbf7a6b7e08d9e6e99128dab599de57963b223`,
density 93225. A basis sweep of the rank-2623 representation exposes an exact
`7x19x30:2562` projection; a 50-million-move walk (nonce 19241) lowers it to
rank 2541. A different exact same-rank refactor (mode 10) ties 2541 in 50
million moves (nonce 19253), then 100-million-move continuations (nonces
19259 and 19261) lower it to the retained rank 2538, SHA-256
`005b9d101f493eb6cd6386479099ad10c106940d682ab7c2e7d6302ff5a59d13`.
A basis projection from the intermediate rank-2539 tensor gives an exact
`7x18x30:2465` seed; two 50-million-move walks (nonces 19265 and 19269)
reach rank 2453. That intermediate is superseded by the separate parent below
and is not retained. The retained `7x20x30` and `7x19x30` tensors pass
independent full GF(2) verification. Their pinned composition prices were
2629 and 2563, respectively. These finite walks do not establish optimality
or worldwide novelty; the Lille table currently lists 2532 for `7x19x30`.

Replaying the `8x18x30` structured-parent row gives an exact `8x30x18:2526`
tensor. First-axis coordinate 6 projects to a verified `7x30x18:2408` seed;
a 50-million-move walk (nonce 19343) reaches the retained rank 2374, SHA-256
`0645becb3abaf003bbe7fe60d3b139ff0079f7345e4367ce41accd8ac364dd76`,
density 114693. A 100-million-move continuation (nonce 19347) ties it.
Middle-axis coordinate 0 of the parent gives retained `8x29x18:2498`, SHA-256
`deb90236cda251a21c9576d17eebb647755f3dac5490529f2cd9899c288f9d89`;
its 50-million-move walk (nonce 19349) ties. A basis projection of the
rank-2374 child gives `7x29x18:2350`, and a 50-million-move walk (nonce
19351) reaches rank 2341. A separate middle-axis coordinate-3 projection
of the rank-2374 child gives rank 2352; a 50-million-move walk followed by
a 100-million-move continuation (nonce 19377) reaches retained rank 2340,
SHA-256
`614a99ac97e54556895bcf7aa22dae1462f9bab4a1e3c05e570a72be4fab7773`.
All three pass independent full GF(2) verification. The pinned composition
prices were 2467, 2550, and 2390; the current Lille table lists 2375, 2535,
and 2317. Thus the first two numerical ranks beat that table, not a complete
worldwide or cross-field novelty audit.

An exact one-coordinate projection scan over 4486 structured-parent portfolio
cases produced candidates below the pinned closure in 70 distinct shapes.
Three projected parents were retained and then improved by a 19-context exact
shared-factor basis sweep followed by matched 50-million-move walks:
`11x28x25:4533→4527→4518` (from `12x25x28`, nonce 19411),
`16x23x15:3168→3165→3164` (from `15x16x24`, nonce 19413), and
`11x16x30:3107→3106→3105` (from `12x16x30`, nonce 19417).
The rank-4518 tensor projects to `11x27x25:4443`, walked to 4426 (nonce
19429), and `11x28x24:4425`. The rank-3164 tensor projects to
`16x23x14:3017`, walked to 3003 (nonce 19423), `16x22x15:3083`, walked
to 3071 (nonce 19431), and `15x23x15:3095`. The 11-row family also retains
`11x16x29:3045`, walked to 3034 (nonce 19427), and `11x15x30:3041`.
All ten retained tensors pass independent full GF(2) expansion. Relative to
the previously retained rank-4533, rank-3168, and rank-3107 parent seeds,
these refinements affect 84 shapes and save 1911 further rank units. Lille's
current table entries are 4572, 3238, 3126, 4431, 3071, 3168, and 3067
for the retained shapes `11x25x28`, `15x16x23`, `11x16x30`, `11x25x27`,
`14x16x23`, `15x16x22`, and `11x16x29`, respectively; the corresponding
certificates are numerically lower. This is not an audited worldwide or
cross-field novelty claim.

Continuing those exact tensors through one more 19-context basis/projection
generation gives eight retained descendants. From `16x23x14:3003`, the
`16x23x13` projection reaches 2795 and a 50-million-move walk (nonce 19441)
reaches 2776; `16x22x14` similarly goes 2929→2922 (nonce 19443). From
`11x16x29:3034` comes `11x16x28:2946`, while `11x27x25:4426` yields
`11x26x25:4327` and `11x27x24:4327`. Finally, the rank-2776 tensor yields
`16x23x12:2533→2511` (nonce 19447), `16x22x13:2713→2692` (nonce 19449),
and `15x23x13:2718`. Each saved tensor passes independent full GF(2)
expansion. This tranche affects 86 shapes and saves 5253 further rank units
against the preceding pinned closure. Its `13x16x23:2776`,
`14x16x22:2922`, `12x16x23:2511`, and `13x16x22:2692` ranks are
numerically below Lille's listed 2863, 2961, 2552, and 2757, respectively;
that comparison is not a worldwide or cross-field novelty claim.

The next bounded generation projects those retained exact tensors and checks
19 same-rank shared-factor basis contexts per parent. From `16x23x12:2511`,
projection gives `16x23x11:2430`, walked to the retained rank 2412 (50 million
moves, nonce 19451); a further 100-million-move continuation tied. The same
parent gives `16x22x12:2451`, walked to 2444 (nonce 19459), and
`15x23x12:2452`, walked to 2443 then 2442 (nonces 19461 and 19463); a further
100-million-move continuation tied. Projecting `16x22x13:2692` gives
`16x21x13:2627`, walked to 2616 (nonce 19455). Projecting the rank-2412
tensor gives `16x22x11:2353`, walked to 2342 (nonce 19465). Finally,
`11x26x25:4327` projects to `11x25x25:4227`, walked to 4205 (nonce 19457).
The six retained complete GF(2) tensors are independently expanded by both
verifiers. They affect 42 shapes and save 1673 further rank units against the
preceding pinned closure; total retained closure impact is 363 shapes and
18880 rank units. The 11x16x23, 13x16x21, 12x16x22, and 11x16x22 oriented
ranks (2412, 2616, 2444, 2342) are numerically below the Lille table's
2434, 2657, 2499, and 2360 entries at this audit. This is neither a
worldwide/cross-field novelty claim nor an optimality proof.

One further bounded projection generation retains three complete tensors.
`15x23x12:2442` projects to `14x23x12:2348`, walked to 2326 and 2323
(50 million and 100 million moves, nonces 19469 and 19475), and to
`15x22x12:2381`, walked to 2375 (nonce 19471); its 100-million-move
continuation (nonce 19477) tied. `16x21x13:2616` projects to
`16x21x12:2396`, walked to 2380 and 2379 (nonces 19473 and 19479).
All three retained results pass both independent full-tensor verifiers. They
affect five shapes and save 165 further rank units against the preceding
closure, raising the cumulative retained impact to 367 shapes and 19045
rank units. The oriented `12x16x21:2379` is numerically below Lille's 2385
entry at this audit; no worldwide or cross-field novelty is claimed.

A distinct 11-row branch starts from retained `11x16x28:2946`: its 19-context
basis sweep reaches rank 2934, and a 50-million-move walk (nonce 19483)
reaches retained `11x16x28:2929`. A projection in that same basis sweep
gives `11x16x27:2842`; its 50-million-move walk (nonce 19481) reaches 2825.
That child projects to `11x16x26:2722`, walked to 2701 (nonce 19487).
Separately, retained `20x27x11:3545` projects to `19x27x11:3471`, walked to
3448 (nonce 19485). All four results pass both independent full-tensor
verifiers. Their finite composition effect is 19 shapes and 948 saved rank
units against the preceding closure, raising cumulative impact to 378 shapes
and 19993 rank units. The oriented `11x16x27:2825` and `11x16x26:2701` are
numerically below Lille's 2847 and 2744 entries at this audit. A further
`19x26x11:3377` projection was exact but added no closure benefit once the
four retained tensors were included, so it was not archived. No worldwide,
cross-field, or optimality claim follows from this finite comparison.

Continuing the 11-row branch, 19 exact basis contexts of `11x16x26:2701`
expose a `11x16x25:2598` projection. A 50-million-move directed walk
(nonce 19489) reaches the retained complete tensor `11x16x25:2582`, checked
by both independent full GF(2) verifiers. Against the preceding pinned
closure it affects 14 shapes and saves 602 rank units, raising cumulative
impact to 385 shapes and 20595 rank units. Its rank is numerically below
Lille's 2643 entry at this audit; no worldwide or cross-field novelty is
claimed. A separate 19-context scan of `20x25x13:3890` found only a
one-unit same-shape cleanup, which was not retained.

Replaying the `15x20x28` structured-parent row yields a rank-4700 tensor in
factor order `20x28x15`. Deleting coordinate 13 of the first axis and applying
exact GF(2) cancellation/compression yields `19x28x15` at rank 4600; exact
refactoring lowers it to 4598. A 50-million-move walk (nonce 19101) reaches
4576; the 100-million-move continuation (nonce 19107) does not lower rank.
The retained same-rank refactor `19x28x15-r4576.mfw.gz.b64` has SHA-256
`20554ab7fe74e6a977ad7612274843926e79b18bbd2f3f168bf103b0cbc2ca86`
and density 150216. Deleting coordinate 7 of the last axis of the same
rank-4700 parent yields `20x28x14` at rank 4503 after exact compression;
refactoring lowers it to 4491. A 50-million-move walk (nonce 19103) reaches
4485 and a 100-million-move continuation (nonce 19109) reaches 4484. The
retained same-rank refactor `20x28x14-r4484.mfw.gz.b64` has SHA-256
`10b966b8ceeb69bdf506007eb026df28df0aed4d6c118a5593e991a915ce8091`
and density 144255. Prior pinned GF(2) catalog-plus-portfolio prices were
4682 and 4530 for the two projected shapes.

Projecting output-axis coordinate 7 (zero-based) of the verified
`20x28x14` tensor and applying exact GF(2) shared-factor compression gives
`20x28x13` at rank 4188. Two bounded basis sweeps reduce it to 4180; directed
walks of 50 million, then 100 million, then 100 million moves (nonces 19115,
19117, 19119) reduce it to 4172, 4168, and 4167. The retained
`20x28x13-r4167.mfw.gz.b64` has SHA-256
`dbbcfd9d67a9c7a51927f6b0e7cdf72f2df419fb136e2a9cde04743d6749e986`.
The pinned GF(2) catalog-plus-portfolio price was 4271. The other two
one-coordinate projections of the same parent that were tested here are
exact, but the pinned catalog already derives lower ranks for their shapes.

A follow-up scan tested all 749 one-coordinate projections of the 13 retained
rectangular certificates, using exact cancellation and shared-factor
compression. Four projected shapes improved the pinned GF(2) composition
prices. From `20x28x13`, first-axis coordinate 3 gives `19x28x13` at rank
4093; two bounded basis sweeps reach 4071 and a 50-million-move walk (nonce
19125) reaches the retained rank 4068, SHA-256
`15e461d7172163885bc5a51485d6de238e42ca783f02adc786bb9c85947c53e5`.
From the same parent, middle-axis coordinate 15 gives `20x27x13` at rank
4105; two basis sweeps reach 4097 and a 50-million-move walk (nonce 19131)
reaches the retained rank 4092, SHA-256
`23a9d6e38925bfaecdccf3f3dc9f400dfd68b2f66f3fb4ab8e5aa1b032e4cc3d`.
From `8x19x30`, last-axis coordinate 16 gives `8x19x29` at rank 2663; two
basis sweeps reach 2654, then 50-million and 100-million-move walks (nonces
19129 and 19137) reach the retained rank 2642, SHA-256
`cf97d17f4b857e83df6e97541938e545f4a3ad03ce981d828a189df90099c633`.
From `19x28x15`, middle-axis coordinate 21 gives `19x27x15` at rank 4507;
two basis sweeps reach 4495 and a 50-million-move walk (nonce 19141) reaches
the retained rank 4488, SHA-256
`6547c40d267aed101dae2f3a2d91e5d3ded8198e586a5a4ea1f46af701b41feb`.
The latter improves the pinned GF(2) composition price but not the currently
served Lille table entry of 4485. The other three beat that table's entries
for 13x19x28 (4096), 13x20x27 (4160), and 8x19x29 (2696). All four
certificates are checked by the Ruby and independent Python full-tensor
verifiers; finite walks are not optimality proofs.

A further scan of 237 one-coordinate projections from those descendants
produced four retained certificates. Projecting middle-axis coordinate 25 of
`19x28x13` gives `19x27x13` at rank 4001; two bounded basis sweeps reach 3988,
and a 50-million-move walk (nonce 19145) reaches rank 3969, SHA-256
`ac2739d03b5231470050263c8677bfb25e283daebccdb5a6d9c7a180360d75d8`.
Projecting middle-axis coordinate 19 of `20x27x13` gives `20x26x13` at rank
4002; two basis sweeps reach 3999, and a 50-million-move walk (nonce 19147)
reaches rank 3991, SHA-256
`f115d6847bd5bd894ca59183e527a286e03f5ae4383f3dc38e24fca51ef56490`.
Projecting last-axis coordinate 6 of the same parent gives `20x27x12` at rank
3715; two sweeps reach 3711, and a 50-million-move walk (nonce 19149) reaches
rank 3699, SHA-256
`21e6b32af7808c961b33afa0357113cc019ef482e3caa8ca4d1710360ccece48`.
Projecting last-axis coordinate 15 of `8x19x29` gives `8x19x28` at rank 2579;
two sweeps reach 2566, and a 50-million-move walk (nonce 19151) reaches rank
2554, SHA-256
`bb5dc75988081487d8818f0199bda6cd424022a0ce07eaad1278f93143704da5`.
The prior pinned GF(2) composition prices were 4077, 4076, 3735, and 2590.
All four decompositions are retained in factor order and independently checked.

Scanning all 232 one-coordinate projections of those four certificates yields
five more improvements on the pinned closure. The retained factor-order ranks
are `19x26x13:3874`, `20x25x13:3890`, `20x27x11:3545`, `7x19x28:2384`,
and `8x19x27:2464`, with SHA-256 respectively
`36a042fbf9a75a2910694a46343a9ffa5b79af5aace59d9d9562365e065ca3f0`,
`6a709719b5fe039baea4e1b97da45a2cd022c5d4a63345dec56da478dd6bcd59`,
`86d8bac9048e7fd74c7a9dd9cf8dc029c555e32cba44622c7803ec3dcb96433c`,
`91f691c6acbf09d16ecc819c77d1f7dce5fc8bd14cae307d17a14fbcde4d9e3a`,
and `0acee2a6eebe372fb9f395a6b7f91b88361dfc51efcce955b467ba8aaa2c9072`.
The source projections remove, respectively, middle coordinate 4 from
`19x27x13`, middle coordinate 16 from `20x26x13`, last coordinate 1 from
`20x27x12`, first coordinate 6 from `8x19x28`, and last coordinate 13 from
`8x19x28` (all zero-based). Exact shared-factor compression gives ranks 3905,
3919, 3555, 2414, and 2485; two bounded basis sweeps give 3899, 3915, 3550,
2403, and 2477. A 50-million-move walk each (nonces 19153 through 19161,
step 2), then a 100-million-move continuation each (nonces 19163 through
19171, step 2), gives the retained ranks. The pinned composition prices before
these five additions were 3964, 3936, 3559, 2442, and 2516. Every saved
certificate passes the Ruby and independent Python full-tensor checks.

Scanning all 282 one-coordinate projections of those five certificates yields
another five improvements on the pinned closure. The retained factor-order
ranks are `19x25x13:3766`, `8x19x26:2366`, `7x19x27:2298`,
`19x26x12:3493`, and `7x18x28:2287`, with SHA-256 respectively
`79e591467c80ba62f290c8613da4320706707a5847da568737e177de3a47b5de`,
`bbade19dd1133fe2bca1ec529ce7787ab59b1f6d76360786c48aa0b81581e5d3`,
`0cc954e1b7f0e5455cf29df9e20b45ab12505a3ca0dd1c3b976f5591882d18e7`,
`748e38f85e567644c495f46706ba4aeb2fdc9d1d25f46fb997557e1eb8d7103a`,
and `72d219a018cb0713080e7e384b1f7ca2215043537c93dccb81f5a154c21b1ebb`.
The source projections remove, respectively, middle coordinate 17 from
`19x26x13`, last coordinate 13 from `8x19x27`, first coordinate 6 from
`8x19x27`, last coordinate 6 from `19x26x13`, and middle coordinate 18 from
`7x19x28` (all zero-based). Exact compression gives ranks 3785, 2385, 2324,
3523, and 2310; two bounded basis sweeps give 3777, 2374, 2316, 3519,
and 2301. A 50-million-move walk each (nonces 19173 through 19181, step 2)
gives 3766, 2368, 2300, 3497, and 2287. The second, third, and fourth
receive 100-million-move continuations (nonces 19183, 19185, 19187), giving
2366, 2298, and 3493. Two further 100-million-move 7x19x27 walks (nonces
19189 and 19191) do not lower rank; the retained nonce-19191 tie has the
lowest checked density, 73408. The prior pinned composition prices for these
five shapes were 3828, 2419, 2347, 3533, and 2316. Every saved tensor is
independently verified; the finite walks are not lower-bound proofs.

A further one-coordinate scan of those five certificates tested 273 exact
projections. It produced `8x19x25` at rank 2273 by deleting last-axis
coordinate 13 of the retained `8x19x26`; a 50-million-move directed walk
(nonce 19193) reached the retained **rank 2267**. Deleting last-axis
coordinate 13 of `7x19x27` gave `7x19x26` at rank 2231. The next bounded
generation projected these witnesses to `8x19x24:2144` and `7x19x25:2126`
by deleting last-axis coordinate 12 from each. Further exact projections gave
`7x19x24:2010` (last-axis 12 from `7x19x25`), `8x19x23:2105` (last-axis 20
from `8x19x24`), and `8x18x24:2080` (middle-axis 9 from `8x19x24`). From
`8x19x23`, deleting last-axis coordinate 21 gave rank 2053 at `8x19x22`;
another 50-million-move walk (nonce 19197) reached the retained **rank 2034**.
Finally, deleting middle-axis coordinate 4 of `8x18x24` gave `8x17x24:1975`,
and deleting its last-axis coordinate 20 gave `8x17x23:1936`. Every
projection used GF(2) cancellation and exact shared-factor compression; the
two walks independently verified both their input and output tensors. Another
100 million moves from the rank-2267 `8x19x25` witness did not lower rank.

An 18-context basis follow-up improved several of the initial children.
`7x19x26:2231` dropped to 2219, then 2217 in a second sweep; a directed
50-million-move walk (nonce 19199) reached the retained **rank 2209**. A
further 100-million-move continuation (nonce 19201) tied that rank. A
rank-tied basis variant of `8x19x25:2267`, projected at last-axis coordinate
12, gave the retained `8x19x24:2143`; a separate sweep of its rank-2144
predecessor also reached 2143. The retained `7x19x25:2122` comes from a
basis sweep of its rank-2126 seed. The selected variants of these two shapes
have more shared-factor pairs than the lower-density alternatives tested;
density was not a search gate. Basis-before-projection gave `8x19x23:2104`
and `8x18x24:2079`; a second basis sweep of the latter reached the retained
`8x18x24:2073`. First basis sweeps also lowered `8x17x24` to 1973 and
`8x17x23` to 1934. All changed tensors pass independent full GF(2) checks.

Three 50-million-move continuations from that chain yielded further exact
witnesses. The `8x19x24:2143` tensor reached `8x19x24:2140` (nonce 19203).
Projecting its last-axis coordinate 20 and compressing gave `8x19x23:2101`;
a walk reached `8x19x23:2099` (nonce 19205). Projecting first-axis coordinate
1 of that result gave `7x19x23:1983`; a walk reached `7x19x23:1980` (nonce
19207). Each saved output passed independent full GF(2) tensor expansion.
The 17- and 19-context basis/projection follow-ups found no better child than
the corresponding walks in their bounded screens.

These eleven witnesses have independently checked canonical MFW1 hashes in the
focused Python certificate test and the closure checker. Ten beat entries in
the current [Université de Lille table](https://fmm.univ-lille.fr/), served
version `2b71762f906bef43f0ce25d31a9b8e5ad28a23db` on 2026-09-22:

| Shape | Retained GF(2) rank | Lille table rank |
| --- | ---: | ---: |
| 8x19x25 | 2267 | 2330 |
| 7x19x26 | 2209 | 2215 |
| 8x19x24 | 2140 | 2216 |
| 7x19x25 | 2122 | 2127 |
| 7x19x24 | 2010 | 2025 |
| 8x19x23 | 2099 | 2145 |
| 8x18x24 | 2059 | 2100 |
| 8x19x22 | 2034 | 2057 |
| 8x17x24 | 1965 | 2012 |
| 8x17x23 | 1923 | 1946 |

The new `7x19x23:1980` improves the pinned GF(2) closure price of 2015 but
does not beat Lille's listed rank 1959 for that shape.

A second directed branch began at the retained `8x18x24:2073` tensor. A
50-million-move walk (nonce 19211) reached rank 2059. Exact one-coordinate
projections and compression gave `7x18x24:1947`, `8x18x23:2020`, and
`8x17x24:1972`; 50-million-move walks on the first two (nonces 19213 and
19215) reached 1942 and 2016. Projecting the latter gave `8x17x23:1928`
and `7x18x23:1904`; a 50-million-move walk (nonce 19217) lowered the first
to 1923. Further exact projections gave `7x17x24:1862`, `8x17x22:1876`,
and `8x16x23:1793`; a final 50-million-move walk (nonce 19219) lowered the
last to 1792. A separate 50-million-move `8x19x22` walk (nonce 19209) tied
its seed and was not retained. All nine changed or added tensor witnesses
pass independent full GF(2) verification. Each contributes positively to
the pinned composition closure even in the presence of the other eight.
The new `8x18x23:2016` and `8x16x23:1792` beat Lille's listed 2025 and
1824; the new 7-row and `8x17x22` witnesses do not beat that table.

A 19-context basis sweep of `8x18x24:2059` exposed `8x17x24:1970`;
a 50-million-move walk (nonce 19221) lowered it to 1965. A projection
gave `7x17x24:1856`, and another basis sweep lowered that to 1853. Deleting
middle-axis coordinate 4 gave the exact `7x16x24:1730` witness. Separate
50-million-move walks on the latter two (nonces 19223 and 19225) tied their
seeds. All three retained tensors pass independent full GF(2) verification.
The two 7-row ranks improve the pinned closure but not Lille's listings.

Across all retained rectangular certificates, the pinned
catalog-plus-portfolio closure now improves 329 shapes by 17207 total rank
units (previously 258 shapes by 11954). Those downstream prices are not 329
separately materialized tensor certificates. The table comparison is not a
complete worldwide novelty audit or an optimality claim.

Replaying the `20x20x25` structured-parent row yields rank 5566. Deleting
coordinate 18 of its middle axis, cancelling equal GF(2) terms, and applying
exact shared-factor compression yields `20x19x25` at rank 5439. Repeated
exact refactors lower it to 5418. A 50-million-move walk (nonce 19111)
reaches 5405 and a 100-million-move continuation (nonce 19113) reaches
5403. The retained same-rank refactor `20x19x25-r5403.mfw.gz.b64` has
SHA-256 `c11d3a775ed89031462c126f1707f63cd600c611d268878f165a838b9a8eb2a6`
and density 339443. The prior pinned GF(2) catalog-plus-portfolio price
was 5583. The exact tensor is checked by both independent verifiers.

For context, the [Université de Lille full table](https://fmm.univ-lille.fr/)
(served version `2b71762f906bef43f0ce25d31a9b8e5ad28a23db`, consulted on
2026-09-22) lists 10x12x19:1434, 10x12x25:1844,
16x25x27:6048, 16x25x28:6307, 16x25x29:6507, 16x25x31:6914,
8x19x30:2775, 13x20x28:4271, 15x19x28:4663, 14x20x28:4556,
and 19x20x25:5276. The same table lists 13x19x27:3989,
13x20x26:4016, 12x20x27:3740, and 8x19x28:2590. Its further entries are
13x19x26:3838, 13x20x25:3858, 11x20x27:3559, 7x19x28:2362, and
8x19x27:2516. The next descendants have entries 13x19x25:3705,
8x19x26:2419, 7x19x27:2295, 12x19x26:3484, and 7x18x28:2228.
The retained 12x10x19 rank 1421, 12x10x25 rank 1836, 16x28x25 rank 6223,
8x19x30 rank 2723,
13x20x28 rank 4167, 15x19x28 rank 4576, 14x20x28 rank 4484,
13x19x28 rank 4068, 13x20x27 rank 4092, and 8x19x29 rank 2642 beat their
corresponding table entries. The four further descendants at ranks 3969,
3991, 3699, and 2554 also beat their corresponding entries. The retained
11x20x27 rank 3545 and 8x19x27 rank 2464 also beat their table entries;
13x19x26 rank 3874, 13x20x25 rank 3890, and 7x19x28 rank 2384 improve the
pinned finite closure but not the table. Of the next five, 8x19x26 rank 2366
beats the table, while 13x19x25 rank 3766, 7x19x27 rank 2298,
12x19x26 rank 3493, and 7x18x28 rank 2287 do not. The retained
16x27x25 rank 6080, 16x29x25 rank 6534,
16x31x25 rank 6916, 19x20x25 rank 5403, and 15x19x27 rank 4488 do not.
Some individual
shape pages show older, weaker bounds, so those pages should not
be used alone for record comparisons. These exact GF(2) certificates are not
claims of global novelty across every source or field.

A bounded 19-context basis/projection sweep of the retained
`16x23x13:2772` tensor produced `15x23x13:2711`. Walks of 50 million and
100 million moves (nonces 19561 and 19563) lowered it to 2696; a further
100 million moves (nonce 19565) tied. Basis projections of that endpoint,
followed by 50-million and 100-million-move walks, retained
`14x23x13:2565` (nonces 19567, 19571) and `15x22x13:2622` (19569,
19573). One more bounded basis/projection generation and 50-million-move
walks retained `14x22x13:2501` (19575) and `13x23x13:2446` (19577).
All five complete GF(2) tensors pass both exact verifiers. Together they
change the pinned finite closure from 445 improved shapes and 24993 rank
units to 454 shapes and 25453 units. The `13x15x23:2696` and
`13x15x22:2622` ranks are numerically below Lille's listed
[2724](https://fmm.univ-lille.fr/13x15x23.html) and
[2628](https://fmm.univ-lille.fr/13x15x22.html), respectively; this is not
a worldwide novelty or cross-field optimality claim.

In the next bounded generation, a 19-context basis/projection sweep of
`13x23x13:2446` produced `13x23x12:2219`. A 50-million-move walk (nonce
19579) reached 2206 and a 100-million-move continuation (nonce 19581)
reached the retained rank 2203; the companion sweep of `14x22x13:2501`
found no lower-priced projection. The exact new tensor improves three
pinned composition prices by 86 rank units, moving the finite closure to
456 shapes and 25539 units. It does not establish worldwide novelty.

Returning to the higher-leverage `16x23x13:2772` parent, two exact
same-rank basis restarts each received 100 million directed moves. Mode 0
(nonce 19583) tied, while mode 13 (nonce 19585) reached the retained rank
2771; another 100 million moves (19587) tied. A 19-context sweep of the
new endpoint found no lower-priced projection. The exact parent lowers 39
pinned downstream prices by 40 further rank units; the finite closure is
456 shapes and 25579 units. The two matched restarts show why same-rank
tensor representations are retained, but do not establish a worldwide
record.

The `20x28x13:4167` parent gave no cheaper direct projection in its
19-context basis sweep. A separate exact screen projected all 61 individual
coordinates, compressed each tensor, and gave each result one million directed
moves. Two middle-axis projections beat the pinned `20x27x13:4092` price;
removing coordinate 21 gave a rank-4122 seed, then nonces 19685 (1M moves),
19699 (20M), 19705 (30M), and 19707 (50M) reached the retained rank 4075.
Another 50M moves (19709) tied. Its 19-context basis/projection sweep found
one cheaper child: mode 4, middle coordinate 14, `20x26x13:3990`. Walks of
20M moves (19711) and 50M moves (19715) reached the retained rank 3984.
Both new tensors pass independent full GF(2) expansion. In the pinned finite
closure they improve nine composition prices by 135 rank units in total,
moving the cumulative count to 458 shapes and 25714 units. This is not an
audited worldwide record claim. The short-walk result is evidence for a
possible automatic background arm, not yet a production integration.

Two further parent screens tested that idea against fresh tensors. All 62
one-coordinate projections of `20x28x14:4484` received one million moves;
none beat its existing child prices. The nearest `20x28x13` branch reached
4171 after 20M more moves and tied at 4171 after another 50M, above the
retained 4167. From `19x28x15:4576`, only the 12 projections within 32 ranks
of their current prices received one million moves; none won immediately.
Removing final-axis coordinate 8 gave a `19x28x14:4390` seed that reached
4361 in the short walk, 4357 after 20M moves (nonce 20091), and the retained
4356 after 50M (nonce 20095). Its full GF(2) identity is checked independently.
This adds five downstream price improvements worth 19 rank units, moving the
pinned closure to 463 shapes and 25733 units. These mixed results do not yet
justify an unconditionally eager short-walk arm for every projection.

The retained `19x28x14:4356` parent has a productive final-axis projection
chain. Removing coordinate 6 and applying exact shared-factor compression
gave `19x28x13:4092`; a 1M walk reached 4062, then 20M/50M/50M moves
(nonces 20301/20307/20311) reached the retained 4052. Its rank-4053
intermediate had two cheaper basis/projection children: mode 13 removed
first-axis coordinate 3 for `18x28x13:3906`, and mode 2 removed final-axis
coordinate 6 for `19x28x12:3689`. The former reached 3899 after 20M/50M
moves (20313/20317); the latter reached 3660 (20315/20319). Further exact
basis sweeps found `19x28x11:3520` from the 3660 tensor (mode 0, final
coordinate 1), refined to 3510 (20321/20323), and `17x28x13:3740` from
the 3899 tensor (mode 6, first coordinate 16), refined to 3719
(20325/20327). The latter yielded `17x27x13:3641` (mode 11, middle
coordinate 25), refined to 3618 (20329/20331). Its mode-4 sweep removed
middle coordinate 4 for `17x26x13:3527`; 20M moves (20333) reached 3513,
and 50M more (20335) tied with lower density. Its basis cleanup reached the
retained 3507, while mode 8 removed middle coordinate 17 for
`17x25x13:3400`. Walks of 20M/50M moves (20339/20341) reached 3376, then
basis cleanup reached the retained 3374. That sweep's mode 7 removed middle
coordinate 10 for `17x24x13:3200`; 20M moves (20343) reached 3193, another
50M (20345) tied, and basis cleanup reached the retained 3190. A raw
projection of the rank-3193 intermediate removed first-axis coordinate 7 for
`16x24x13:2920`; walks of 20M/50M moves (20347/20349) reached 2894.
Two 100M-move continuations (20709/20711) lowered that verified tensor to
the retained `16x24x13:2888`, SHA-256
`642f7d379bc69acfa7f14b9982505840add8d47d9e243146473575303cfe395f`.
Every retained endpoint is independently
expanded and checked over GF(2). These ten certificates add 15 improved
pinned composition prices and 1072 rank units, for a cumulative closure of
478 shapes and 26805 units. The [live Lille table](https://fmm.univ-lille.fr/index.html)
lists 2942 for this shape,
while the pinned external index lists 2930; this certificate is lower than
both, without establishing a worldwide or cross-field record.

Reproduction: replay the `5x9x20` row of
`../structured-parent-portfolio-20260922/manifest.json` with
`tools/replay_structured_parent_portfolio.rb --output DIR --only 5x9x20`.
Compile `tools/wide_rect_walk.w` with `bin/tungsten compile ... --release
--native --no-lto`, then run the resulting binary as
`wide-rect-walk 9x5x20 DIR/5x9x20/9x5x20.mfw OUT.mfw 10000000 19071`.
For the second certificate, replay `--only 10x12x20`. From its generated
`12x10x20.mfw`, run 10 million moves with nonce 19071 (rank 1456), continue
that output for 100 million moves with nonce 19071 (rank 1448), then continue
for 100 million moves with nonce 19077 (the saved density-74455 certificate).
For the third, replay `--only 16x25x28`, run its generated `16x28x25.mfw` for
10 million moves with nonce 19071 (rank 6224), then run that output for 100
million moves with nonce 19073 (rank 6223). Decode the saved certificate with
`base64 -D < CERT.mfw.gz.b64 | gzip -dc > CERT.mfw` before feeding it to the
standalone walker or Ruby verifier. The focused Python test decodes it itself.
The finite walker checks the seed and output tensor exactly. The saved
certificates are independently expanded by
`python3 spec/wide_rectangular_certificate_test.py` and can also be checked by
`ruby tools/verify_tensor.rb --shape SHAPE CERT.mfw` (paths relative to this
MetaFlip package and certificate directory as appropriate).

The pinned-catalog closure comparison is replayable with
`python3 tools/check_wide_rectangular_closure.py CATALOG.json`. The checker
recomputes the pinned expected totals among shapes with coordinates 2 through
32; those are composition prices, not separate materialized
certificates for every improved shape. The sole square-price change is
`23x23x23:7328→7263`; it is a composition price, not a materialized square
certificate, and remains above Lille's listed rank 6504.
Another 100 million moves from the retained rank-623 seed, and three further
100-million-move continuations from distinct rank-623 seeds, found no rank-622
result. This finite search is not a lower-bound proof.
Five 100-million-move continuations from rank-1448 seeds found no lower rank.
One further 100-million-move continuation from rank 6223 found no lower rank.
