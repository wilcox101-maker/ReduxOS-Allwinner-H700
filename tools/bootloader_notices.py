#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Write the licence notices for our bootloader binary (SPL + TF-A BL31 + u-boot).

usage: bootloader_notices.py --uboot-src DIR --uboot-build DIR [--uboot-build DIR ...]
                             --tfa-src DIR --tfa-build DIR  > NOTICES.txt

The binary written at 8 KiB of the card combines two projects:
  * u-boot (GPL-2.0+ as a whole): its corresponding source goes in the release bundle, which meets the
    GPL. A file that is GPL-or-something-else is used under the GPL; only files with no GPL option
    (e.g. MIT-only device trees) need their notices reproduced.
  * TF-A BL31 (BSD-3-Clause as a whole): every file under a permissive licence needs its copyright
    notice and licence text reproduced with the binary. Dual-licensed libfdt is used under BSD-2-Clause,
    as TF-A's docs/license.rst says.
The files that went into each binary are taken from the builds' own dependency files (TF-A `*.d`,
kbuild `.*.cmd`), so the list is exactly what was compiled, headers and device trees included; host
tools (u-boot tools/ and scripts/) are not part of the binary and are skipped. Python stdlib only.
"""
import argparse
import glob
import os
import re
import sys

SRC_EXT = (".c", ".S", ".h", ".dts", ".dtsi")
SPDX = re.compile(r"SPDX-License-Identifier:\s*(.+?)\s*(?:\*/|-->)?\s*$", re.M)
COPY = re.compile(r"^[\s/*#;-]*((?:\(C\)\s*)?Copyright\b.*?)\s*(?:\*/)?\s*$", re.M | re.I)
TEXTS = {   # licence id -> file under u-boot's Licenses/
    "BSD-2-Clause": "bsd-2-clause.txt", "BSD-3-Clause": "bsd-3-clause.txt", "ISC": "isc.txt",
    "MIT": "mit.txt", "X11": "x11.txt", "bzip2-1.0.6": "bzip2-1.0.6.txt", "eCos-2.0": "eCos-2.0.txt",
    "IBM-pibs": "ibm-pibs.txt",
}
# Licence texts u-boot does not ship, kept in this repo (tools/licences/, provenance in its README.md).
REPO_TEXTS = {"Unicode-DFS-2016": "Unicode-DFS-2016.txt"}
REPO_TEXT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "licences")
# Ids already reviewed whose text is unavailable; still warned about, with what was decided.
KNOWN_FLAGS = {"Intel": "lib/binman.c + include/binman.h: Google copyright under u-boot's own 'Intel' tag "
                        "(no text in u-boot); to be reported upstream"}
# Licences whose full text is the notice in each file's header (reproduced verbatim by section()).
KNOWN_HEADER_ONLY = {"BSD-2-Clause-FreeBSD", "LZMA-SDK-9.22"}


def deps(build, src, kind):
    """Source files (relative to src) named in a build directory's dependency files."""
    src = os.path.realpath(src)
    files = set()
    pats = ["**/*.d"] if kind == "tfa" else ["**/.*.cmd"]
    for pat in pats:
        for f in glob.glob(os.path.join(build, pat), recursive=True):
            try:
                text = open(f, errors="replace").read()
            except OSError:
                continue
            for tok in re.split(r"[\s\\:=]+", text):
                tok = tok.strip()
                if not tok.endswith(SRC_EXT):
                    continue
                p = os.path.realpath(tok if os.path.isabs(tok) else os.path.join(src, tok))
                if p.startswith(src + os.sep) and os.path.isfile(p):
                    rel = os.path.relpath(p, src)
                    if kind == "uboot" and rel.split(os.sep)[0] in ("tools", "scripts"):
                        continue
                    files.add(rel)
    return sorted(files)


def head_comment(text):
    m = re.match(r"\s*/\*(.*?)\*/", text, re.S)
    if not m:
        return ""
    lines = [re.sub(r"^\s?\*\s?", "", l).rstrip() for l in m.group(1).splitlines()]
    return "\n".join(lines).strip("\n-")


