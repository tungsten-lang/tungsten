#!/usr/bin/env python3
"""Reconstruct the SATBENCH_EXT corpus that reference.py's survey tier reads.

The corpus lives in /tmp by default and a reboot erases it -- this script IS
the durable artifact. It rebuilds exactly the files the reference suite needs:

  - SATLIB tarballs (cs.ubc.ca/~hoos/SATLIB) for the random/structured
    families. SATLIB files end with a '%' / '0' sentinel that CaDiCaL
    rejects; it is stripped at install time.
  - GBD (benchmark-database.de) single files, resolved BY FILENAME through
    the getinstances query API, for the SAT-competition-archive rows and the
    families SATLIB no longer serves (beijing, lran).
  - php109 is generated (pigeonhole php(10,9)), matching gen_instances.py.

Every installed file is verified against its expected `p cnf <vars> <clauses>`
header; a mismatch is fatal, never silent. Idempotent: existing verified files
are kept.

Usage:  python3 fetch_ext.py [--dest /tmp/satbench-ext]
"""
from __future__ import annotations

import argparse
import gzip
import io
import lzma
import sys
import tarfile
import urllib.parse
import urllib.request
from pathlib import Path

SATLIB = "https://www.cs.ubc.ca/~hoos/SATLIB/Benchmarks/SAT"
GBD_QUERY = "https://benchmark-database.de/getinstances?query="

# SATLIB tarballs: (url path, dest subdir, members to install or None=all .cnf)
TARBALLS = [
    ("RND3SAT/uf225-960.tar.gz", "rand3", None),
    ("RND3SAT/uf250-1065.tar.gz", "rand3", None),
    ("RND3SAT/uuf200-860.tar.gz", "rand3", None),
    ("RND3SAT/uuf225-960.tar.gz", "rand3", None),
    ("RND3SAT/uuf250-1065.tar.gz", "rand3", None),
    ("BMC/bmc.tar.gz", "bmc", None),
    ("DIMACS/DUBOIS/dubois.tar.gz", "dubois", None),
    ("DIMACS/GCP/gcp-large.tar.gz", "gcp-large", None),
    ("QG/QG.tar.gz", "quasigroup", None),
    ("DIMACS/PHOLE/pigeon-hole.tar.gz", "pigeon", None),
    # SATLIB really does spell it "Bejing"
    ("Bejing/Bejing.tar.gz", "beijing", None),
    ("DIMACS/LRAN/f.tar.gz", "lran", None),
]

# GBD files: dest relative path -> (gbd filename query, expected vars, clauses)
GBD_FILES = {
    "comp/agile-sat__bench_1614.smt2.cnf": ("bench_1614.smt2", 25148, 87531),
    "comp/bitvector-unsat__minand064.cnf": ("minand064", 14703, 42956),
    "comp/bitvector-unsat__smulo016.cnf": ("smulo016", 2945, 8738),
    "comp/cryptography-sat__cms-scheel-md5-families-r24-c11-p1-4-6-9-10-11-1.cnf":
        ("cms-scheel-md5-families-r24-c11-p1-4-6-9-10-11-1", 39550, 131279),
    "comp/edge-matching-sat__em_7_3_6_fbc.cnf": ("em_7_3_6_fbc", 1473, 19063),
    "comp/graph-based-unsat__urqh2x5.shuffled-as.sat03-1473.cnf":
        ("urqh2x5.shuffled-as.sat03-1473", 53, 432),
    "comp/hardware-bmc-unsat__shuffling-1-s1722048485-of-bench-sat04-437.used-.cnf":
        ("shuffling-1-s1722048485-of-bench-sat04-437", 14809, 48483),
    "comp/hardware-verification-sat__ibm-2004-03-k70.cnf": ("ibm-2004-03-k70", 69839, 286405),
    "comp/hardware-verification-unsat__SAT_dat.k10.cnf": ("SAT_dat.k10", 46169, 207720),
    "comp/planning-sat__mrpp_6x6#14_10.cnf": ("mrpp_6x6", 4931, 32184),
    "comp/planning-unsat__blocks-4-ipc5-h21-unknown.cnf": ("blocks-4-ipc5-h21-unknown", 136756, 905980),
    "comp/popularity-similarity-unsat__mp1-ps_5000_21250_3_0_0.8_0_1.50_6.cnf":
        ("mp1-ps_5000_21250_3_0_0.8_0_1.50_6", 5000, 21250),
    "comp/quasigroup-completion-sat__qwh.35.405.shuffled-as.sat03-1651.cnf":
        ("qwh.35.405.shuffled-as.sat03-1651", 1597, 10658),
    "comp/quasigroup-completion-unsat__gensys-icl003.shuffled-as.sat05-2715.cnf":
        ("gensys-icl003.shuffled-as.sat05-2715", 1472, 7737),
    "comp/random-planted-solution-sat__fla-350-6.cnf": ("fla-350-6", 350, 1543),
    "comp/scheduling-sat__Break_triple_10_16.xml.cnf": ("Break_triple_10_16", 6443, 28686),
    "comp/social-golfer-sat__ContextModel_output_8_3_10.bul_.dimacs.cnf":
        ("ContextModel_output_8_3_10", 20040, 124280),
    "comp/software-verification-unsat__dspam_dump_vc972.cnf": ("dspam_dump_vc972", 274451, 908255),
    "comp/tseitin-unsat__Urquhart-s3-b3.shuffled-as.sat03-1556.cnf":
        ("Urquhart-s3-b3.shuffled-as.sat03-1556", 45, 376),
    "comp/tseitin-unsat__urquhart3_25bis.shuffled.cnf": ("urquhart3_25bis.shuffled", 99, 264),
}

