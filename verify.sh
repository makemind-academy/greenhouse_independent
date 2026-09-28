#!/bin/bash
# greenhouse-independent — verified in AppPlayer. Prerequisites: tools/appplayer.py header.
set -euo pipefail
cd "$(dirname "$0")"
echo "   [build] greenhouse_bus (C)"
( cd greenhouse_bus && cc -O2 -o greenhouse_bus greenhouse_bus.c -lm )
echo "   [analyze] greenhouse_server"
( cd greenhouse_server && dart pub get >/dev/null && dart analyze | tail -1 )
echo "   [player] open in AppPlayer, drive it, capture"
rm -f captures/*.png
python3 verify.py
COUNT=$(ls captures/*.png | wc -l | tr -d ' ')
[ "$COUNT" -eq 4 ] || { echo "   expected 4 captures, got $COUNT"; exit 1; }
