#!/usr/bin/env python3
"""Collects every translatable string of the app into i18n/source.json and writes translations back.

  python3 tools/i18n.py extract          -> i18n/source.json  {key: {"en": ..., "nl": ...}}
  python3 tools/i18n.py apply            -> applies every i18n/<lang>.json (key -> text) to compose files,
                                            locales/<lang>.json and README.<lang>.txt
"""
import json, glob, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
LANGS = ["en", "nl", "de", "fr", "it", "sv", "no", "es", "da", "ru", "pl", "ko", "ar"]

def compose_files():
    files = glob.glob('.homeycompose/**/*.json', recursive=True) + glob.glob('drivers/*/driver*.json') + glob.glob('widgets/*/widget.compose.json')
    return sorted(f for f in files if not f.endswith('/app.json') or f.startswith('.homeycompose/app.json'))

def walk(node, path, out):
    if isinstance(node, dict):
        if 'en' in node and all(isinstance(k, str) and (len(k) == 2) for k in node.keys()):
            out[path] = node
            return
        for k, v in node.items():
            walk(v, f'{path}/{k}', out)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(v, f'{path}/{i}', out)

def get_path(root, path):
    node = root
    for part in path.strip('/').split('/'):
        node = node[int(part)] if isinstance(node, list) else node[part]
    return node

def flatten(d, prefix=''):
    out = {}
    for k, v in d.items():
        key = f'{prefix}.{k}' if prefix else k
        if isinstance(v, dict):
            out.update(flatten(v, key))
        else:
            out[key] = v
    return out

def set_dotted(d, dotted, value):
    parts = dotted.split('.')
    for p in parts[:-1]:
        d = d.setdefault(p, {})
    d[parts[-1]] = value

def extract():
    src = {}
    for f in compose_files():
        data = json.load(open(f))
        found = {}
        walk(data, '', found)
        for path, node in found.items():
            src[f'{f}::{path}'] = {'en': node['en'], 'nl': node.get('nl')}
    en = flatten(json.load(open('locales/en.json')))
    nl = flatten(json.load(open('locales/nl.json')))
    for k, v in en.items():
        src[f'locale::{k}'] = {'en': v, 'nl': nl.get(k)}
    src['readme::text'] = {'en': open('README.txt').read(), 'nl': open('README.nl.txt').read()}
    cl = json.load(open('.homeychangelog.json'))
    for ver, node in cl.items():
        src[f'changelog::{ver}'] = {'en': node['en'], 'nl': node.get('nl')}
    json.dump(src, open('i18n/source.json', 'w'), indent=1, ensure_ascii=False)
    print(len(src), 'strings')

def apply():
    for lang in LANGS:
        if lang in ('en', 'nl'):
            continue
        f = f'i18n/{lang}.json'
        if not os.path.exists(f):
            print('missing', f); continue
        tr = json.load(open(f))
        by_file = {}
        for key, value in tr.items():
            kind, _, rest = key.partition('::')
            by_file.setdefault(kind, []).append((rest, value))
        for kind, items in by_file.items():
            if kind == 'locale':
                loc = {}
                for dotted, value in items:
                    set_dotted(loc, dotted, value)
                json.dump(loc, open(f'locales/{lang}.json', 'w'), indent=2, ensure_ascii=False)
            elif kind == 'readme':
                open(f'README.{lang}.txt', 'w').write(items[0][1])
            elif kind == 'changelog':
                cl = json.load(open('.homeychangelog.json'))
                for ver, value in items:
                    cl.setdefault(ver, {})[lang] = value
                json.dump(cl, open('.homeychangelog.json', 'w'), indent=2, ensure_ascii=False)
            else:
                data = json.load(open(kind))
                for path, value in items:
                    get_path(data, path)[lang] = value
                json.dump(data, open(kind, 'w'), indent=2, ensure_ascii=False)
        print('applied', lang, len(tr))

if __name__ == '__main__':
    {'extract': extract, 'apply': apply}[sys.argv[1]]()
