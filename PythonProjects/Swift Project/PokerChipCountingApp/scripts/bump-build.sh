#!/bin/sh
# Raises the build number (or sets it): the one number App Store Connect needs to be
# different for every upload of the same version.
#
#   scripts/bump-build.sh        # one more than now
#   scripts/bump-build.sh 7      # exactly 7
#
# The app, its widget extension and the test targets all take the version from the
# project's own build settings (CURRENT_PROJECT_VERSION and MARKETING_VERSION in the
# two project-level configurations), so this changes exactly those two lines.
set -eu

PBX="$(dirname "$0")/../PokerChipApp.xcodeproj/project.pbxproj"
[ -f "$PBX" ] || { echo "can't find $PBX" >&2; exit 1; }

current="$(grep -E '^[[:space:]]*CURRENT_PROJECT_VERSION = [0-9]+;' "$PBX" | head -1 | sed -E 's/.*= ([0-9]+);/\1/')"
[ -n "$current" ] || { echo "no CURRENT_PROJECT_VERSION found" >&2; exit 1; }

if [ "$#" -ge 1 ]; then
  case "$1" in ''|*[!0-9]*) echo "the build number must be a whole number" >&2; exit 2 ;; esac
  next="$1"
else
  next=$((current + 1))
fi

sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\1$next;/" "$PBX"
echo "build number: $current -> $next"
grep -c "CURRENT_PROJECT_VERSION = $next;" "$PBX" | sed 's/^/places set: /'
