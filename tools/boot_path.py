#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""List the drivers a set of device-tree nodes needs before they can probe, and how each is
configured in a kernel .config.

Usage:
  boot_path.py LINUX_TREE BOARD.dtb --config .config START [START ...]

START is a node path (/soc/mmc@4020000) or an alias name (mmc0, serial0). From each start
node the tool follows every reference a driver waits on before probing: clocks, resets,
pinctrl-N, *-supply, *-gpios, interrupt-parent / interrupts-extended, phys, dmas,
power-domains, plus each node's parent buses. For every node reached it finds the binding
driver and its Kconfig symbol (same lookup as dt_driver_coverage.py) and prints the symbol's
value. Symbols that are modules (=m) are the ones a kernel without an initramfs would have to
build in (=y) for that start node to come up.

Exit status: 0 when every symbol found is =y, 1 when some are =m or unset.
Read-only. Python stdlib plus the `dtc` binary.
"""
import argparse
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dt_driver_coverage import index_driver_compatibles, kconfig_for, read_config  # noqa: E402

# property -> name of the #cells property in the referenced node (None: plain phandle list)
SPEC = {
    'clocks': '#clock-cells', 'resets': '#reset-cells', 'dmas': '#dma-cells',
    'phys': '#phy-cells', 'power-domains': '#power-domain-cells',
    'interrupts-extended': '#interrupt-cells', 'pwms': '#pwm-cells',
    'io-channels': '#io-channel-cells', 'nvmem-cells': None,
}


def parse(dtb):
    dts = subprocess.run(['dtc', '-q', '-I', 'dtb', '-O', 'dts', dtb], check=True,
                         capture_output=True, text=True).stdout
    nodes, stack = {}, []
    for line in dts.splitlines():
        s = line.strip()
        m = re.match(r'^(?:[\w-]+:\s*)*([\w@,.+-]+|/)\s*\{$', s)
        if m:
            stack.append(m.group(1))
            nodes['/' + '/'.join(p for p in stack if p != '/')] = {}
            continue
        if s == '};':
            stack.pop()
            continue
        m = re.match(r'^([\w,#.+-]+)\s*=\s*(.*);$', s)
        if m and stack:
            path = '/' + '/'.join(p for p in stack if p != '/')
            raw = m.group(2)
            if raw.startswith('<'):
                cells = [int(x, 16) if x.startswith('0x') else int(x)
                         for x in re.findall(r'0x[0-9a-fA-F]+|\b\d+\b', raw)]
                nodes[path][m.group(1)] = cells
            else:
                vals = []
                for v in re.findall(r'"([^"]*)"', raw):
                    vals += [x for x in v.split('\\0') if x]
                nodes[path][m.group(1)] = vals
        elif stack and re.match(r'^[\w,#.+-]+;$', s):
            nodes['/' + '/'.join(p for p in stack if p != '/')][s[:-1]] = True
    return nodes


def refs(path, props, nodes, by_ph):
    """Yield (property, target path) for every reference a driver waits on."""
    def target(ph):
        return by_ph.get(ph)

    for name, val in props.items():
        if not isinstance(val, list) or not val or not isinstance(val[0], int):
            continue
        if name == 'interrupt-parent' or name.endswith('-supply') or re.match(r'pinctrl-\d+$', name):
            for ph in val:
                if target(ph):
                    yield name, target(ph)
        elif name in SPEC or name.endswith('-gpios') or name == 'gpios':
            cells_prop = SPEC.get(name, '#gpio-cells')
            i = 0
            while i < len(val):
                t = target(val[i])
                if not t:
                    break
                yield name, t
                n = nodes[t].get(cells_prop, [0]) if cells_prop else [0]
                i += 1 + (n[0] if isinstance(n, list) and n and isinstance(n[0], int) else 0)
    # interrupts without interrupt-parent: the nearest ancestor's interrupt-parent applies.
    if 'interrupts' in props and 'interrupt-parent' not in props:
        q = path
        while q != '/':
            q = q.rsplit('/', 1)[0] or '/'
            ip = nodes.get(q, {}).get('interrupt-parent')
            if isinstance(ip, list) and ip and target(ip[0]):
                yield 'interrupt-parent (inherited)', target(ip[0])
                break
    # Pin groups are children of the pin controller: depend on the controller.
    parent = path.rsplit('/', 1)[0] or '/'
    if parent != '/':
        yield 'parent', parent


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('tree')
    ap.add_argument('dtb')
    ap.add_argument('--config', required=True)
    ap.add_argument('start', nargs='+')
    a = ap.parse_args()

    nodes = parse(a.dtb)
    by_ph = {v['phandle'][0]: p for p, v in nodes.items()
             if isinstance(v.get('phandle'), list)}
    aliases = {k: v[0] for k, v in nodes.get('/aliases', {}).items() if isinstance(v, list)}
    idx = index_driver_compatibles(a.tree)
    cfg = read_config(a.config)

    # References a driver can work without (it falls back or defers the feature).
    optional = {'dmas'}
    todo, seen, via, opt = [], set(), {}, set()
    for s in a.start:
        p = aliases.get(s, s)
        if p not in nodes:
            sys.exit(f'start node not found: {s}')
        todo.append(p)
        via[p] = 'start'
    while todo:
        p = todo.pop()
        if p in seen:
            continue
        seen.add(p)
        for why, t in refs(p, nodes[p], nodes, by_ph):
            if t not in seen:
                if t not in via:
                    via[t] = f'{why} of {p}'
                    if why in optional or p in opt:
                        opt.add(t)
                elif why not in optional and p not in opt:
                    opt.discard(t)
                todo.append(t)

    bad = 0
    rows = []
    for p in sorted(seen):
        comp = nodes[p].get('compatible')
        if not isinstance(comp, list):
            continue
        st = nodes[p].get('status', ['okay'])
        if isinstance(st, list) and st and st[0] not in ('okay', 'ok'):
            rows.append((p, comp[0], '-', 'disabled', via[p]))
            continue
        hit = next((c for c in comp if c in idx), None)
        if not hit:
            rows.append((p, comp[0], '-', 'no driver (structural or unsupported)', via[p]))
            continue
        syms = set()
        for src in idx[hit]:
            syms |= kconfig_for(a.tree, src)
        # Several drivers can bind one compatible (e.g. simple-bus): one built in is enough.
        vals = {sym: ('always' if sym == '(always built)' else cfg.get(sym, 'not set'))
                for sym in syms or {'?'}}
        ok = [s_ for s_, v in vals.items() if v in ('y', 'always')]
        if ok:
            sym, val = sorted(ok)[0], vals[sorted(ok)[0]]
        else:
            sym = ' / '.join(sorted(vals))
            val = ' / '.join(vals[k] for k in sorted(vals))
            if p in opt:
                val += ' (optional)'
            else:
                bad += 1
        rows.append((p, hit, sym, val, via[p]))
    for r in rows:
        print('\t'.join(r))
    print(f'# {len(seen)} nodes reached; {bad} symbol(s) not built in', file=sys.stderr)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
