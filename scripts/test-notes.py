#!/usr/bin/env python3
"""Compiled W exporter and the native app's actual document decoder."""
import json
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/reports/notes';OUT.mkdir(parents=True,exist_ok=True)
source=OUT/'export.w'
source.write_text('''use core/notes
+ NotesProbeMeasurement
  -> new(@value)
  -> to_notes
    Notes.table(["quantity", "value"], [["measurement", @value]])
blocks = [Notes.text("Unicode: α and 😀"), Notes.render(NotesProbeMeasurement.new(42)), Notes.line_plot([[~0.0, ~1.0], [~1.0, ~2.0]])]
Notes.write(ARGV[0], "Notes integration", blocks)
''')
def run(args, success=True):
 p=subprocess.run([str(a) for a in args],cwd=ROOT,text=True,capture_output=True,timeout=90)
 assert (p.returncode==0)==success,p.stdout+p.stderr
 return p.stdout
run([ROOT/'bin/tungsten-compiler','compile',source,'--out',OUT/'export','--no-lto'])
run([OUT/'export',OUT/'roundtrip.tnotes'])
valid=json.loads((OUT/'roundtrip.tnotes').read_text())
assert valid['blocks'][1]['rows']==[['measurement','42']]
run([ROOT/'bin/tungsten','notes','--validate',OUT/'roundtrip.tnotes'])
for change in [lambda d:d.update(schema_version=2),lambda d:d['blocks'].append({'kind':'code','text':'run()'}),
 lambda d:d['blocks'].append({'kind':'table','columns':['a'],'rows':[['x','y']]}),
 lambda d:d['blocks'].append({'kind':'certificate','claim':'not enough information','level':'kernel_checked'})]:
 doc=json.loads(json.dumps(valid));change(doc)
 path=OUT/'invalid.tnotes';path.write_text(json.dumps(doc))
 run([ROOT/'bin/tungsten','notes','--validate',path],False)
print('PASS: compiled #to_notes export, Unicode/plot/table decoding and malformed/unknown block rejection')
