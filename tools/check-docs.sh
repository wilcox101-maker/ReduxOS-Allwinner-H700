#!/usr/bin/env bash
# check-docs.sh — verify that every relative Markdown link in the repo resolves to a file that exists.
# Skips external links (http/https/mailto) and in-page anchors (#...). Exits non-zero on any broken link.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

fail=0
# All tracked markdown files.
mapfile -t mdfiles < <(git ls-files '*.md')

for f in "${mdfiles[@]}"; do
	dir="$(dirname "$f")"
	# Extract [..](target) targets.
	grep -oE '\]\([^)]+\)' "$f" | sed -E 's/^\]\(//; s/\)$//' | while read -r link; do
		# Strip surrounding whitespace and any title: (path "title")
		link="${link%% *}"
		case "$link" in
			http://*|https://*|mailto:*|\#*) continue ;;  # external / anchor
		esac
		# Drop any #anchor suffix.
		target="${link%%#*}"
		[ -z "$target" ] && continue
		# Resolve relative to the file's directory.
		resolved="$(cd "$dir" 2>/dev/null && printf '%s' "$(realpath -m "$target")")"
		if [ ! -e "$resolved" ]; then
			printf 'BROKEN LINK: %s -> %s\n' "$f" "$link" >&2
			echo "x" >> /tmp/check-docs.fail
		fi
	done
done

if [ -f /tmp/check-docs.fail ]; then
	fail=$(wc -l < /tmp/check-docs.fail)
	rm -f /tmp/check-docs.fail
	printf '\n%s broken relative link(s) found.\n' "$fail" >&2
	exit 1
fi

echo "check-docs: all relative Markdown links resolve."
