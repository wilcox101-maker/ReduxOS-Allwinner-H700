#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Map every enabled node of a compiled device tree to the kernel driver and Kconfig symbol
that bind it, and optionally check a kernel .config against that list.

Usage:
  dt_driver_coverage.py LINUX_TREE BOARD.dtb [--config .config] [--ignore FILE] [--symbols]

For each enabled node (no status, or status "okay"/"ok") the first compatible string that a
driver in LINUX_TREE matches is looked up in the C sources (of_device_id tables and
OF_DECLARE macros), and the object's Makefile line gives the Kconfig symbol. With --config, each
symbol's value in that .config is shown and the exit status is 1 if any is missing. With
--symbols, only the Kconfig symbols found are printed, one per line (for allowlists).

Read-only. Python stdlib plus the `dtc` binary (to decompile the DTB).
"""
import argparse
import os
import re
import subprocess
import sys
from collections import defaultdict


def enabled_compatibles(dtb):
    """Return {node_path: [compatible, ...]} for enabled nodes."""
    dts = subprocess.run(['dtc', '-q', '-I', 'dtb', '-O', 'dts', dtb], check=True,
                         capture_output=True, text=True).stdout
    nodes, stack = {}, []
    props = defaultdict(dict)
    for line in dts.splitlines():
        s = line.strip()
        m = re.match(r'^(?:[\w-]+:\s*)*([\w@,.+-]+|/)\s*\{$', s)
        if m:
            stack.append(m.group(1))
            path = '/' + '/'.join(p for p in stack if p != '/')
            nodes[path] = True
            continue
        if s == '};':
            stack.pop()
            continue
        m = re.match(r'^(compatible|status)\s*=\s*(.*);$', s)
        if m and stack:
            path = '/' + '/'.join(p for p in stack if p != '/')
            vals = []
            for v in re.findall(r'"([^"]*)"', m.group(2)):
                vals += [x for x in v.split('\\0') if x]   # dtc may print "a\0b"
            props[path][m.group(1)] = vals
    out = {}
    for path in nodes:
        p = props.get(path, {})
        if 'compatible' not in p:
            continue
        status = p.get('status', ['okay'])[0]
        if status not in ('okay', 'ok'):
            continue
        # A parent that is disabled disables its children.
        parents = [path.rsplit('/', i)[0] for i in range(1, path.count('/'))]
        if any(props.get(q, {}).get('status', ['okay'])[0] not in ('okay', 'ok')
               for q in parents if q):
            continue
        out[path] = p['compatible']
    return out


def index_driver_compatibles(tree):
    """Return {compatible: set(source files)} from of_device_id tables and *_OF_DECLARE."""
    idx = defaultdict(set)
    pat = re.compile(rb'\.compatible\s*=\s*"([^"]+)"|[A-Z0-9_]+_DECLARE\s*\(\s*\w+\s*,\s*"([^"]+)"')
    for top in ('drivers', 'sound', 'arch/arm64', 'kernel', 'mm', 'net', 'fs'):
        for root, _, files in os.walk(os.path.join(tree, top)):
            for f in files:
                if not f.endswith('.c'):
                    continue
                p = os.path.join(root, f)
                try:
                    data = open(p, 'rb').read()
                except OSError:
                    continue
                for m in pat.finditer(data):
                    c = (m.group(1) or m.group(2)).decode()
                    idx[c].add(os.path.relpath(p, tree))
    return idx


def kconfig_for(tree, src, cache={}):
    """Find CONFIG_ symbols that build SRC, following composite objects one level up."""
    d, base = os.path.split(src)
    obj = base[:-2] + '.o'
    mk = os.path.join(tree, d, 'Makefile')
    if mk not in cache:
        try:
            text = open(mk).read().replace('\\\n', ' ')
        except OSError:
            text = ''
        cache[mk] = text
    text = cache[mk]
    syms = set()
    for line in text.splitlines():
        if re.search(r'(^|\s)' + re.escape(obj) + r'(\s|$)', line):
            m = re.match(r'\s*obj-\$\(CONFIG_(\w+)\)', line)
            if m:
                syms.add(m.group(1))
                continue
            m = re.match(r'\s*([\w-]+)-(?:y|objs|\$\(CONFIG_(\w+)\))\s*[+:]?=', line)
            if m:
                if m.group(2):
                    syms.add(m.group(2))
                comp = m.group(1) + '.o'
                for l2 in text.splitlines():
                    m2 = re.match(r'\s*obj-\$\(CONFIG_(\w+)\)\s*[+:]?=.*?(^|\s)' +
                                  re.escape(comp) + r'(\s|$)', l2)
                    if m2:
                        syms.add(m2.group(1))
            m = re.match(r'\s*obj-y\s*[+:]?=', line)
            if m:
                syms.add('(always built)')
    return syms


def read_config(path):
    vals = {}
    for line in open(path):
        m = re.match(r'CONFIG_(\w+)=(.*)', line)
        if m:
            vals[m.group(1)] = m.group(2)
    return vals


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('tree')
    ap.add_argument('dtb')
    ap.add_argument('--config')
    ap.add_argument('--ignore', help='file of compatibles to skip, one per line (# comments)')
    ap.add_argument('--symbols', action='store_true', help='print only the Kconfig symbols found')
    a = ap.parse_args()

    ignore = set()
    if a.ignore:
        for line in open(a.ignore):
            line = line.split('#', 1)[0].strip()
            if line:
                ignore.add(line)

    nodes = enabled_compatibles(a.dtb)
    idx = index_driver_compatibles(a.tree)
    cfg = read_config(a.config) if a.config else None
    missing, rows = [], []
    for path in sorted(nodes):
        compats = nodes[path]
        if any(c in ignore for c in compats):
            rows.append((path, compats[0], '-', 'ignored'))
            continue
        hit = next((c for c in compats if c in idx), None)
        if not hit:
            rows.append((path, compats[0], '-', 'NO DRIVER in tree'))
            continue
        syms = set()
        for src in sorted(idx[hit]):
            syms |= kconfig_for(a.tree, src)
        syms = sorted(syms) or ['?']
        if cfg is None:
            rows.append((path, hit, ' '.join(syms), ''))
            continue
        vals = [cfg.get(s, 'n') if s.isidentifier() else 'y' for s in syms]
        ok = any(v in ('y', 'm') for v in vals)
        state = ' '.join(f'{s}={v}' for s, v in zip(syms, vals))
        rows.append((path, hit, state, 'ok' if ok else 'MISSING'))
        if not ok:
            missing.append((path, hit, syms))

    if a.symbols:
        found = set()
        for path in nodes:
            hit = next((c for c in nodes[path] if c in idx), None)
            if hit and not any(c in ignore for c in nodes[path]):
                for src in idx[hit]:
                    found |= {x for x in kconfig_for(a.tree, src) if x.isidentifier()}
        print('\n'.join(sorted(found)))
        return 0

    w = max(len(r[0]) for r in rows)
    for r in rows:
        print(f'{r[0]:<{w}}  {r[1]:<40}  {r[2]}  {r[3]}'.rstrip())
    if cfg is not None:
        print(f'\n{len(rows)} enabled nodes; {len(missing)} without a driver in the config')
        return 1 if missing else 0
    return 0


if __name__ == '__main__':
    sys.exit(main())
