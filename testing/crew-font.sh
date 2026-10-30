#!/bin/bash
# Builds AgentValleyCrew.ttf, the crew's faces as a colour font, from the same cells the notch
# draws. Run it whenever a person or a pose changes, and commit the font with the change:
# CrewFontTests fails while the font is behind the code.
set -euo pipefail
cd "$(dirname "$0")/.."

# brotli reads the woff2 of IBM Plex Mono, the name tags' letters.
if ! .build/fontenv/bin/python -c 'import fontTools, brotli' 2>/dev/null; then
    python3 -m venv .build/fontenv
    .build/fontenv/bin/pip install --quiet fonttools==4.67.0 brotli==1.1.0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
CREW_FACES_OUT="$tmp/faces.json" swift test --filter CrewFontTests/testWriteTheFacesForTheFont
.build/fontenv/bin/python testing/crew-font.py "$tmp/faces.json" AgentValleyCrew.ttf
