#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Apply a pinned list of upstream patch series (by reference) to a Linux git tree.

Usage: apply_upstream.py MANIFEST LINUX_TREE [--cache DIR]

For each `series` in MANIFEST (see kernel/upstream/base-layer.txt for the format):
  1. download https://patchwork.kernel.org/series/<id>/mbox/ into the cache (once);
  2. split it; check that the number of patches and each listed patch's
     `git patch-id --stable` match the manifest (a mismatch stops everything);
  3. apply each `apply` patch with its fixes, as a commit with the patch's own author, date and
     message (git am); `reanchor` patches are applied hunk by hunk, see below.
Nothing is written outside the cache and LINUX_TREE. Python stdlib + git + curl.
"""
import argparse
import os
import re
import subprocess
import sys
import tempfile

BASE = 'https://patchwork.kernel.org/series/{}/mbox/'


def run(cmd, cwd=None, inp=None, check=True):
    r = subprocess.run(cmd, cwd=cwd, input=inp, capture_output=True, text=True)
    if check and r.returncode:
        sys.exit(f"FAIL: {' '.join(cmd)}\n{r.stdout}{r.stderr}")
    return r


def parse(path):
    series, cur = [], None
    for raw in open(path):
        line = raw.rstrip('\n')
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        m = re.match(r'series\s+(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(.*)$', line)
        if m:
            cur = {'id': m.group(1), 'version': m.group(2), 'date': m.group(3),
                   'author': m.group(4), 'title': m.group(5), 'patches': {}}
            series.append(cur)
            continue
        m = re.match(r'patch\s+(\d+)\s+([0-9a-f]{40})\s+(apply|skip)\b\s*(.*)$', line)
        if m:
            cur['patches'][int(m.group(1))] = {'pid': m.group(2), 'action': m.group(3),
                                               'why': m.group(4), 'fixes': []}
            continue
        m = re.match(r'fix\s+(\d+)\s+replace (.*)$', line)
        if m:
            old, sep, new = m.group(2).partition('|')
            if not sep:
                sys.exit(f'bad replace (no |): {line}')
            cur['patches'][int(m.group(1))]['fixes'].append(('replace', old, new))
            continue
        m = re.match(r'fix\s+(\d+)\s+drop-hunk (.*)$', line)
        if m:
            cur['patches'][int(m.group(1))]['fixes'].append(('drop-hunk', m.group(2)))
            continue
        m = re.match(r'fix\s+(\d+)\s+reanchor\s*$', line)
        if m:
            cur['patches'][int(m.group(1))]['fixes'].append(('reanchor',))
            continue
        sys.exit(f'cannot parse manifest line: {line}')
    return series


def split_mbox(mbox, outdir):
    run(['git', 'mailsplit', '-o' + outdir, mbox])
    return [os.path.join(outdir, f) for f in sorted(os.listdir(outdir))]


def patch_id(text):
    out = run(['git', 'patch-id', '--stable'], inp=text).stdout.split()
    return out[0] if out else ''


def apply_fixes(text, fixes, where):
    for f in fixes:
        if f[0] == 'replace':
            if f[1] not in text:
                sys.exit(f'{where}: replace target not found: {f[1]!r}')
            text = text.replace(f[1], f[2])
        elif f[0] == 'drop-hunk':
            parts = re.split(r'(?m)^(?=@@ )', text)
            keep = [p for p in parts if f[1] not in p]
            if len(keep) != len(parts) - 1:
                sys.exit(f'{where}: drop-hunk matched {len(parts) - len(keep)} hunks, want 1')
            text = ''.join(keep)
    return text


def reanchor(tree, text, where):
    """Apply a patch hunk by hunk: hunks that apply go through git apply; a failing hunk that
    only adds lines is inserted before its first trailing-context line, which must be unique."""
    files = re.split(r'(?m)^(?=diff --git )', text)
    files = files[1:]   # drop the mail header before the first diff
    for ftext in files:
        hdr, *hunks = re.split(r'(?m)^(?=@@ )', ftext)
        path = re.search(r'^\+\+\+ b/(.*)$', hdr, re.M).group(1)
        for h in hunks:
            with tempfile.NamedTemporaryFile('w', suffix='.patch', delete=False) as t:
                t.write(hdr + h)
            ok = run(['git', 'apply', t.name], cwd=tree, check=False).returncode == 0
            os.unlink(t.name)
            if ok:
                continue
            body = h.split('\n')[1:]
            if any(l.startswith('-') for l in body):
                sys.exit(f'{where}: {path}: failing hunk removes lines; reanchor refuses')
            added, after = [], None
            for l in body:
                if l.startswith('+'):
                    added.append(l[1:])
                elif added and l.startswith(' '):
                    after = l[1:]
                    break
            if not added or after is None:
                sys.exit(f'{where}: {path}: no trailing context to anchor on')
            full = os.path.join(tree, path)
            lines = open(full).read().split('\n')
            hits = [i for i, l in enumerate(lines) if l == after]
            if len(hits) != 1:
                sys.exit(f'{where}: {path}: anchor {after!r} found {len(hits)} times, want 1')
            lines[hits[0]:hits[0]] = added
            open(full, 'w').write('\n'.join(lines))
            print(f'    reanchored {len(added)} line(s) in {path} before {after.strip()!r}')
    # Commit with the patch's own author, date and message.
    with tempfile.TemporaryDirectory() as d:
        msgf, patchf = os.path.join(d, 'msg'), os.path.join(d, 'patch')
        info = run(['git', 'mailinfo', msgf, patchf], inp=text).stdout
        msg = open(msgf).read()
    meta = dict(re.findall(r'^(Author|Email|Subject|Date): (.*)$', info, re.M))
    # Stage only what this patch touches (the tree may hold other uncommitted files).
    for path in re.findall(r'^\+\+\+ b/(.*)$', text, re.M):
        run(['git', 'add', '--', path], cwd=tree)
    env = dict(os.environ, GIT_AUTHOR_NAME=meta['Author'], GIT_AUTHOR_EMAIL=meta['Email'],
               GIT_AUTHOR_DATE=meta['Date'])
    r = subprocess.run(['git', 'commit', '-q', '-F', '-'], cwd=tree, env=env, text=True,
                       input=meta['Subject'] + '\n\n' + msg, capture_output=True)
    if r.returncode:
        sys.exit(f'{where}: commit failed\n{r.stderr}')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('manifest')
    ap.add_argument('tree')
    ap.add_argument('--cache', default=os.path.expanduser('~/.cache/h700-upstream'))
    a = ap.parse_args()
    os.makedirs(a.cache, exist_ok=True)
    for s in parse(a.manifest):
        mbox = os.path.join(a.cache, f"series-{s['id']}-v{s['version']}.mbox")
        if not os.path.exists(mbox):
            run(['curl', '-sSfL', '-m', '180', '-o', mbox, BASE.format(s['id'])])
        tmp = tempfile.mkdtemp(prefix=f"s{s['id']}-", dir=a.cache)
        files = split_mbox(mbox, tmp)
        if len(files) != len(s['patches']):
            sys.exit(f"series {s['id']}: {len(files)} patches downloaded, manifest lists "
                     f"{len(s['patches'])}")
        print(f"series {s['id']} v{s['version']} ({s['date']}, {s['author']}): {s['title']}")
        for n, f in enumerate(files, 1):
            p = s['patches'][n]
            text = open(f).read()
            got = patch_id(text)
            if got != p['pid']:
                sys.exit(f"series {s['id']} patch {n}: patch-id {got}, manifest {p['pid']}")
            if p['action'] == 'skip':
                print(f'  {n:2d} skip   {p["why"]}')
                continue
            text = apply_fixes(text, p['fixes'], f"series {s['id']} patch {n}")
            if any(x[0] == 'reanchor' for x in p['fixes']):
                reanchor(a.tree, text, f"series {s['id']} patch {n}")
                print(f'  {n:2d} applied (reanchored)')
                continue
            r = run(['git', 'am', '-q', '--keep-cr'], cwd=a.tree, inp=text, check=False)
            if r.returncode:
                run(['git', 'am', '--abort'], cwd=a.tree, check=False)
                sys.exit(f"series {s['id']} patch {n}: does not apply\n{r.stdout}{r.stderr}")
            fixed = ' (with fixes)' if p['fixes'] else ''
            print(f'  {n:2d} applied{fixed}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
