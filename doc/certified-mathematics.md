# Certified mathematics

Tungsten distinguishes an exact computation from a theorem whose complete
dependency chain has been checked. The distinction matters most in descent:
an exact intersection of supplied bit vectors is not evidence that those
vectors are the global and local images of a Jacobian.

## Certificate levels

| Level | Meaning | May imply a theorem? |
| --- | --- | --- |
| Finite checked | A matrix, Boolean formula, factor product, or incidence table was replayed exactly | Only the finite statement named by the certificate |
| Arithmetic checked | The finite data are tied to exact field, ideal, divisor, or local-arithmetic producers whose certificates also verify | Yes, within the stated arithmetic model |
| Trusted theorem import | A named established theorem is applied after its hypotheses are checked, but its proof is not formalized here | Yes, relative to the displayed trust base |
| Kernel checked | The theorem connecting the arithmetic statement to the claimed result is present in a proof kernel | Yes |
| Conditional | A named conjecture or unverified theorem import is required, such as a GRH class-group bound | Only with that condition displayed |
| Heuristic | Numerical or search evidence with no completeness theorem | No |

The target proof-object contract is:

- the precise claim and mathematical scope;
- immutable input/proof artifacts;
- dependency certificates;
- `verified?` for independent replay;
- `certified?` only when every required dependency is unconditional;
- explicit conditional assumptions and theorem imports;
- a failure or `unknown` result instead of a guessed theorem.

## Certified real algebraic roots

`RootIsolationCertificate` is a replayable arithmetic certificate for one
real root of a univariate polynomial over ℚ. It checks squarefreeness,
non-root rational endpoints, an exact Sturm count of one on the open interval,
and the ordered number of roots to the left. Refining an
`AlgebraicRealRoot` bisects that interval and repeats the exact Sturm
obligation.

`RealRootIsolation` is the completeness certificate. It compares the returned
list size with the polynomial's exact distinct-real-root count, checks every
rational root directly, checks that every algebraic defining factor divides
the original polynomial, replays each isolating certificate, and verifies
strict ordering. A decimal or floating-point approximation derived from an
interval is useful output, but it is not the certificate.

`AlgebraicRealOperationCertificate` binds an exact `+`, `-`, `*`, or `/`
statement to two certified real operands. Its replay reconstructs the
block-order Gröbner eliminant for the operation (or the direct polynomial
transform for a rational operand), recomputes the propagated rational
interval, proves that the eliminant has exactly one real root there, and
checks that the returned rational or `AlgebraicRealRoot` is that root.
`AlgebraicRealComputation#value` is convenient exact output;
`#certificate` is the statement-bound proof object. A root-isolation
certificate alone proves what a `RootOf` value denotes, not that it was the
result of a claimed arithmetic operation.

`IntegerHermiteNormalFormCertificate` replays the canonical full-rank
integer lattice basis used by `AlgebraOrderIdeal`. Ideal-operation
certificates then check generator products or sums against that lattice.
Prime valuations are certified by exact membership in consecutive prime-ideal
powers, and an `AlgebraIdealFactorizationCertificate` reconstructs both the
ideal and its norm. An invertible fractional ideal records the resulting
certified primes with signed exponents; a principal fractional-ideal
certificate independently clears its denominator and replays the quotient.
These certificates establish individual ideal computations. They do not
establish class-group completeness or a unit-group basis.

`F2LinearSystemCertificate` is the reference finite certificate. It replays
elementary row operations, validates canonical RREF, and independently checks
the particular solution and kernel basis. `ExplicitSelmerIntersectionCertificate`
binds producer dependencies to the exact supplied matrices but deliberately
refuses to return a rank bound. Its columns do not yet carry a certified
ambient square-class basis, so its name denotes an explicit constraint
intersection rather than the true arithmetic Selmer group.

## Certified integral elliptic arithmetic

`WeierstrassInvariantsCertificate` replays the integral \(a_i\), \(b_i\),
\(c_4,c_6,\Delta\), and \(j\) identities. An
`IntegralWeierstrassTransformationCertificate` checks every coefficient in
an admissible change

\[
x=u^2x'+r,\qquad y=u^3y'+u^2sx'+t
\]

and independently checks that \(c_4,c_6,\Delta\) scale by
\(u^4,u^6,u^{12}\). Local minimization searches the complete finite residue
box \(r\bmod p^2,s\bmod p,t\bmod p^3\) whenever invariant valuations alone
do not prove minimality. The search is resource-bounded and returns
`unknown` rather than silently accepting an unproved minimum.

