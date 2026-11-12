#!/usr/bin/env python3
"""Golden data for lib/metaflip/gf2/gitx.w on the pinned upstream clones of the record hunt.

usage: gen_gitx_goldens.py WORK_DIR OUTDIR
  WORK_DIR   the record-hunt work directory (contains upstream/{fmm,mmc,merlijn,fmm_digest})
  OUTDIR     where the .tsv files go

Runs exactly what the Python originals ran (subprocess.check_output(['git', '-C', clone, ...]),
`git show` with a returncode test) and records the answers:
  real_ls_tree.tsv  clone, rev, path ('-' = whole tree), name count, SHA-256 of the names joined
                    with newlines plus a final newline, and whether Python's whitespace .split()
                    (used by the originals) agreed with a split on newlines
  real_probe.tsv    clone, rev, path, ok|missing, byte size, SHA-256 (of `git show REV:PATH`)
  real_log.tsv      clone, rev, %H, `%h %ci`, %aI, %s of that rev
Every git call runs with GIT_NO_LAZY_FETCH=1: the clones are blob-less partial clones and a
plain `git show` of a missing blob would download it. The generator never writes to a clone.
"""
import hashlib
import os
import subprocess
import sys

ENV = dict(os.environ, GIT_NO_LAZY_FETCH='1', GIT_TERMINAL_PROMPT='0')

FMM_REV = '613599b6c35159b2dcc6749574152eee89518998'
CLONES = {
    'fmm': dict(paths=['schemes', None, 'schemes/known'],
                probes=['README.md', 'CHANGELOG.md', 'schemes/known/alpha_evolve/2x4x7_m45_mod0.json',
                        'schemes/status.json', 'no/such/path.json']),
    'mmc': dict(paths=['src/main/resources/schemes/', None],
                probes=['docs/catalog.json', 'README.md', 'no/such/path.json']),
    'merlijn': dict(paths=[None, 'schemes'], probes=['README.md', 'SHA256SUMS', 'no/such/path.json']),
    'fmm_digest': dict(paths=[None], probes=['fmm_sota.json', 'json_schema.json', 'no/such/path.json']),
}


def git(clone, *args, text=True):
    return subprocess.run(['git', '-C', clone, *args], capture_output=True, text=text, env=ENV)


def names_digest(names):
    return hashlib.sha256(('\n'.join(names) + '\n').encode()).hexdigest()


def main(work, out):
    os.makedirs(out, exist_ok=True)
    ls_rows, probe_rows, log_rows = [], [], []
    for name, spec in CLONES.items():
        clone = os.path.join(work, 'upstream', name)
        revs = [FMM_REV, 'HEAD'] if name == 'fmm' else ['HEAD']
        for rev in revs:
            head = git(clone, 'rev-parse', rev).stdout.strip()
            log_rows.append('\t'.join([name, rev, head, git(clone, 'log', '-1', '--format=%h %ci', rev).stdout.strip(),
                                       git(clone, 'log', '-1', '--format=%aI', rev).stdout.strip(),
                                       git(clone, 'log', '-1', '--format=%s', rev).stdout.strip()]))
            for path in spec['paths']:
                command = ['ls-tree', '-r', '--name-only', rev] + ([path] if path else [])
                listing = subprocess.check_output(['git', '-C', clone, *command], text=True, env=ENV)
                by_lines = listing.split('\n')
                by_lines = by_lines[:-1] if by_lines and by_lines[-1] == '' else by_lines
                by_words = listing.split()
                ls_rows.append('\t'.join([name, rev, path or '-', str(len(by_lines)), names_digest(by_lines),
                                          'same' if by_words == by_lines else 'differs']))
        for probe in spec['probes']:
            shown = git(clone, 'show', f'{revs[0]}:{probe}', text=False)
            if shown.returncode == 0:
                probe_rows.append('\t'.join([name, revs[0], probe, 'ok', str(len(shown.stdout)),
                                             hashlib.sha256(shown.stdout).hexdigest()]))
            else:
                probe_rows.append('\t'.join([name, revs[0], probe, 'missing', '0', '-']))
    for filename, rows in (('real_ls_tree.tsv', ls_rows), ('real_probe.tsv', probe_rows), ('real_log.tsv', log_rows)):
        with open(os.path.join(out, filename), 'w', encoding='utf-8', newline='\n') as fh:
            fh.write('\n'.join(rows) + '\n')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
