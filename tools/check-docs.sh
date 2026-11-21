#!/usr/bin/env bash
# check-docs.sh — verify that every relative Markdown link in the repo resolves to a file that exists.
# Skips external links (http/https/mailto) and in-page anchors (#...). Exits non-zero on any broken link.
# Deliberately does NOT use `set -e`/pipefail abort semantics: files with no links are normal.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

broken=0
while IFS= read -r f; do
	[ -n "$f" ] || continue
	dir="$(dirname "$f")"
	while IFS= read -r link; do
		[ -n "$link" ] || continue
		case "$link" in
			http://*|https://*|mailto:*|\#*) continue ;;  # external / anchor
		esac
		target="${link%%#*}"          # drop any #anchor suffix
		[ -n "$target" ] || continue
		if [ ! -e "$dir/$target" ] && [ ! -e "$(realpath -m "$dir/$target" 2>/dev/null)" ]; then
			echo "BROKEN LINK: $f -> $link" >&2
			broken=$((broken + 1))
		fi
	done < <(grep -oE '\]\([^)[:space:]]+' "$f" 2>/dev/null | sed -E 's/^\]\(//' || true)
done < <(git ls-files '*.md')

if [ "$broken" -gt 0 ]; then
	echo "$broken broken relative Markdown link(s) found." >&2
	exit 1
fi
echo "check-docs: all relative Markdown links resolve."