On a certified minimal model, \(\Delta\not\equiv0\bmod p\) certifies good
reduction and \(c_4\not\equiv0\bmod p\) certifies multiplicative reduction.
`EllipticTateLocalDataCertificate` then replays Tate's complete state machine
over \(\mathbb Q\), every integral translation, residue-field root test,
Kodaira symbol, Tamagawa number, split multiplicative flag, and Ogg conductor
formula. This includes the wild additive branches at 2 and 3. The basic
reduction certificate uses the resulting Tate certificate whenever the
conductor exponent cannot be inferred from good, multiplicative, or tame
additive reduction alone.
`EllipticConductorCertificate` composes the minimal-model certificate, exact
discriminant factorization, every local reduction certificate, and the
reconstructed conductor. This certifies the displayed arithmetic result; it
does not by itself supply modularity or level lowering. The current Tate
checker is for rational integral models; a number-field version needs prime
ideals, uniformizers, and residue-field translations.

## Wassat and Wrat

Wassat is appropriate after an arithmetic checker has regenerated a bounded
Boolean problem. Useful examples include:

- matching bitangents and syzygetic quadruples to the canonical theta
  incidence structure;
- eliminating finite Galois subgroups or decomposition actions;
- finite cocycle and cohomology constraints;
- proving that an excluded Selmer vector cannot satisfy all finite
  conditions.

The optional `bits/tungsten-wassat/lib/algebra_certificate.w` bridge asks
Wassat for a WRAT refutation and replays it through the separately implemented
Wrat checker. The certificate stores the canonical base CNF and reconstructs
the exact refutation query by appending the negation of its normalized claim;
an UNSAT proof therefore cannot be relabeled as a different consequence.
Clause labels remain diagnostic metadata.

Wrat verifies file certificates through an allocation-bounded mmap scanner.
Hinted WRAT/LRAT can be packed losslessly as WRATB: sequential addition ids
are implicit and literals/reference deltas use varints. On the representative
149,751-addition shell-width/LRC proof this reduced 80.3 MB to 32.2 MB and
native verifier RSS from the old 7.01 GB whole-proof path to 186 MB. Large
research replays remain opt-in; the default suite checks small proof identities
and format round-trips rather than imposing multi-gigabyte jobs.

WRAT does **not** certify the arithmetic-to-CNF translation, maximal orders,
class groups, unit groups, p-adic lifting, local constancy, duality theorems,
or a modularity theorem. Those need their own semantic checkers or
kernel-checked mathematics.

## Geometric prefix for plane-quartic descent

The implemented shell-width path prepares Bruin--Poonen--Stoll generalized
explicit descent:

1. certify a smooth plane quartic;
2. verify the rational hyperflex `Z=0` with intersection `4P`;
3. use the rational member to select the degree-27 geometric prefix for the
   true setup of BPS section 6.5;
4. check the three supplied bitangent projection pieces of degrees 6, 9, and
   12 by exact substitution and divisibility;
5. prove their product squarefree modulo 5 and recover all 28 geometric
   bitangents, using the classical 28-bitangent theorem as an explicit trusted
   import whose hypotheses are checked;
6. construct the certified degree-27 étale quotient and its executable
   `6 + 9 + 12` Chinese-remainder decomposition;
7. reconstruct a normalized contact quadratic on every étale component,
   verify `l.C = a*q^2`, and construct the true-setup functions `l/l0` with
   `div(l/l0) = 2(beta_l-beta_l0)`;
8. construct the certified integral power product order on those three
   components, with exact generator transforms and rank 27;
9. compute the degree-generic Round 2 integral closure of all three
   components and certify the maximal product order;
10. decompose `2`, `3`, and `13` in all maximal components, certifying the 20
   finite primes above the candidate finite set S, their residue fields,
   ramification indices, and residue degrees; canonical integral and
   fractional ideal arithmetic is available componentwise after this step;
   exact relation witnesses now certify trivial S-class 2-torsion for the
   degree-6, degree-9, and degree-12 components, with full ranks 9, 187, and
   56 on their complete Minkowski factor bases. Each model-field theorem
   transfers to the original bitangent presentation through an exact
   isomorphic-model certificate. Supplied S-unit square-class bases have
   dimensions 9, 12, and 14; their certified true-descent product has
   dimension 35;
11. compute the exact norm map to
   \(\mathbb Q(S,2)=\langle-1,2,3,13\rangle\); its certified rank is 4, so
   the norm-one kernel inside the 35-dimensional true ambient has dimension
   31;
12. evaluate the BPS function family on the rational divisor
    \([0:9:1]-[-3:-3:1]\), certify its nonzero coordinates in the 35-dimensional
    S-unit basis, and replay its zero norm; BPS sections 6.4--6.5 are the named
    theorem import identifying this exact value with the image of the divisor
    class, so this is one known image element rather than a Selmer upper bound;