def scan(src, files):
    """{licence expression: {"files": [...], "copyrights": set()}} plus untagged files."""
    groups, untagged = {}, []
    for rel in files:
        text = open(os.path.join(src, rel), errors="replace").read(16384)
        m = SPDX.search(text)
        cps = {re.sub(r"\s+", " ", c) for c in COPY.findall(text)}
        if m:
            lic = m.group(1).strip().rstrip("*/ ").strip()
            g = groups.setdefault(lic, {"files": [], "copyrights": set()})
            g["files"].append(rel)
            g["copyrights"] |= cps
        else:
            untagged.append((rel, cps, head_comment(text)))
    return groups, untagged


def has_gpl(lic):
    return re.search(r"\bL?GPL", lic) is not None


def needs_notice(lic, project):
    """(licence ids whose notices must ship with the binary, how the file is used).

    An OR picks one alternative: in u-boot a pure-GPL one (its source in the bundle meets it), in TF-A a
    permissive one. Every part of an AND applies. A malformed expression (no operator) is read as AND.
    """
    alts = [a.strip(" ()") for a in re.split(r"\s+OR\s+", lic.strip("() "))]

    def parts(alt):
        alt = re.sub(r"\s+WITH\s+\S+", "", alt)
        return [x.strip(" ()") for x in re.split(r"\s+AND\s+|\s+(?=[A-Za-z][\w.+-]*-\d)", alt) if x.strip(" ()")]

    if project == "uboot":
        pure = [a for a in alts if all(has_gpl(x) for x in parts(a))]
        pick = pure[0] if pure else alts[0]
    else:
        perm = [a for a in alts if not any(has_gpl(x) for x in parts(a))]
        pick = perm[0] if perm else alts[0]
    need = [x for x in parts(pick) if not (project == "uboot" and has_gpl(x))]
    return need, pick


