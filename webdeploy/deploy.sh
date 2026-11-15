#!/usr/bin/env bash
# Publish the web build to Railway (service "web" in project space-turism-relay).
#   1. Export the "Web" preset with the STANDARD Godot build (the mono editor can't export to web):
#        Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Web" build/web/index.html
#   2. bash webdeploy/deploy.sh [path/to/build/web]     (default: build/web)
# Copies the build into webdeploy/site (git-ignored), writes .gz copies of the big files, uploads.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
build="${1:-$here/../build/web}"
[ -f "$build/index.html" ] || { echo "no web build at $build (export the Web preset first)"; exit 1; }

rm -rf "$here/site"
mkdir -p "$here/site"
cp "$build"/index.* "$here/site/"
rm -f "$here"/site/*.import
python -I - "$here/site" <<'EOF'
import gzip, pathlib, shutil, sys
for f in pathlib.Path(sys.argv[1]).iterdir():
    if f.suffix in (".wasm", ".js", ".html"):   # .pck is already compressed data (~3% smaller as gzip)
        with open(f, "rb") as src, gzip.open(str(f) + ".gz", "wb", compresslevel=9) as dst:
            shutil.copyfileobj(src, dst)
EOF
du -sh "$here/site"

cd "$here"
# --no-gitignore: site/ is git-ignored (a copied build), but it IS what we upload.
railway up --no-gitignore --project 24226d88-1c55-4beb-aa3f-d8d381e029d0 --environment production --service web --detach -m "web build"
echo "Uploaded. Watch it with: railway deployment list --service web --json"