13. construct exact `Sp6(F2)` actions on the 28 odd characteristics and bind
    certified good-prime factorizations to Frobenius cycle-type constraints;
    these constrain conjugacy classes but deliberately do not claim a common
    arithmetic labeling;
14. over \(\mathbb F_{5^6}\), reconstruct all 28 reduced bitangents and
    contact quadratics, check the 315 conic incidences, label the complete
    finite fiber by odd characteristics, and recover the exact Frobenius
    element; this is one certified finite fiber, not yet a common
    characteristic-zero splitting-field labeling;
15. factor the degree-27 projection exactly over its degree-6 component,
    certify the nine relative factors by residue-degree exclusion, and use
    the resulting stabilizer subdegrees to identify the global theta subgroup
    up to conjugacy as class 693 of order 36; finite group replay is internal,
    while completeness of GAP's 1,369 subgroup classes is a named trusted
    import;
16. at every rational prime in \(S\), compute complete local square classes
    in every number-field completion and replay the resulting block
    global-to-local matrix on the certified 35-dimensional ambient basis;
    the dyadic lane uses the full higher-unit filtration through
    \(U_{2e+1}\), including the critical Artin--Schreier cokernel, and its
    certificate replays a retained statement-bound transcript rather than
    reconstructing every local ideal computation;
    separately, enumerate and certify the complete residue-disk cover at
    good-reduction primes; at \(p=5\), evaluate every BPS line ratio on all
    seven clean disks, replay their exact residue square classes, and certify
    that their one-dimensional span equals the independently checked
    Frobenius-fixed \(J[2]\) dimension, hence is the complete local image;
    the known rational divisor class restricts to a certified one-dimensional
    lower-bound subspace at 2, 3, and 13, where completeness remains unproved;
17. intersect the future explicitly labeled theta-module and local-image
    conditions with that replay-certified F2 kernel.

Step 7 is the BPS true setup. Its certificate checks the component polynomial
identities exactly and records the section 6.5 fake-to-true comparison and the
divisor-of-a-ratio identity as named trusted theorem imports. It is not yet a
completed Selmer computation. The remaining path is:

```text
certified finite and archimedean places for S = {2, 3, 13}
  -> certified S-class 2-torsion in all degree-6/9/12 factors
  -> certified 35-dimensional true ambient square-class space
  -> certified rank-4 global norm map and 31-dimensional kernel
  -> certified rational point-difference image element
  -> certified canonical 28/315 theta incidence
  -> certified Sp6(F2) actions and primewise Frobenius cycle constraints
  -> certified p=5 splitting-field incidence labeling and Frobenius element
  -> certified characteristic-zero subdegrees and global subgroup up to conjugacy
  -> common shell-width root labeling and comparison kernel
  -> certified odd and dyadic ambient localization and good-reduction residue disks
  -> certified complete p=5 good-reduction BPS local image
  -> bad-reduction regular models and certified Jacobian local images at 2, 3, 13
  -> explicit Selmer upper bound
  -> BPS comparison and rational J[2]
  -> Mordell-Weil rank upper bound
```

An earlier implementation divided the degree-27 true target by the rank-four
diagonal rational subgroup and reported dimension 31. BPS section 6.5 says
that removing the rational distinguished bitangent produces a true setup,
whose target is \(L'^\times/L'^{\times2}\), not a second diagonal quotient.
The corrected ambient dimension is 35. The equivalent fake setup uses all 28
bitangents: its rational component contributes four dimensions before the
rank-four diagonal quotient, again leaving dimension 35. The independently
computed global norm map from the true ambient also has rank four, so its
kernel has dimension 31. That kernel—not the erroneous true-target
quotient—is the useful 31-dimensional space.

The combined S-unit and norm replay is a heavyweight, opt-in native lane. On
an 18-core, 128-GiB Mac17,6, the certified \(p=2\) ambient localization takes
about 31.5 seconds and 10.14 GB peak RSS, the \(p=3\) lane about 20.2 seconds
and 7.79 GB, and the \(p=13\) lane about 19.7 seconds and 7.61 GB. Their
localization matrices have dimensions/ranks \(35/29\), \(18/17\), and
\(14/13\), respectively. The complete \(p=5\) good-reduction image lane takes
about 19.8 seconds and 7.37 GB. The standard suite checks smaller identities
and artifact structure. The checked-in witnesses are small. The peak comes
from exact high-degree S-unit arithmetic in a runtime that does not yet
reclaim completed object graphs, not from loading a giant certificate file.
The former dyadic coordinate certificate recomputed its complete filtration
and used 39.5 seconds / 11.71 GB; retaining its exact transcript removed that
duplicate work without weakening the replay. Adding the certified rational
point-difference now takes about 36.0 seconds / 13.23 GB, down from
44.7 seconds / 14.80 GB.

