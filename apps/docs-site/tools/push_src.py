#!/usr/bin/env python3
"""push_src.py <app> <root> <list.txt>: upload source files as src/<path>, batched."""
import json, os, sys, time, urllib.request
tok = os.environ['YAKS_TOKEN']  # mint one with the yaks.app `grant` tool; never commit it
app, root, lst = sys.argv[1:4]
def call(args):
    req = urllib.request.Request('https://yaks.app/mcp', data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "app_files", "arguments": args}}).encode(),
                                 headers={'authorization': 'Bearer ' + tok, 'content-type': 'application/json', 'accept': 'application/json, text/event-stream'})
    body = urllib.request.urlopen(req, timeout=300).read().decode()
    if body.startswith(('event:', 'data:')):
        body = [l[5:] for l in body.split('\n') if l.startswith('data:')][-1]
    return json.loads(body)
paths = [l.strip() for l in open(lst) if l.strip()]
batch, size, done, failed = [], 0, 0, []
def flush():
    global batch, size, done
    if not batch: return
    for attempt in range(3):
        try:
            r = call({'app': app, 'files': batch})
            if 'error' in r or r.get('result', {}).get('isError'):
                raise RuntimeError(json.dumps(r)[:300])
            break
        except Exception as e:
            if attempt == 2: failed.extend(f['path'] for f in batch); print('FAILED batch:', e, flush=True)
            time.sleep(2)
    done += len(batch); print(f'{done}/{len(paths)}', flush=True)
    batch, size = [], 0
for p in paths:
    text = open(os.path.join(root, p), encoding='utf-8', errors='replace').read()
    batch.append({'path': 'src/' + p, 'content': text}); size += len(text)
    if len(batch) >= 40 or size > 900_000: flush()
flush()
print('DONE failed=%d' % len(failed), failed[:5], flush=True)
