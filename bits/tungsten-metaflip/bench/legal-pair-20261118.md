# Legal-pair proposals against V0

Both walkers reached the target on all 72 runs per arm. The legal-pair sampler took 1.41× the CPU time to target on the geometric mean of the six shape-specific ratios. V0 remains the default.

| Shape | Target | Budget (CPU s) | V0 mean CPU s | Legal-pair mean CPU s | Pair/V0 | Seeds faster with legal-pair |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 2x3x4 | 20 | 2 | 0.0491 | 0.0500 | 1.02× | 6/12 |
| 2x4x4 | 26 | 10 | 0.6002 | 0.9210 | 1.53× | 1/12 |
| 3x3x3 | 23 | 1 | 0.0191 | 0.0252 | 1.32× | 6/12 |
| 3x3x4 | 29 | 30 | 2.6442 | 3.7718 | 1.43× | 6/12 |
| 3x3x5 | 36 | 60 | 3.2658 | 4.8075 | 1.47× | 6/12 |
| 2x3x5 | 25 | 120 | 9.0974 | 16.4203 | 1.80× | 5/12 |

Legal-pair processed fewer proposals per CPU second on every shape and needed more proposals to reach the target on five. On 2×3×5 it averaged 93.7 million proposals at 5.71 million/s, compared with 58.2 million at 6.40 million/s for V0. Individual seeds varied. The experiment covers the standard starts and target ranks above.

## Method

Each algorithm used the same release walker binary, 12 matched seed indices per shape, the published CPU budgets, six concurrent single-threaded workers, and the default randomized blocked order. CPU time includes walker startup and final self-check. The Ruby verifier checked every hit. A second pass reopened all 144 archived certificates, verified their tensors and target ranks, and matched their SHA-256 digests to the run records.

The benchmark ran on arm64 macOS from the Tungsten checkout at 242caa4c with the sampler changes applied. The release compiler and core came from the MetaFlip worktree at ee430203. The walker binary had SHA-256 `75aac15469db66e1fd8eef085f10094e2714ff235c657a999df629000f570a83`.

Run from the MetaFlip package directory.

```sh
bench/metabench run --experiment pairs-20261118 --algo metaflip/V0,metaflip/legal-pair \
  --tasks 2x3x4,2x4x4,3x3x3,3x3x4,3x3x5,2x3x5 --n 12 --jobs 6
```

To verify the [archived run logs and certificates](legal-pair-20261118/) and reproduce the comparison, run `ruby bench/legal-pair-20261118/audit.rb` from the MetaFlip package directory.
