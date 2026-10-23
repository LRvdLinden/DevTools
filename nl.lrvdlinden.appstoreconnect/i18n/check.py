import json, re, sys
src = json.load(open('/home/claude/homey-asc/i18n/source.json'))
path = sys.argv[1]
tr = json.load(open(path))
probs = []
for k, v in src.items():
    en = v['en']
    if k not in tr: probs.append(('missing', k)); continue
    t = tr[k]
    if isinstance(en, list):
        if not isinstance(t, list) or len(t) < len(en) * 0.8: probs.append(('list', k))
        continue
    if not isinstance(t, str) or (en.strip() and not t.strip()): probs.append(('empty', k)); continue
    if sorted(re.findall(r'\[\[\w+\]\]', en)) != sorted(re.findall(r'\[\[\w+\]\]', t)): probs.append(('args', k))
    if en.count('!{{') != t.count('!{{'): probs.append(('not-syntax', k))
    if re.findall(r'</?\w+>', en) != re.findall(r'</?\w+>', t): probs.append(('html', k))
    if en.count('\n') and abs(en.count('\n') - t.count('\n')) > 2: probs.append(('lines', k))
extra = [k for k in tr if k not in src]
print(f'{path}: {len(tr)}/{len(src)} keys, problems={len(probs)}, extra={len(extra)}')
for p in probs[:20]: print('  ', p)
sys.exit(1 if probs or extra else 0)
