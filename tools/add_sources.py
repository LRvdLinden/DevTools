#!/usr/bin/env python3
"""Registers new DevTools/*.swift files in the Xcode project (main app target).
Usage: python3 tools/add_sources.py DevTools/Core/Foo.swift DevTools/Views/Bar.swift"""
import hashlib, re, sys, os
P = os.path.join(os.path.dirname(__file__), '..', 'DevTools.xcodeproj', 'project.pbxproj')
s = open(P).read()
ANCHOR_REF = 'AAA7B870BF6EADF99B8FFFDA'   # SalesReports.swift file ref (main app group)
ANCHOR_BUILD = '9FEA9B7218C66453CAC2E139' # its build file (main app sources phase)
def uid(seed): return hashlib.md5(seed.encode()).hexdigest()[:24].upper()
for path in sys.argv[1:]:
    if f'path = "{path}"' in s:
        print('already registered', path); continue
    ref, bf = uid('ref:' + path), uid('build:' + path)
    line_ref = f'\t\t{ref} = {{ isa = "PBXFileReference"; lastKnownFileType = "sourcecode.swift"; path = "{path}"; sourceTree = "<group>"; }};\n'
    line_bf = f'\t\t{bf} = {{ isa = "PBXBuildFile"; fileRef = {ref}; }};\n'
    i = s.index(f'\t\t{ANCHOR_REF} = ')
    s = s[:i] + line_ref + line_bf + s[i:]
    # group children: insert after anchor ref inside the PBXGroup line
    s = re.sub(r'(isa = "PBXGroup"; children = \([^)]*?)\b' + ANCHOR_REF + r'\b', lambda m: m.group(1) + ANCHOR_REF + ', ' + ref, s, count=1)
    # sources build phase
    s = re.sub(r'(files = \([^)]*?)\b' + ANCHOR_BUILD + r'\b', lambda m: m.group(1) + ANCHOR_BUILD + ', ' + bf, s, count=1)
    print('added', path)
open(P, 'w').write(s)
