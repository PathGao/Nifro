#!/bin/bash
# Compatibility entry point. Existing destinations are never overwritten.
set -euo pipefail
cd "$(dirname "$0")/.."
destination="${1:-}"
if [[ -n "$destination" && ( -e "$destination" || -L "$destination" ) ]]; then
  echo "Destination already exists: $destination" >&2
  exit 1
fi
./build.sh dev
if [[ -n "$destination" ]]; then
  ditto .xcode-build/Build/Products/Release/Nifro.app "$destination"
fi
