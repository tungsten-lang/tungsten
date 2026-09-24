# Exact block-47 materializations, 2026-09-23

These are complete GF(2) matrix-multiplication tensors, not just block-formula
rank estimates. `manifest.json` pins the historical cross-audit and source
revision lists. The parent formulas use the rank-47 4x4 outer tensor and the
audited 3--8 leaf pool. The compressed MFW1 files carry the final witnesses;
the checker expands every coefficient using both the Python and independent
Ruby full-tensor verifiers.

| Shape | Audited formula | Exact composition | Retained rank | Lille listed rank |
|---|---:|---:|---:|---:|
| 13x15x23 | 2664 | 2662 | 2659 | 2724 |
| 13x15x26 | 3013 | 3012 | 3010 | 3074 |
| 13x15x27 | 3131 | 3129 | 3126 | 3191 |
| 13x16x26 | 3148 | 3148 | 3148 | 3226 |
| 13x16x27 | 3256 | 3256 | 3256 | 3346 |
| 13x19x26 | 3764 | 3762 | 3761 | 3838 |
| 13x19x27 | 3898 | 3894 | 3893 | 3989 |
| 14x16x26 | 3413 | 3412 | 3407 | 3472 |
| 15x19x29 | 4768 | 4766 | 4766 | 4835 |
| 15x19x31 | 5089 | 5083 | 5083 | 5131 |
| 15x22x25 | 4732 | 4731 | 4731 | 4787 |
| 15x22x26 | 4938 | 4936 | 4936 | 4974 |
| 15x22x27 | 5124 | 5120 | 5115 | 5148 |
| 15x23x25 | 4915 | 4913 | 4913 | 4968 |
| 15x23x26 | 5137 | 5133 | 5129 | 5167 |
| 16x20x26 | 4636 | 4636 | 4634 | 4802 |
| 16x21x25 | 4710 | 4710 | 4710 | 4836 |
| 16x21x26 | 4908 | 4908 | 4908 | 5041 |
| 16x22x24 | 4665 | 4665 | 4665 | 4732 |
| 16x22x25 | 4921 | 4921 | 4921 | 5028 |
| 16x22x26 | 5139 | 5138 | 5136 | 5250 |
| 20x23x29 | 7174 | 7174 | 7173 | 7360 |
| 20x23x32 | 7782 | 7782 | 7772 | 8040 |
| 20x24x31 | 7830 | 7830 | 7827 | 8070 |
| 20x23x27 | 6729 | 6729 | 6724 | 6956 |
| 20x23x28 | 6866 | 6866 | 6863 | 7100 |
| 20x22x28 | 6636 | 6636 | 6635 | 6774 |
| 20x23x31 | 7645 | 7645 | 7636 | 7862 |
| 19x28x28 | 8016 | 8016 | 8010 | 8231 |
| 20x23x30 | 7428 | 7428 | 7427 | 7638 |
| 20x24x26 | 6690 | 6690 | 6684 | 6760 |
| 20x22x32 | 7522 | 7522 | 7513 | 7706 |
| 20x23x26 | 6512 | 6512 | 6508 | 6598 |
| 20x26x26 | 7372 | 7371 | 7370 | 7421 |
| 20x21x27 | 6189 | 6189 | 6188 | 6290 |