def section(out, title, src, files, project, licdir):
    groups, untagged = scan(src, files)
    used = set()
    out.append("=" * 78)
    out.append(title)
    out.append("=" * 78)
    out.append("%d source files went into this part of the binary (from the build's dependency files)." % len(files))
    out.append("")
    out.append("Licences, by SPDX identifier (files: count):")
    for lic in sorted(groups):
        need, pick = needs_notice(lic, project)
        note = ("   -> used under %s" % pick if pick != lic.strip("() ") else "") + \
               ("   [notice below]" if need else "   [source in bundle]")
        out.append("  %-48s %4d%s" % (lic, len(groups[lic]["files"]), note))
    out.append("  %-48s %4d" % ("(no SPDX tag; notice reproduced below if any)", len(untagged)))
    out.append("")
    for lic in sorted(groups):
        need, pick = needs_notice(lic, project)
        if not need:
            continue            # GPL: met by the corresponding source in the release bundle
        used.update(need)
        g = groups[lic]
        out.append("-" * 78)
        out.append("Files under %s (notice needed for: %s):" % (lic, ", ".join(need)))
        out.append("  " + "\n  ".join(g["files"]))
        out.append("Copyright notices in these files:")
        out.append("  " + "\n  ".join(sorted(g["copyrights"])) if g["copyrights"] else "  (none stated in the files)")
        if any(n not in TEXTS and not n.startswith("Apache-2.0") for n in need):
            # no standard text on hand: reproduce each file's own header, verbatim
            out.append("Header notices of these files, verbatim:")
            seen = set()
            for rel in g["files"]:
                hdr = head_comment(re.sub(r"^\s*//[^\n]*\n", "", open(os.path.join(src, rel), errors="replace").read(16384)))
                if hdr and hdr not in seen:
                    seen.add(hdr)
                    out.append("  [%s]\n    %s" % (rel, hdr.replace("\n", "\n    ")))
        out.append("")
    if untagged:
        out.append("-" * 78)
        out.append("Files without an SPDX tag (their own header notice, verbatim where they have one):")
        seen = set()
        for rel, cps, hdr in untagged:
            out.append("* " + rel)
            if hdr and re.search(r"Redistribution|Permission|licen[cs]e", hdr, re.I) and hdr not in seen:
                seen.add(hdr)
                out.append("    " + hdr.replace("\n", "\n    "))
            elif cps:
                out.append("    " + "\n    ".join(sorted(cps)))
            else:
                out.append("    (no notice in the file; covered by the project licence)")
        out.append("")
    return used


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--uboot-src", required=True)
    ap.add_argument("--uboot-build", required=True, action="append")
    ap.add_argument("--tfa-src", required=True)
    ap.add_argument("--tfa-build", required=True)
    a = ap.parse_args()
    licdir = os.path.join(a.uboot_src, "Licenses")
    out = ["Licence notices for the ReduxOS RG34XX-SP bootloader (SPL + TF-A BL31 + u-boot)",
           "",
           "This file goes with every image or binary that carries u-boot-rg34xxsp-*.bin. The complete",
           "corresponding source (u-boot, TF-A, our patches and build inputs) is in the image's source",
           "bundle (image/release-sources.sh). Generated by tools/bootloader_notices.py; do not edit.",
           ""]
    ub = sorted(set().union(*[set(deps(b, a.uboot_src, "uboot")) for b in a.uboot_build]))
    tf = deps(a.tfa_build, a.tfa_src, "tfa")
    if not ub or not tf:
        sys.exit("no dependency files found (u-boot %d, TF-A %d files): build first" % (len(ub), len(tf)))
    used = section(out, "U-Boot (SPL and u-boot proper): GPL-2.0+ as a whole", a.uboot_src, ub, "uboot", licdir)
    out.insert(len(out), "")
    out += ["=" * 78, "Trusted Firmware-A (BL31): its licence, docs/license.rst, verbatim", "=" * 78,
            open(os.path.join(a.tfa_src, "docs", "license.rst")).read().rstrip(), ""]
    used |= section(out, "Trusted Firmware-A (BL31): files and notices", a.tfa_src, tf, "tfa", licdir)
    out += ["=" * 78, "Licence texts", "=" * 78]
    unknown = []
    for lic in sorted(used):
        if lic in TEXTS:
            out += ["-" * 78, lic + " (text from u-boot Licenses/%s)" % TEXTS[lic], "-" * 78,
                    open(os.path.join(licdir, TEXTS[lic])).read().rstrip(), ""]
        elif lic.startswith("Apache-2.0"):
            out += ["-" * 78, lic, "-" * 78,
                    "Apache License 2.0: /usr/share/common-licenses/Apache-2.0 in the image, or",
                    "https://www.apache.org/licenses/LICENSE-2.0. These files are under Apache-2.0 WITH",
                    "LLVM-exception, which lifts the notice requirements for object code embedded by a compiler.", ""]
        elif lic in REPO_TEXTS:
            out += ["-" * 78, lic + " (text from this repo, tools/licences/%s; source: SPDX license-list-data)" % REPO_TEXTS[lic],
                    "-" * 78, open(os.path.join(REPO_TEXT_DIR, REPO_TEXTS[lic]), encoding="utf-8").read().rstrip(), ""]
        elif lic in KNOWN_HEADER_ONLY:
            out += ["-" * 78, lic + ": its text is the files' own header notice, reproduced above.", ""]
        else:
            unknown.append(lic)
            out += ["-" * 78, lic + ": UNKNOWN LICENCE ID, no text found; header notices reproduced above."]
            out += (["  Reviewed: " + KNOWN_FLAGS[lic]] if lic in KNOWN_FLAGS else ["  Needs human review before publishing."]) + [""]
    for lic in unknown:
        why = KNOWN_FLAGS.get(lic)
        print("WARNING: licence id %r has no known text (see NOTICES); %s" %
              (lic, "known flag: " + why if why else "review before publishing"), file=sys.stderr)
    sys.stdout.buffer.write(("\n".join(out) + "\n").encode("utf-8"))


if __name__ == "__main__":
    main()