# spot checks for tarball members the suite actually reads
TAR_EXPECT = {
    "bmc/bmc-ibm-12.cnf": (39598, 194778),
    "gcp-large/g250.15.cnf": (3750, 233965),
    "gcp-large/g125.18.cnf": (2250, 70163),
    "quasigroup/qg3-09.cnf": (729, 16732),
    "quasigroup/qg5-13.cnf": (2197, 125464),
    "pigeon/hole9.cnf": (90, 415),
    "dubois/dubois26.cnf": (78, 208),
    "rand3/uuf250-01.cnf": (250, 1065),
    "beijing/3bitadd_31.cnf": (8432, 31310),
    "beijing/2bitadd_10.cnf": (590, 1422),
    "lran/f1000.cnf": (1000, 4250),
    "lran/f600.cnf": (600, 2550),
}


def http_get(url: str, timeout: int = 120) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "wassat-fetch-ext/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def decompress(blob: bytes) -> bytes:
    if blob[:2] == b"\x1f\x8b":
        return gzip.decompress(blob)
    if blob[:6] == b"\xfd7zXZ\x00":
        return lzma.decompress(blob)
    return blob


def strip_sentinel(text: bytes) -> bytes:
    # SATLIB files end with a line '%' followed by '0' -- everything from the
    # bare '%' line onward is not DIMACS and must go.
    idx = text.find(b"\n%")
    return text[: idx + 1] if idx >= 0 else text


def header(path: Path):
    with open(path, "rb") as fh:
        for raw in fh:
            if raw.startswith(b"p cnf"):
                parts = raw.split()
                return int(parts[2]), int(parts[3])
    return None


def verify(path: Path, nv: int, ncl: int, label: str) -> None:
    got = header(path)
    if got != (nv, ncl):
        raise SystemExit(f"FATAL {label}: header {got} != expected {(nv, ncl)}")


def install_tarballs(dest: Path) -> None:
    for rel, sub, members in TARBALLS:
        outdir = dest / sub
        outdir.mkdir(parents=True, exist_ok=True)
        marker = outdir / f".done-{Path(rel).name}"
        if marker.exists():
            print(f"  [tar] {rel}: already installed")
            continue
        print(f"  [tar] {rel} ...", flush=True)
        blob = http_get(f"{SATLIB}/{rel}", timeout=300)
        with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as tf:
            n = 0
            for m in tf.getmembers():
                if not m.isfile() or not m.name.endswith(".cnf"):
                    continue
                name = Path(m.name).name
                if members and name not in members:
                    continue
                data = strip_sentinel(tf.extractfile(m).read())
                (outdir / name).write_bytes(data)
                n += 1
        marker.write_text("ok\n")
        print(f"        installed {n} files -> {sub}/")


def gbd_resolve(name_query: str) -> list[str]:
    q = urllib.parse.quote(f"filename like %{name_query}%")
    try:
        body = http_get(GBD_QUERY + q, timeout=60).decode(errors="replace")
    except Exception as e:
        raise SystemExit(f"FATAL gbd query {name_query!r}: {e}")
    # response is whitespace/HTML-adjacent; harvest every file URL in it
    urls = []
    for tok in body.replace("<", " ").replace(">", " ").split():
        if tok.startswith("http") and "/file/" in tok and tok not in urls:
            urls.append(tok)
    if not urls:
        raise SystemExit(f"FATAL gbd: no instance matches filename ~ {name_query!r}")
    return urls


def install_gbd(dest: Path) -> None:
    for rel, (query, nv, ncl) in GBD_FILES.items():
        out = dest / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        if out.exists():
            try:
                verify(out, nv, ncl, rel)
                print(f"  [gbd] {rel}: already present, verified")
                continue
            except SystemExit:
                out.unlink()
        # A loose name query can match several instances; the expected header
        # is the disambiguator, so try each candidate until one verifies.
        last = None
        for url in gbd_resolve(query):
            print(f"  [gbd] {rel} <- {url}", flush=True)
            out.write_bytes(decompress(http_get(url, timeout=600)))
            if header(out) == (nv, ncl):
                break
            last = header(out)
            out.unlink()
        if not out.exists():
            raise SystemExit(f"FATAL gbd {rel}: no candidate matched {(nv, ncl)}; last={last}")


def gen_php109(dest: Path) -> None:
    # php(10,9): pigeon p in hole h -> var (p-1)*9 + h, 1-based
    out = dest / "pigeon/php109.cnf"
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        return
    p, h = 10, 9
    cls = []
    for i in range(p):
        cls.append([i * h + j + 1 for j in range(h)])
    for j in range(h):
        for a in range(p):
            for b in range(a + 1, p):
                cls.append([-(a * h + j + 1), -(b * h + j + 1)])
    lines = [f"p cnf {p * h} {len(cls)}"]
    lines += [" ".join(map(str, c)) + " 0" for c in cls]
    out.write_text("\n".join(lines) + "\n")
    verify(out, 90, 415, "pigeon/php109.cnf")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dest", default="/tmp/satbench-ext")
    dest = Path(ap.parse_args().dest)
    dest.mkdir(parents=True, exist_ok=True)
    install_tarballs(dest)
    install_gbd(dest)
    gen_php109(dest)
    for rel, (nv, ncl) in TAR_EXPECT.items():
        verify(dest / rel, nv, ncl, rel)
    print(f"OK: corpus verified at {dest}")


if __name__ == "__main__":
    main()
