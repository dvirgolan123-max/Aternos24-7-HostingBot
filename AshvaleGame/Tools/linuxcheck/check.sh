#!/usr/bin/env bash
# Typechecks every Ashvale source file (including the UIKit / Metal / AVFoundation
# layers) on Linux against signature stubs of the Apple frameworks.
#   usage: Tools/linuxcheck/check.sh            (needs docker, image swift:6.0-noble)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUILD="$HERE/.build"
mkdir -p "$BUILD/modules"
python3 "$HERE/prepare_sources.py" "$ROOT/Ashvale" "$BUILD/src"
docker run --rm -v "$ROOT":/work -w /work/Tools/linuxcheck swift:6.0-noble bash -c '
set -e
M=.build/modules
for mod in CoreGraphics QuartzCore UIKit Metal MetalKit AVFoundation; do
  swiftc -swift-version 5 -parse-as-library -emit-module -module-name $mod -I $M stubs/$mod.swift -emit-module-path $M/$mod.swiftmodule
done
swiftc -swift-version 5 -parse-as-library -typecheck -I $M .build/src/*.swift 2>&1 | grep -v "^\s*$" | head -${MAXERR:-200}
echo "typecheck finished"
'
