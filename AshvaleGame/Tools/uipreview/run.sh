#!/usr/bin/env bash
# Lays out every UIKit screen of the game on Linux (functional UIKit stand-ins) and
# renders PNG previews for several iPhone sizes into Tools/uipreview/out/.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUILD="$HERE/.build"
mkdir -p "$BUILD" "$HERE/out"
python3 "$ROOT/Tools/linuxcheck/prepare_sources.py" "$ROOT/Ashvale" "$BUILD/src" >/dev/null
rm -f "$BUILD/src/AppDelegate.swift"
docker run --rm -v "$ROOT":/w -w /w/Tools/uipreview swift:6.0-noble bash -c '
set -e
M=.build/modules; mkdir -p $M
for mod in CoreGraphics QuartzCore UIKit; do
  swiftc -swift-version 5 -parse-as-library -emit-module -module-name $mod -I $M stubs/$mod.swift -emit-module-path $M/$mod.swiftmodule -emit-library -static -o $M/lib$mod.a 2>&1 | grep -E "error" || true
done
for mod in Metal MetalKit AVFoundation; do
  swiftc -swift-version 5 -parse-as-library -emit-module -module-name $mod -I $M ../linuxcheck/stubs/$mod.swift -emit-module-path $M/$mod.swiftmodule -emit-library -static -o $M/lib$mod.a 2>&1 | grep -E "error" || true
done
swiftc -swift-version 5 -O -I $M -L $M -lCoreGraphics -lQuartzCore -lUIKit -lMetal -lMetalKit -lAVFoundation .build/src/*.swift main.swift -o .build/uipreview 2>&1 | grep -E "error" | head -40 || true
OUT_DIR=/w/Tools/uipreview/out .build/uipreview
'
python3 "$HERE/render.py" "$HERE/out" "$ROOT/Tools/headless/out"
