#!/usr/bin/env python3
"""Import and independently verify signed FMM .exp catalogues.

The upstream expression format has one product of three linear forms per
line, for example ``(a11-a12)*(b21+b22)*(c11-c12)``.  This tool parses that
format directly, expands the complete integer tensor, rejects coefficients
outside {-1,0,1}, gauge-canonicalizes the terms, and writes FlipFleet's
six-mask ``T n rank`` format.

This deliberately does not reuse the Tungsten parser or verifier.  It is the
independent source-format side of the import audit; the generated certificate
is gated again by ``fft_load_seed`` in pure Tungsten.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import pathlib
import re
import subprocess
from collections import defaultdict


TOKEN_RE = re.compile(r"([+-])([abc])([1-9])([1-9])")


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_form(text: str, letter: str, n: int) -> tuple[int, ...]:
    compact = "".join(text.split())
    if not (compact.startswith("(") and compact.endswith(")")):
        raise ValueError(f"linear form lacks parentheses: {text!r}")
    body = compact[1:-1]
    if not body.startswith(("+", "-")):
        body = "+" + body
    coefficients = [0] * (n * n)
    consumed = ""
    for match in TOKEN_RE.finditer(body):
        consumed += match.group(0)
        sign, got_letter, row_text, col_text = match.groups()
        if got_letter != letter:
            raise ValueError(f"expected {letter}, found {got_letter} in {text!r}")
        row = int(row_text)
        col = int(col_text)
        if row < 1 or row > n or col < 1 or col > n:
            raise ValueError(f"coordinate {got_letter}{row}{col} outside {n}x{n}")
        index = (row - 1) * n + col - 1
        coefficients[index] += 1 if sign == "+" else -1
    if consumed != body:
        raise ValueError(f"unparsed source syntax in {text!r}: {body!r}")
    if not any(coefficients):
        raise ValueError(f"zero linear form: {text!r}")
    if any(value not in (-1, 0, 1) for value in coefficients):
        raise ValueError(f"coefficient outside {{-1,0,1}}: {text!r}")
    return tuple(coefficients)


def parse_source(path: pathlib.Path, n: int) -> list[tuple[tuple[int, ...], ...]]:
    terms: list[tuple[tuple[int, ...], ...]] = []
    for line_number, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        factors = line.split("*")
        if len(factors) != 3:
            raise ValueError(f"{path}:{line_number}: expected three factors")
        try:
            term = tuple(
                parse_form(factor, letter, n)
                for factor, letter in zip(factors, "abc", strict=True)
            )
        except ValueError as error:
            raise ValueError(f"{path}:{line_number}: {error}") from error
        terms.append(term)
    if not terms:
        raise ValueError(f"empty source: {path}")
    return terms


def parse_json_source(
    path: pathlib.Path, n: int
) -> list[tuple[tuple[int, ...], ...]]:
    document = json.loads(path.read_text())
    if document.get("n") != [n, n, n]:
        raise ValueError(f"JSON tensor is {document.get('n')!r}, expected {[n, n, n]!r}")
    if document.get("z2") is not False:
        raise ValueError("JSON source is not marked as a signed non-Z2 scheme")
    rank = document.get("m")
    banks = [document.get(name) for name in ("u", "v", "w")]
    if not isinstance(rank, int) or any(not isinstance(bank, list) for bank in banks):
        raise ValueError("JSON source lacks integer m and u/v/w arrays")
    if any(len(bank) != rank for bank in banks):
        raise ValueError("JSON u/v/w row counts do not match m")
    terms: list[tuple[tuple[int, ...], ...]] = []
    for term_index, vectors in enumerate(zip(*banks, strict=True), 1):
        checked = []
        for vector in vectors:
            if not isinstance(vector, list) or len(vector) != n * n:
                raise ValueError(f"JSON term {term_index} has a malformed factor")
            if any(type(value) is not int or value not in (-1, 0, 1) for value in vector):
                raise ValueError(f"JSON term {term_index} is not strictly ternary")
            if not any(vector):
                raise ValueError(f"JSON term {term_index} has a zero factor")
            checked.append(tuple(vector))
        terms.append(tuple(checked))
    return terms


def verify_terms(
    terms: list[tuple[tuple[int, ...], ...]], n: int, *, source_c_transposed: bool = False
) -> None:
    got: defaultdict[tuple[int, int, int], int] = defaultdict(int)
    for u, v, w in terms:
        us = [(index, value) for index, value in enumerate(u) if value]
        vs = [(index, value) for index, value in enumerate(v) if value]
        ws = [(index, value) for index, value in enumerate(w) if value]
        for ai, av in us:
            for bi, bv in vs:
                for ci, cv in ws:
                    got[(ai, bi, ci)] += av * bv * cv

    dim = n * n
    for ai in range(dim):
        arow, acol = divmod(ai, n)
        for bi in range(dim):
            brow, bcol = divmod(bi, n)
            for ci in range(dim):
                crow, ccol = divmod(ci, n)
                if source_c_transposed:
                    # FastMatrixMultiplication's .exp files pair c[j,i] with
                    # the coefficient of output C[i,j].
                    want = int(acol == brow and bcol == crow and arow == ccol)
                else:
                    want = int(acol == brow and arow == crow and bcol == ccol)
                value = got.get((ai, bi, ci), 0)
                if value != want:
                    raise ValueError(
                        "integer tensor mismatch at "
                        f"A[{arow+1},{acol+1}] B[{brow+1},{bcol+1}] "
                        f"C[{crow+1},{ccol+1}]: got {value}, want {want}"
                    )


def negate(vector: tuple[int, ...]) -> tuple[int, ...]:
    return tuple(-value for value in vector)


def gauge_term(term: tuple[tuple[int, ...], ...]) -> tuple[tuple[int, ...], ...]:
    u, v, w = term
    if next(value for value in u if value) < 0:
        u, w = negate(u), negate(w)
    if next(value for value in v if value) < 0:
        v, w = negate(v), negate(w)
    return u, v, w


def masks(vector: tuple[int, ...]) -> tuple[int, int]:
    positive = 0
    negative = 0
    for index, value in enumerate(vector):
        if value > 0:
            positive |= 1 << index
        elif value < 0:
            negative |= 1 << index
    return positive, negative


def transpose(vector: tuple[int, ...], n: int) -> tuple[int, ...]:
    return tuple(vector[col * n + row] for row in range(n) for col in range(n))


def certificate_text(terms: list[tuple[tuple[int, ...], ...]], n: int) -> str:
    rows = [f"T {n} {len(terms)}"]
    for u, v, source_w in terms:
        # The Tungsten worker stores output coordinates in row-major C[i,j],
        # while upstream .exp uses the dual variable c[j,i].
        term = (u, v, transpose(source_w, n))
        words: list[int] = []
        for vector in gauge_term(term):
            words.extend(masks(vector))
        rows.append(" ".join(str(word) for word in words))
    return "\n".join(rows) + "\n"


def parse_certificate(path: pathlib.Path) -> tuple[int, list[tuple[tuple[int, ...], ...]]]:
    lines = [line.strip() for line in path.read_text().splitlines() if line.strip()]
    header = lines[0].split()
    if len(header) != 3 or header[0] != "T":
        raise ValueError(f"bad certificate header: {lines[0]!r}")
    n = int(header[1])
    rank = int(header[2])
    if len(lines) != rank + 1:
        raise ValueError(f"header rank {rank}, found {len(lines)-1} rows")
    terms: list[tuple[tuple[int, ...], ...]] = []
    limit = (1 << (n * n)) - 1
    for line_number, line in enumerate(lines[1:], 2):
        fields = line.split()
        if len(fields) != 6:
            raise ValueError(f"{path}:{line_number}: expected six masks")
        words = [int(field) for field in fields]
        vectors: list[tuple[int, ...]] = []
        for positive, negative in zip(words[0::2], words[1::2], strict=True):
            if positive < 0 or negative < 0 or positive & negative:
                raise ValueError(f"{path}:{line_number}: invalid signed masks")
            if (positive | negative) & ~limit:
                raise ValueError(f"{path}:{line_number}: mask exceeds {n*n} bits")
            vector = tuple(
                1 if positive >> index & 1 else -1 if negative >> index & 1 else 0
                for index in range(n * n)
            )
            if not any(vector):
                raise ValueError(f"{path}:{line_number}: zero factor")
            vectors.append(vector)
        terms.append(tuple(vectors))
    return n, terms


def verify_manifest(manifest: pathlib.Path, checkouts: list[pathlib.Path]) -> None:
    with manifest.open(newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    if not rows:
        raise ValueError(f"empty provenance manifest: {manifest}")
    checkout_commits: dict[pathlib.Path, str] = {}
    for checkout in checkouts:
        checkout_commits[checkout] = subprocess.check_output(
            ["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True
        ).strip()

    for row in rows:
        n = int(row["tensor"].split("x")[0])
        rank = int(row["rank"])
        certificate = manifest.parent / row["certificate"]
        if sha256(certificate) != row["certificate_sha256"]:
            raise ValueError(f"certificate digest mismatch: {certificate}")
        generated_n, generated_terms = parse_certificate(certificate)
        if generated_n != n or len(generated_terms) != rank:
            raise ValueError(f"certificate metadata mismatch: {certificate}")
        verify_terms(generated_terms, generated_n)

        if checkouts:
            candidates = [
                checkout / row["path"]
                for checkout in checkouts
                if checkout_commits[checkout] == row["commit"]
                and (checkout / row["path"]).is_file()
            ]
            if len(candidates) != 1:
                raise ValueError(
                    f"expected one pinned source checkout for {row['path']}, found {len(candidates)}"
                )
            source = candidates[0]
            checkout = next(
                checkout
                for checkout in checkouts
                if checkout / row["path"] == source
                and checkout_commits[checkout] == row["commit"]
            )
            blob = subprocess.check_output(
                ["git", "-C", str(checkout), "rev-parse", f"{row['commit']}:{row['path']}"],
                text=True,
            ).strip()
            if blob != row["git_blob_sha1"]:
                raise ValueError(f"Git blob mismatch: {source}")
            if sha256(source) != row["source_sha256"]:
                raise ValueError(f"source digest mismatch: {source}")
            source_terms = (
                parse_json_source(source, n)
                if source.suffix.lower() == ".json"
                else parse_source(source, n)
            )
            if len(source_terms) != rank:
                raise ValueError(f"source rank mismatch: {source}")
            verify_terms(source_terms, n, source_c_transposed=True)
            if certificate.read_text() != certificate_text(source_terms, n):
                raise ValueError(f"certificate is not a byte-exact pinned import: {certificate}")

    scope = "certificates+sources" if checkouts else "certificates"
    print(f"PASS manifest={manifest} rows={len(rows)} scope={scope}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", nargs="?", type=pathlib.Path)
    parser.add_argument("output", nargs="?", type=pathlib.Path)
    parser.add_argument("--tensor", type=int)
    parser.add_argument("--expect-rank", type=int)
    parser.add_argument("--verify-certificate", type=pathlib.Path)
    parser.add_argument("--verify-manifest", type=pathlib.Path)
    parser.add_argument("--checkout", action="append", default=[], type=pathlib.Path)
    args = parser.parse_args()

    if args.verify_manifest is not None:
        verify_manifest(args.verify_manifest, args.checkout)
        return

    if args.verify_certificate is not None:
        n, terms = parse_certificate(args.verify_certificate)
        verify_terms(terms, n)
        print(
            f"PASS certificate={args.verify_certificate} tensor={n}x{n} "
            f"rank={len(terms)} sha256={sha256(args.verify_certificate)}"
        )
        return

    if args.source is None or args.output is None or args.tensor is None:
        parser.error("source, output, and --tensor are required for import")
    if args.source.suffix.lower() == ".json":
        terms = parse_json_source(args.source, args.tensor)
    else:
        terms = parse_source(args.source, args.tensor)
    if args.expect_rank is not None and len(terms) != args.expect_rank:
        raise SystemExit(f"expected rank {args.expect_rank}, found {len(terms)}")
    verify_terms(terms, args.tensor, source_c_transposed=True)
    args.output.write_text(certificate_text(terms, args.tensor))
    # Reparse and reverify the serialization, independently of the source AST.
    generated_n, generated_terms = parse_certificate(args.output)
    verify_terms(generated_terms, generated_n)
    print(
        f"PASS source={args.source} source_sha256={sha256(args.source)} "
        f"tensor={args.tensor}x{args.tensor} rank={len(terms)} "
        f"certificate={args.output} certificate_sha256={sha256(args.output)}"
    )


if __name__ == "__main__":
    main()
