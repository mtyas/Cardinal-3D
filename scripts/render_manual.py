#!/usr/bin/env python3
"""Render the illustrated Markdown manual as a portable, offline HTML document."""
from pathlib import Path
import html, re
root = Path(__file__).resolve().parents[1]
def inline(text):
    text = html.escape(text)
    text = re.sub(r'!\[([^\]]*)\]\(([^)]+)\)', r'<figure><img src="\2" alt="\1" loading="lazy"><figcaption>\1</figcaption></figure>', text)
    text = re.sub(r'\[([^\]]*)\]\(([^)]+)\)', r'<a href="\2">\1</a>', text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', text)
    return re.sub(r'`([^`]+)`', r'<code>\1</code>', text)
blocks=[]; paragraph=[]; table=False; contents=[]
def flush():
    if paragraph: blocks.append('<p>' + inline(' '.join(paragraph)) + '</p>'); paragraph.clear()
for line in (root/'docs/MANUAL.md').read_text(encoding='utf-8').splitlines():
    if line.startswith('|'):
        flush()
        if not table: blocks.append('<table>'); table=True
        if re.fullmatch(r'[| :\-]+', line): continue
        blocks.append('<tr>' + ''.join('<td>'+inline(cell.strip())+'</td>' for cell in line.strip('|').split('|')) + '</tr>')
        continue
    if table: blocks.append('</table>'); table=False
    if line.startswith('#'):
        flush(); level=len(line)-len(line.lstrip('#')); title=line[level:].strip(); anchor='section-'+str(len(contents))
        blocks.append(f'<h{level} id="{anchor}">{inline(title)}</h{level}>')
        if level==2: contents.append((anchor,title))
    elif not line.strip(): flush()
    else: paragraph.append(line)
flush()
style='''body{margin:0;background:#0c1720;color:#dce8ed;font:19px/1.65 system-ui,sans-serif}main{max-width:980px;margin:auto;padding:40px 24px}h1,h2{color:#62e4ca;line-height:1.2}h2{margin-top:64px}a{color:#8ce7dc}nav{padding:20px;background:#17303c;border-radius:16px}nav a{display:inline-block;margin:6px 18px 6px 0}figure{margin:28px 0}img{max-width:100%;height:auto;border-radius:14px;border:1px solid #365363}figcaption{font-size:15px;color:#a4bac6}table{width:100%;border-collapse:collapse}td{padding:12px;border-bottom:1px solid #365363}tr:first-child{color:#62e4ca;font-weight:600}code{background:#203443;padding:2px 5px;border-radius:4px}@media print{body{background:white;color:#172730}h1,h2,a{color:#174f52}nav{display:none}img{max-height:420px;object-fit:contain}h2{break-before:page}figure,table{break-inside:avoid}}'''
nav='<nav>'+''.join(f'<a href="#{anchor}">{html.escape(title)}</a>' for anchor,title in contents)+'</nav>'
document='<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Cardinal 3D 0.77 — manual</title><style>'+style+'</style><main>'+blocks[0]+nav+''.join(blocks[1:])+'</main></html>'
for filename in re.findall(r'<img src="([^"]+)"', document):
    if not (root/'docs'/filename).is_file(): raise RuntimeError('Missing illustration: '+filename)
(root/'docs/MANUAL.html').write_text(document, encoding='utf-8')
print('Offline illustrated manual rendered; all image paths verified.')
