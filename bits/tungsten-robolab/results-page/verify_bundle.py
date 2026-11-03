"""Verify portable result links and package the audited static page."""
import hashlib,json,zipfile
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote,urlsplit
ROOT=Path(__file__).resolve().parents[1];DIST=Path(__file__).resolve().parent/'dist';OUT=ROOT/'out/gpt_campaign_final'
class Links(HTMLParser):
    def __init__(self):super().__init__();self.links=[]
    def handle_starttag(self,tag,attrs):
        for key,value in attrs:
            if key in ['href','src','poster'] and value:self.links.append(value)
def main():
    refs=[]
    for page in DIST.glob('*.html'):
        parser=Links();parser.feed(page.read_text())
        refs.extend((page,url) for url in parser.links)
    payload=json.loads((DIST/'evidence.json').read_text())
    def visit(value):
        if isinstance(value,dict):
            for v in value.values():visit(v)
        elif isinstance(value,list):
            for v in value:visit(v)
        elif isinstance(value,str) and value.startswith('assets/'):refs.append((DIST/'index.html',value))
    visit(payload)
    missing=[];checked=[]
    for page,url in refs:
        split=urlsplit(url)
        if split.scheme or split.netloc or not split.path:continue
        target=(page.parent/unquote(split.path)).resolve()
        if not target.is_relative_to(DIST) or not target.is_file():missing.append({'page':page.name,'url':url})
        checked.append(str(target.relative_to(DIST)) if target.is_relative_to(DIST) else str(target))
    assert not missing,missing
    assert payload['completion']['passed'] and payload['followup']['round7']['audit_passed']
    round8=payload['followup'].get('round8')
    if round8:assert round8['audit_passed'] and payload['followup']['round8_audit']['passed']
    round9=payload['followup'].get('round9')
    if round9:assert round9['audit_passed'] and payload['followup']['round9_audit']['passed']
    round10=payload['followup'].get('round10')
    if round10:assert round10['audit_passed'] and payload['followup']['round10_audit']['passed']
    round11=payload['followup'].get('round11')
    if round11:assert round11['audit_passed'] and payload['followup']['round11_audit']['passed']
    round12=payload['followup'].get('round12')
    if round12:
        assert payload['followup']['round12_audit']['passed']
        assert len(round12['arena']['entries'])==6 and not round12['arena']['promotions']
    rounds=[4,5,6,7]+([8] if round8 else [])+([9] if round9 else [])+([10] if round10 else [])+([11] if round11 else [])+([12] if round12 else [])
    entries=len(payload['entries'])+sum(len(payload['followup'][f'round{i}']['arena']['entries']) for i in rounds)
    expected=82 if round12 else (76 if round11 else (70 if round10 else (64 if round9 else (58 if round8 else 52))))
    assert entries==expected
    files=sorted(p for p in DIST.rglob('*') if p.is_file());bundle=ROOT/'out/gpt-results-page.zip'
    with zipfile.ZipFile(bundle,'w',compression=zipfile.ZIP_DEFLATED) as archive:
        for file in files:archive.write(file,file.relative_to(DIST))
    with zipfile.ZipFile(bundle) as archive:
        assert archive.testzip() is None
        assert len(archive.namelist())==len(files)
        assert all(archive.read(str(file.relative_to(DIST)))==file.read_bytes() for file in files)
    manifest={str(p.relative_to(DIST)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    result={'passed':True,'files':len(files),'references_checked':len(checked),'unique_targets':len(set(checked)),'broken_links':missing,'arena_entries':entries,'main_cross_evaluations':len(payload['followup']['main_history']['entries']),'archive_matches_dist':True,'archive':str(bundle),'sha256':manifest,'publication_of_latest_update_confirmed':False}
    (OUT/'bundle_verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='sha256'},indent=2))
if __name__=='__main__':main()
