#!/bin/sh
# Copia o app web (pasta acima de ios/) para dentro do app iOS.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/.."
DST="$DIR/Livre/web"
mkdir -p "$DST"
for f in index.html manifest.json icon.svg icon-192.png icon-512.png; do
  cp "$SRC/$f" "$DST/$f"
done
