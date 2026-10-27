"""Builds dist/artifact.html: index.html without the outer document tags
(the Artifact host wraps the page in its own skeleton) and lists the files to publish."""
import json, os, re, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
src = (root / 'index.html').read_text(encoding='utf-8')
head = re.search(r'<head>(.*?)</head>', src, re.S).group(1)
body = re.search(r'<body>(.*?)</body>', src, re.S).group(1)
keep = []
for line in head.strip().splitlines():
    l = line.strip()
    if l.startswith('<meta charset') or l.startswith('<meta name="viewport"'):
        continue
    # the Artifact host supplies its own icon and page metadata
    if 'rel="icon"' in l or 'apple-touch-icon' in l or 'rel="manifest"' in l or 'property="og:' in l or 'name="theme-color"' in l:
        continue
    keep.append(l)
title = [l for l in keep if l.startswith('<title>')]
rest = [l for l in keep if not l.startswith('<title>')]
out = '\n'.join(title + rest) + '\n' + body.strip() + '\n'
# the host does not set dir/lang on <html>: the app root carries them
out = out.replace('<div id="app" class="app">', '<div id="app" class="app" dir="rtl" lang="ar">', 1)
dist = root / 'dist'
dist.mkdir(exist_ok=True)
(dist / 'artifact.html').write_text(out, encoding='utf-8')
files = {}
for d in ['css', 'js', 'icons']:
    for p in sorted((root / d).rglob('*')):
        if p.is_file() and p.suffix in ('.css', '.js', '.mjs', '.txt') or p.name == 'icon.svg':
            rel = p.relative_to(root).as_posix()
            files[rel] = rel
(dist / 'files.json').write_text(json.dumps(files, indent=1), encoding='utf-8')
print('artifact.html', len(out), 'bytes;', len(files), 'files')
