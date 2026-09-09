#!/usr/bin/env python3
"""Matched frozen-queue ordering experiment, with independent full replays."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import tempfile
from composition_queue_test import RUNTIME, store, value, completion, audit
from packed_composition_parity_test import parse_terms


def check(binary, external):
    def run(*args, fifo=False):
        return subprocess.run([str(binary),*map(str,args)],check=True,timeout=60,
                              stdout=subprocess.DEVNULL,
                              env=dict(os.environ,METAFLIP_COMPOSITION_FIFO='1' if fifo else '0'))
    with tempfile.TemporaryDirectory(prefix='metaflip-priority-order-') as d:
        base=Path(d); frozen=base/'frozen'
        for name in ('objects','tasks','results'): (frozen/name).mkdir(parents=True)
        key=store(frozen,(4,8,4),parse_terms(Path(external).read_bytes(),94))
        (frozen/'tasks'/'1').write_text(key+'\n')
        run('--refine-batch',frozen,1,1,RUNTIME)
        total=value(frozen/'composition/submitted')
        initial=value(frozen/'composition/consumed')
        assert total==105 and initial==2
        records={}; output_sets={}
        for label in ('fifo','priority'):
            root=base/label; shutil.copytree(frozen,root); q=root/'composition'
            while value(q/'consumed')<total:
                run('--compose-batch',root,4,fifo=label=='fifo')
            output_sets[label]=audit(root)
            seen=set(); first={}; prefixes={}
            for ordinal in range(1,total+1):
                ticket,result=completion(q,ordinal)
                shape=tuple(sorted(map(int,result[3].split('x')))); rank=int(result[4])
                assert ticket not in seen; seen.add(ticket)
                for target,cap in (((7,12,12),651),((7,16,16),1132)):
                    if shape==target and rank<=cap:
                        first.setdefault('x'.join(map(str,target)),ordinal)
                if ordinal in (8,16,32,64): prefixes[ordinal]=dict(first)
            assert seen==set(range(1,total+1))
            records[label]={'first_exact_target':first,'prefixes':prefixes,
                            'completed':total,'initial_shared':initial}
        assert output_sets['fifo']==output_sets['priority']
        for target in ('7x12x12','7x16x16'):
            assert records['priority']['first_exact_target'][target] < records['fifo']['first_exact_target'][target]
        print(json.dumps(records,sort_keys=True))
        print('PASS matched priority/FIFO: identical 105 recipes, 210 independent full tensor replays, no dropped work')


if __name__=='__main__':
    check(Path(sys.argv[1]).resolve(),Path(sys.argv[2]))