The durable degree-6/9/12 S-class witness artifacts and supplied S-unit
generators live in `spec/fixtures/algebra/`. Their authoritative checks are
opt-in native replays; for example:

```sh
bin/tungsten compile scripts/algebra/shell_width_degree9_verify.w \
  --out /tmp/shell-width-degree9-verify
/tmp/shell-width-degree9-verify \
  spec/fixtures/algebra/shell_width_degree9_s_class.rel
```

The verifier ignores claimed metadata, reconstructs both fields, replays every
principal-ideal relation, checks full F2 rank, and constructs the source-field
transfer proof. On an 18-core, 128-GiB Mac17,6, reference native S-class
replays took 0.41 seconds / 51 MB (degree 6), 18.5 seconds / 9.46 GB
(degree 9), and 22.1 seconds / 7.17 GB (degree 12), so the larger two remain
outside the default regression suite. The witness files themselves are only
hundreds of bytes to about 12 KB. The field isomorphism and arithmetic are
exact; functoriality of localized class groups and the Minkowski generation
theorem remain named trusted mathematical imports rather than kernel-checked
formal proofs.

A GRH-assisted class-group result must remain conditional. A certified
explicit-Selmer upper bound may still bound the true 2-Selmer dimension after
the comparison-kernel correction; equality with the true Selmer group is a
stronger claim and needs the corresponding comparison certificate.

Primary reference: [Bruin--Poonen--Stoll, *Generalized explicit descent and
its application to curves of genus 3*](https://arxiv.org/abs/1205.4456).

## What an FLT-scale checker needs

Generalized explicit descent on this Jacobian solves a fixed arithmetic
problem. Fermat's Last Theorem needs a uniform theorem about an infinite
family of Frey elliptic curves, so the missing layers are substantially
different:

1. elementary exponent reduction and a checked Frey-curve construction
   (the constructor and invariant certificate now exist; uniform exponent
   reduction remains);
2. general integral Weierstrass models, admissible changes, minimal models,
   invariants, and a certified Tate algorithm at every rational prime
   (implemented over \(\mathbb Q\), including wild 2/3 branches);
3. conductors, component groups, finite-flat local conditions, and mod-p
   Galois representations (conductors and Tamagawa numbers are implemented;
   the representation-theoretic structures are missing);
4. modular symbols, q-expansions, Hecke algebras, old/new quotients, newforms,
   and Sturm-bound certificates (the exact \(\Gamma_0(N)\) invariants,
   dimension formulas, Sturm certificates, and classical level-one
   \(E_4,E_6,\Delta\) q-expansions are implemented; weight-two Manin
   generators, relations, cusp boundaries, and cuspidal dimensions are also
   implemented; exact prime Hecke operators, degeneracy maps, old subspaces,
   and canonical new Hecke quotients have replay certificates and explicit
   Heilbronn/Atkin--Lehner--Li theorem imports; one rational weight-two
   eigenpacket can be recovered with exact Euler-recurrence q-coefficients;
   composite Hecke indices, multiple-packet splitting, and non-rational
   eigenform coefficient fields remain);
5. local/global Galois cohomology, Selmer and dual Selmer groups,
   Poitou--Tate duality, and deformation rings;
6. a kernel-checked Ribet level-lowering theorem;
7. a kernel-checked Wiles--Taylor--Wiles modularity-lifting theorem, including
   `R=T`, Taylor--Wiles patching, Langlands--Tunnell, and the 3--5 switch;
8. the finite certificate that weight-two level 2 has no cusp form
   (implemented relative to the named classical dimension theorem), followed
   by composition of all preceding dependencies.

Wassat can check bounded subgroup, incidence, congruence, and finite-module
sublemmas inside that chain. It cannot replace level lowering, modularity
lifting, Chebotarev, duality, or patching.

An honest intermediate milestone is an **FLT application checker**: Tungsten
can verify the elementary Frey invariants, local conductor computation, level
changes, and the final level-2 finite calculation while listing Ribet and
Wiles--Taylor--Wiles as explicit trusted theorem imports. It becomes a fully
kernel-checked FLT proof only when those theorems are formalized and their
proofs are checked by the kernel; merely adding them as axioms remains an
application checker relative to explicit trusted imports.

Primary references:

- [Ribet, *On modular representations of
  Gal(Q-bar/Q) arising from modular forms*](https://math.berkeley.edu/~ribet/Articles/invent_100.pdf)
- [Wiles, *Modular elliptic curves and Fermat's Last
  Theorem*](https://annals.math.princeton.edu/1995/141-3/p01)
- [Taylor--Wiles, *Ring-theoretic properties of certain Hecke
  algebras*](https://annals.math.princeton.edu/1995/141-3/p02)
