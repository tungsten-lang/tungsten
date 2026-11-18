# Certifying a register shortage with cutting planes

Suppose a clique contains $k+1$ mutually interfering live ranges and there are $k$ registers. Write $x_{vc}$ for the Boolean choice “range $v$ uses register $c$.” Each range has an input clause requiring at least one register. For every pair of clique vertices, the input must supply a clause forbidding their simultaneous use of the same register, for every register. These clauses alone suffice.

Fix a register. Start with its exclusion on the first two vertices. Suppose the first $m$ vertices have a proved capacity bound $S = x_1 + \cdots + x_m \le 1$. For a new vertex with literal $x$, adding the $m$ original pair exclusions gives $S + mx \le m$. Add $m-1$ copies of the previous bound to obtain

$$
m(S+x) \le 2m-1.
$$

Since $S+x$ is an integer, division and rounding give $S+x \le 1$. Iterate until the bound covers the clique. Adding the $k$ register capacities and the $k+1$ input clauses for the ranges now gives a contradiction. The certificate uses $k(k-1)+1$ derived constraints and $O(k^3)$ input or previous-constraint references. A detector can supply actual clause IDs, so this argument also applies when the clique is a subset of a larger formula.

| Registers | Clique size | LymphoSAT Hall proof, bytes | Independent cutting-planes proof, bytes | Derived constraints |
|---:|---:|---:|---:|---:|
| 3 | 4 | 634 | 305 | 7 |
| 5 | 6 | 6,219 | 841 | 21 |
| 8 | 9 | 151,276 | 2,785 | 57 |
| 15 | 16 | unmeasured | 15,864 | 211 |
| 30 | 31 | unmeasured | 119,477 | 871 |

VeriPB 3.0.2 reported unconditional UNSAT on all five independently generated proofs. Each paired measurement uses identical input CNF. These are generated complete cliques.

The generator, original formulas, proof files and verifier transcripts are in the audit evidence directory. [Measurements](../../../build/lymphosat-specialist-audit-20261117/93-independent-polynomial-results.json) · [Generator](../../../build/lymphosat-specialist-audit-20261117/probes/93-polynomial.py)

## Native integration on November 18

Wassat now records the chosen row IDs and color coordinates during its bounded
clique search. The native exporter recovers the original pair-clause IDs and
applies the derivation above. Run `wassat certify input.cnf --veripb out.pbp`.

VeriPB 3.0.2 independently verified unconditional UNSAT on all twelve original
SC2025 RoundRobin and MVRoundRobin formulas. The cliques used 13 to 30 colors.
Proofs occupied 11,679 to 145,331 bytes, and median generation time per instance
ranged from 10 to 27 ms across five runs. Shuffling clauses and literals
preserved the result on generated cliques. Removing a required exclusion
produced UNKNOWN in all four satisfiable controls.
[Native measurements](../../../build/wassat-clique-pb-20261118/native-results.json) ·
[CLI controls](../../../build/wassat-clique-pb-20261118/native-cli-controls.json)

## Permuted resources

A shuffled row can list its choices in a different order and use negated
literals. Wassat aligns each row to an anchor using a perfect matching of
original binary exclusions. Before adding two rows to the clique, it checks
that their choices for every anchor color also have an exclusion. The emitter
checks the signed choice rows and the binary clause IDs against the CNF.

VeriPB accepted certificates for SC2025 `homer11` and `harder-fphp-016-015`,
and SC2026 `homer11`, `homer18`, and `homer20`. The four distinct formulas
needed 5,204 to 16,394 bytes. Earlier fast-mode Wassat already decided these
inputs. The new result is a certificate that an independent checker can
verify. [Certificate sizes and runs](../../../build/wassat-specialists-parallel-20261118/certificates.json)
