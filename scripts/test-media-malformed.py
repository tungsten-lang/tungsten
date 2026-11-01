#!/usr/bin/env python3
"""Instrument the real TWMS parser and run a bounded deterministic mutation corpus."""
import os
import pathlib
import random
import struct
import subprocess
import sys
import tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
if sys.platform!='darwin':
    print('SKIP native TWMS sanitizers: requires macOS frameworks'); raise SystemExit(0)
with tempfile.TemporaryDirectory(prefix='av-sanitizers-') as d:
    directory=pathlib.Path(d); binary=directory/'media-fuzz'
    subprocess.run(['clang','-O1','-g','-fsanitize=address,undefined','-fno-sanitize-recover=all','-fno-omit-frame-pointer','-I'+str(ROOT/'runtime'),str(ROOT/'runtime/media/media.c'),str(ROOT/'runtime/media/media_fuzz.c'),'-Wl,-dead_strip','-Wl,-undefined,dynamic_lookup','-framework','VideoToolbox','-framework','CoreMedia','-framework','CoreVideo','-framework','CoreFoundation','-o',str(binary)],check=True)
    header=bytearray(64); header[:4]=b'TWMS'; struct.pack_into('<IIIIIIIII',header,4,1,64,int.from_bytes(b'apcn','big'),160,90,24,1,1,0); struct.pack_into('<Q',header,40,0)
    corpus=[b'',b'TWMS',bytes(header),bytes(header)+b'\0'*24]
    # Every header count/length/geometry field, overflowed offsets, truncations,
    # invalid property lists and deterministic random byte mutations.
    for offset in range(4,56,4):
        for value in (0,1,63,64,0x7fffffff,0xffffffff):
            item=bytearray(header+b'\0'*24); struct.pack_into('<I',item,offset,value); corpus.append(bytes(item))
    # Structurally complete record with an offset+size overflow must be rejected.
    for offset,size in ((2**64-1,2),(0,0xffffffff),(1,1)):
        item=bytearray(header);struct.pack_into('<Q',item,40,4)
        record=bytearray(24); struct.pack_into('<QI',record,0,offset,size);record[20]=1;corpus.append(bytes(item+record)+b'junk')
    for metadata in (b'bad plist',b'bplist00',b'<?xml version="1.0"?><plist><array/></plist>',b'\xff'*256):
        item=bytearray(header); struct.pack_into('<I',item,36,len(metadata));struct.pack_into('<Q',item,40,4)
        record=bytearray(24);struct.pack_into('<QI',record,0,0,4);record[20]=1
        corpus.append(bytes(item)+metadata+bytes(record)+b'junk')
    randomizer=random.Random(20261101)
    for i in range(512):
        item=bytearray(header+b'\0'*randomizer.randrange(0,128))
        for _ in range(randomizer.randrange(1,12)): item[randomizer.randrange(len(item))]=randomizer.randrange(256)
        corpus.append(bytes(item[:randomizer.randrange(len(item)+1)]))
    files=[]
    for i,data in enumerate(corpus):
        file=directory/f'{i}.twms'; file.write_bytes(data); files.append(str(file))
    env=dict(os.environ,ASAN_OPTIONS='detect_leaks=0:abort_on_error=1',UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1')
    subprocess.run([binary,*files],check=True,env=env,timeout=60)
    print(f'PASS {len(corpus)} malformed TWMS cases with ASan + UBSan')
