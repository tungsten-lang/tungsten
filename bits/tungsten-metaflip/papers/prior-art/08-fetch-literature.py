#!/usr/bin/env python3
"""Part B input: fetch the abstract page, the full-text PDF (latest version) and, when arXiv has one,
the HTML rendering of every paper checked in 08-rescore-and-prior-art.md, and turn each PDF into text
with `pdftotext -layout`.  Also clones the FastMatrixF2 repository (README tables).

Everything lands under W/upstream-latest/arxiv/<id>/ (abs.html, paper.pdf, paper.txt, paper.html,
meta.json) and W/upstream-latest/FastMatrixF2; a manifest with fetch times, HTTP status, versions
and SHA-256 is written to W/upstream-latest/arxiv/manifest.json.  Re-running re-fetches everything.
Run: python3 08-fetch-literature.py [extra arXiv ids ...]   (the listed papers plus any extra ids)
     python3 08-fetch-literature.py --only ID [ID ...]       (just these ids, e.g. papers found by web search)
"""
import hashlib
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

W = Path('/Users/erik/.tungsten/metaflip/experiments/record-hunt-20260926/work')
OUT = W / 'upstream-latest/arxiv'
PAPERS = ['2609.17533', '2511.20317', '2603.02398', '2606.02480', '2512.21980', '2512.13365', '2510.19787',
          '2602.11041', '2502.04514', '2312.16960', '2306.00882', '2108.09520', '2511.10786', '2503.05467',
          '2506.22113', '2210.04045', '2212.01175', '2506.13131', '2506.13242', '2101.12568']
UA = 'Mozilla/5.0 (research audit; contact via github.com/tungsten-lang)'


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, r.geturl(), r.read()
    except urllib.error.HTTPError as e:
        return e.code, url, b''


def now():
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def fetch(aid):
    d = OUT / aid
    d.mkdir(parents=True, exist_ok=True)
    meta = dict(id=aid, fetched_utc=now())
    status, url, body = get(f'https://arxiv.org/abs/{aid}')
    (d / 'abs.html').write_bytes(body)
    html = body.decode('utf-8', 'replace')
    title = re.search(r'<meta name="citation_title" content="([^"]*)"', html)
    authors = re.findall(r'<meta name="citation_author" content="([^"]*)"', html)
    history = re.findall(r'<strong>\[v(\d+)\]</strong>\s*([^<]*?)\s*\(', html) or \
        re.findall(r'\[v(\d+)\]</a>\s*</strong>\s*([^<(]*)', html)
    meta.update(abs_status=status, title=title.group(1) if title else None, authors=authors,
                versions=[dict(v=int(v), date=' '.join(s.split())) for v, s in history])
    time.sleep(3)
    status, url, body = get(f'https://arxiv.org/pdf/{aid}')
    (d / 'paper.pdf').write_bytes(body)
    meta.update(pdf_status=status, pdf_url=url, pdf_sha256=hashlib.sha256(body).hexdigest(), pdf_bytes=len(body))
    if status == 200 and body[:4] == b'%PDF':
        subprocess.run(['pdftotext', '-layout', str(d / 'paper.pdf'), str(d / 'paper.txt')], check=True)
        info = subprocess.run(['pdfinfo', str(d / 'paper.pdf')], capture_output=True, text=True).stdout
        pages = re.search(r'Pages:\s+(\d+)', info)
        meta['pdf_pages'] = int(pages.group(1)) if pages else None
    time.sleep(3)
    status, url, body = get(f'https://arxiv.org/html/{aid}')
    if status == 200:
        (d / 'paper.html').write_bytes(body)
    meta.update(html_status=status)
    (d / 'meta.json').write_text(json.dumps(meta, indent=1) + '\n')
    time.sleep(3)
    return meta


def main():
    # `--only ID ...` fetches just those ids (papers found later, e.g. by the web searches); default: the list
    ids = sys.argv[2:] if sys.argv[1:2] == ['--only'] else PAPERS + sys.argv[1:]
    manifest_path = OUT / 'manifest.json'
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    for aid in ids:
        manifest[aid] = fetch(aid)
        print(aid, manifest[aid]['abs_status'], manifest[aid]['pdf_status'], manifest[aid].get('pdf_pages'),
              manifest[aid]['html_status'], manifest[aid]['title'], file=sys.stderr)
    repo = W / 'upstream-latest/FastMatrixF2'
    if not repo.exists():
        subprocess.run(['git', 'clone', '-q', 'https://github.com/big-brain-zaru/FastMatrixF2', str(repo)], check=True)
    head = subprocess.check_output(['git', '-C', str(repo), 'log', '-1', '--format=%H %cI %s'], text=True).strip()
    manifest['FastMatrixF2'] = dict(repository='https://github.com/big-brain-zaru/FastMatrixF2', head=head, fetched_utc=now())
    manifest_path.write_text(json.dumps(manifest, indent=1) + '\n')


if __name__ == '__main__':
    main()
