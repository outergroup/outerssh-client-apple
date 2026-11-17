#!/bin/bash
# Downloads the OuterSSH server helpers listed in helpers.sha256 into helpers/ and
# checks each against its hash, then copies them into DESTINATION if one is given.
# Files that are already in helpers/ with the right hash aren't downloaded again.
# Xcode runs this as a build phase, copying the helpers into the app's resources.
set -euo pipefail

version=0.5.4
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
destination="${1:-}"

sha256() { shasum -a 256 "$1" | cut -d ' ' -f 1; }

mkdir -p "$root/helpers"
grep -E '^[0-9a-f]{64}  ' "$root/helpers.sha256" | while read -r hash name; do
    file="$root/helpers/$name"
    if [[ ! -f "$file" || "$(sha256 "$file")" != "$hash" ]]; then
        curl -fsSL -o "$file.partial" "https://outerssh.org/download/outerssh/$version/$name"
        if [[ "$(sha256 "$file.partial")" != "$hash" ]]; then
            rm -f "$file.partial"
            echo "error: $name doesn't match its hash in helpers.sha256" >&2
            exit 1
        fi
        mv "$file.partial" "$file"
    fi
    if [[ -n "$destination" ]]; then
        mkdir -p "$destination"
        cp "$file" "$destination/$name"
    fi
done