The four additional 13x rows came from materializing 20 unarchived audited
formulas with `screen_block47_cancellations.py`. Four had strict exact
cancellations; the other 16 did not. A second sweep of eight 14x16 formulas found
one more cancellation at 14x16x26. A first 100-million-move directed walk
lowered each of the five further. A second 100-million-move walk tied each
rank with lower density, so the lower-density tensors are retained. Their
exact-composition parents and both walk nonces are pinned in the manifest.
The earlier 13x15x27 composition and walk are retained unchanged. Bounded
postbasis scans of 13x15x23 and 13x15x26 tied their current ranks.
An 18-shape 14x/15x sweep found three more exact cancellations at 15x19x29,
15x22x25, and 15x23x25. Their 100-million-move walks returned the exact
composition parents unchanged, so no walk outcome is needed to replay them.
An adjacent 11-shape sweep found four further cancellations. The walks on
15x19x31 and 15x22x26 returned their composition parents unchanged; the
retained walks on 15x22x27 and 15x23x26 lower them to 5115 and 5129.
A further six-shape 15x/16x allocation-boundary sweep found one cancellation,
at 16x22x26. Its first 100-million-move directed walk reduced rank 5138 to
5136; the next two tied rank while lowering density. All three nonces and the
exact-composition parent are pinned in the manifest.
Its coordinate projections gave five independently exact tensors below the
Lille-listed ranks, but each was numerically dominated by an already audited
block-47 formula. The projections were not retained in this package. We
materialized and independently verified those five stronger formulas instead.
One 100-million-move walk improved 16x20x26 by two terms; matched walks on the
other four tied their formula ranks.
Ten adjacent 16x/17x block compositions and eleven rank-93 5x5 leaf
variants produced no further exact cancellation. We instead materialized
three high-gain 20x block formulas as exact tensors; one 100-million-move
directed walk per shape reduced their ranks by 1, 8, and 3 respectively.
Another 100-million-move continuation of 20x24x31 tied rank 7827 but lowered
factor-bit density from 399026 to 398980. The lower-density exact tensor is
retained in the archive; density was not used as a walk acceptance objective.
Continuing the verified 20x23x32 result for another 100 million moves reduced
it from 7774 to 7772. A third 100-million-move continuation tied rank with
ten fewer factor bits, and that lower-density tensor is retained. All three
walk hashes and nonces are pinned in the manifest.
The 20x23x29 historical cross-audit listed Lille rank 7421; the current
catalogue lists 7360, which is the comparison used in the table.
A second 100-million-move walk on 20x23x29 tied rank 7173 and reduced
factor-bit density from 355122 to 355118; the exact lower-density tensor is
retained without treating density as a search objective.
Eight further unmaterialized high-gain formulas had no exact cancellations.
Three previously audited adjacent formula parents were materialized and each
given one 100-million-move directed walk: 20x23x27 fell by four terms,
20x23x28 by three, and 20x24x29 stayed at 7370. Only the two gains are
retained. The historical audit lists 6962 for 20x23x27; the current
catalogue lists 6956.
Continuing 20x23x27 for another 100 million moves reduced rank 6725 to
6724. Its third walk tied rank with 34 fewer factor bits; that lower-density
tensor is retained, with all three nonces and hashes pinned.
A further matched 100-million-move batch kept 20x21x32 at 7184, lowered
20x22x28 from 6636 to 6635, and kept 20x25x31 at 8342. After widening the
standalone walker's capacity to match the 16384-term MFW1 reader, 20x28x29
also stayed at 8720. The live fleet retains its separate 8192-term cap.
Only the 20x22x28 gain is retained; its historical audit listed Lille rank
6867, versus the current catalogue's 6774.
Two further 100-million-move continuations of 20x22x28 both tied rank 6635,
lowering factor-bit density from 329009 to 328752 in total. The final exact
tensor is retained, with both continuation nonces and hashes in the manifest.
The matched 20x23x28 continuation returned its input byte-for-byte and was
not retained.
Five further high-headroom formulas were materialized as full exact tensors.
None had construction-time cancellations. Matched 100-million-move walks
lowered 20x23x31 from 7645 to 7638 and 19x28x28 from 8016 to 8010;
20x25x27, 20x20x31 and 20x21x31 returned their exact input tensors.
A second walk lowered 20x23x31 again to 7636; the second 19x28x28 walk
tied rank 8010 with 116 fewer factor bits. Both final tensors and their
parent constructions are retained with every walk nonce and hash.
Another five audited formulas were materialized and independently verified.
They had no construction-time cancellations. First 100-million-move walks
lowered 20x23x30 by one term, 20x24x26 by two, and 20x22x32 by nine;
20x22x29 returned its input, while 20x25x28 tied rank with nine fewer
factor bits. A second walk lowered 20x24x26 again to 6684. The other
continuations tied rank with lower density, so their exact endpoints are
retained. The live Lille entries for 20x24x26 and 20x22x32 are 6760 and
7706, lower than the historical audit's 6930 and 7766.
Another five formulas were materialized without construction-time
cancellations. Matched 100-million-move walks left four ranks unchanged,
while 20x23x26 fell from 6512 to 6509. Its second walk reached 6508; a third
tied rank with lower factor-bit density. The final exact tensor and all three
walk nonces are retained. Lille currently lists 6598 for the shape, versus
the historical audit's 6732.
The next five-shape batch had one exact composition cancellation:
20x26x26 fell from formula rank 7372 to 7371, then a directed walk reached
7370. A second walk tied rank with lower factor-bit density. Another walk
lowered 20x21x27 from 6189 to 6188, and its continuation tied rank with
lower density. The other two formula parents stayed at their ranks. A walk
lowered 20x20x23 from 5034 to 5028, but Lille currently lists 4898 there,
so it is not retained as a competitive certificate in this package.

