"""Readable evidence pages for artifact hosts that disable downloads."""
import html,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parent/'dist'
def inline(s):
    s=html.escape(s)
    s=re.sub(r'`([^`]+)`',r'<code>\1</code>',s)
    s=re.sub(r'\*\*([^*]+)\*\*',r'<strong>\1</strong>',s)
    s=re.sub(r'\[([^\]]+)\]\(([^)]+)\)',r'<a href="\2">\1</a>',s)
    return s

def markdown(text):
    lines=text.splitlines();out=[];i=0
    while i<len(lines):
        s=lines[i]
        if not s.strip() or s.startswith('<!--'):i+=1;continue
        if s.startswith('```'):
            code=[];i+=1
            while i<len(lines) and not lines[i].startswith('```'):code.append(lines[i]);i+=1
            out.append('<pre><code>'+html.escape('\n'.join(code))+'</code></pre>');i+=1;continue
        if s.startswith('|') and i+1<len(lines) and re.match(r'^\|[ :|\-]+$',lines[i+1]):
            cells=lambda line:[c.strip() for c in line.strip().strip('|').split('|')]
            out.append('<div class="table-scroll" tabindex="0"><table><thead><tr>'+''.join('<th>'+inline(c)+'</th>' for c in cells(s))+'</tr></thead><tbody>');i+=2
            while i<len(lines) and lines[i].startswith('|'):
                out.append('<tr>'+''.join('<td>'+inline(c)+'</td>' for c in cells(lines[i]))+'</tr>');i+=1
            out.append('</tbody></table></div>');continue
        if s.startswith('#'):
            heading=re.match(r'^(#{1,6}) +(.*)$',s)
            if heading:
                n=len(heading[1]);out.append(f'<h{n}>'+inline(heading[2])+f'</h{n}>');i+=1;continue
        if s.startswith('- '):
            out.append('<ul>')
            while i<len(lines) and lines[i].startswith('- '):out.append('<li>'+inline(lines[i][2:])+'</li>');i+=1
            out.append('</ul>');continue
        para=[s];i+=1
        while i<len(lines) and lines[i].strip() and not lines[i].startswith(('#','|','- ','```','<!--')):para.append(lines[i]);i+=1
        out.append('<p>'+inline(' '.join(para))+'</p>')
    return '\n'.join(out)

def document(title,body):
    return '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+html.escape(title)+' · Robolab</title><link rel="stylesheet" href="style.css"></head><body class="evidence-document"><header class="topbar"><div class="nav-inner"><a href="index.html">← Challenger results</a></div></header><main>'+body+'</main></body></html>'
def render():
    (ROOT/'report.html').write_text(document('Full report',markdown((ROOT/'report.md').read_text())))
    raw=json.loads((ROOT/'evidence.json').read_text());body='<div class="eyebrow">Recorded campaign evidence</div><h1>Evidence data</h1><p>Exact scores, validation summaries, and audit results. The full report explains how to interpret these fields.</p><p><a href="report.html">Read the report →</a></p><pre>'+html.escape(json.dumps(raw,indent=2))+'</pre>'
    (ROOT/'evidence.html').write_text(document('Evidence data',body))
if __name__=='__main__':render()
