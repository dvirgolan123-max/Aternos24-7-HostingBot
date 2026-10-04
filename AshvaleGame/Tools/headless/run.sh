#!/bin/bash
# Builds and runs the headless core simulation inside the official Swift Docker image.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CORE_DIRS="Core World Items Entities Systems"
FILES=""
for d in $CORE_DIRS; do
  if [ -d "$ROOT/Ashvale/$d" ]; then
    FILES="$FILES $(cd "$ROOT" && find Ashvale/$d -name '*.swift' | sort | tr '\n' ' ')"
  fi
done
docker run --rm -v "$ROOT":/w -w /w swift:6.0-noble bash -c "mkdir -p /tmp/b && swiftc -swift-version 5 -O -module-name Ashvale $FILES Tools/headless/*.swift -o /tmp/b/headless 2>&1 | grep -v 'warning:' | head -${MAXERR:-80}; DEBUG_NAV=${DEBUG_NAV:-} OUT_DIR=/w/Tools/headless/out PREVIEW=${PREVIEW:-all} /tmp/b/headless $*"
