#!/usr/bin/env bash
# Builds Vendor/llama.xcframework (iPhone + Simulator) from the pinned llama.cpp release.
# Runs on macOS with Xcode and CMake. CI caches the result, so this only runs when the pin changes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
read -r TAG COMMIT < "$ROOT/scripts/llama-version.txt"
WORK="$ROOT/build/llama.cpp"
OUT="$ROOT/Vendor/llama.xcframework"

if [[ -d "$OUT" ]]; then
  echo "llama.xcframework already present; delete Vendor/ to rebuild."
  exit 0
fi

rm -rf "$WORK"
git clone --depth 1 --branch "$TAG" https://github.com/ggml-org/llama.cpp.git "$WORK"
cd "$WORK"
if [[ "$(git rev-parse HEAD)" != "$COMMIT" ]]; then
  echo "llama.cpp $TAG is $(git rev-parse HEAD), expected $COMMIT. Refusing to build." >&2
  exit 1
fi
echo "Building llama.cpp $TAG ($(git rev-parse HEAD)) for iOS…"

# Only iPhone and the Simulator: much faster than the script's default of every Apple platform.
./build-xcframework.sh ios-sim ios-device

mkdir -p "$ROOT/Vendor"
cp -R build-apple/llama.xcframework "$OUT"
echo "$TAG $(git rev-parse HEAD)" > "$ROOT/Vendor/llama-version.txt"
echo "Done: $OUT"