From the repository root, run:

```sh
python3 bits/tungsten-metaflip/tools/check_block47_exact_20260923.py
```

Optionally compile `bits/tungsten-metaflip/tools/wide_rect_walk.w` and pass its
binary as `--replay-walk BINARY` to reproduce the retained directed walk byte
for byte. `--replay-compose BINARY --leaf-root DIR` also re-materializes all
thirty-five block formulas with `flipfleet_block_compose.w` and verifies their exact
canonical hashes. The tensors beat the numeric ranks in the Lille table as
checked on 2026-09-24. This finite comparison is not a worldwide-record or
optimality claim. With the historical formula bounds included, the first five
new materializations improve only their target shapes in the direct-sum/product
closure over sorted dimensions 2--32. The three later shapes also reduce the
numeric closure at 23x25x31 from 10002 to 10000, but that remains worse than
Lille's listed 9585. No additional record candidate or universal composition
claim follows from that finite scan. The four adjacent-sweep tensors improve
only their own shapes against the same formula-bounded closure. The new
16x22x26 tensor also lowers the finite numeric closure at 18x22x26 from 6041
to 6038, still worse than Lille's listed 5771. Among the six new retained
rows, only 16x20x26 and 16x22x26 lower the already audited block-formula
numeric closure over sorted dimensions 2--32; the four other rows turn prior
formula estimates into full exact tensor witnesses.
Adding the three 20x witnesses changes 19 entries in that finite numeric
direct-sum/product closure, including the three source shapes. Those downstream
entries are arithmetic bounds, not materialized tensor certificates in this
package; sampled Lille comparisons do not establish further record candidates.
The later 20x23x32 continuation lowers three numeric closure entries again:
20x23x32 (7774 to 7772), 21x23x32 (8510 to 8508), and 23x32x32
(12706 to 12704). The two downstream prices remain above Lille's listings.
In the same formula-bounded closure, the two adjacent 20x23 gains lower five
numeric entries including their source shapes: 21x23x27 (7350 to 7345),
21x23x28 (7510 to 7507), and 23x28x32 (11242 to 11239) are the three
downstream entries. Each remains above its current Lille-listed rank, so no
downstream tensor was materialized for this batch.
The 20x22x28 gain lowers three entries in the same finite numeric closure:
its own rank and the arithmetic prices for 21x22x28 (7252 to 7251) and
22x28x32 (10842 to 10841). The latter two remain above their Lille listings;
they are not additional tensor certificates.
The two latest gains lower five entries in that finite numeric closure:
20x23x31 (7645 to 7636), 21x23x31 (8358 to 8349), 23x31x32 (12494 to
12485), 19x28x28 (8016 to 8010), and 28x28x31 (13233 to 13227).
The three downstream prices remain above saved public comparisons and are
not materialized here.
The three newest gains lower eight entries in the same finite numeric closure:
their own ranks plus 21x23x30 (8118 to 8117), 23x30x32 (12178 to 12177),
21x24x26 (7314 to 7308), 21x22x32 (8226 to 8217), and 22x32x32
(12274 to 12265). None of these five downstream prices beats its saved
public comparison; they are not additional tensor witnesses.
The 20x23x26 gain lowers only its source and 21x23x26 in the same finite
formula-bounded closure: 6512 to 6508 and 7110 to 7106, respectively.
The latter remains above Lille's listed 6875 and is not materialized here.
The 20x26x26 and 20x21x27 gains lower six numeric entries in that closure:
their two source ranks, 21x26x26 (8048 to 8046), 22x26x26 (8724 to 8722),
21x21x27 (6756 to 6755), and 21x27x32 (10074 to 10073). The four downstream
prices are not materialized tensor certificates.
