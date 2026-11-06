#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Orden
BIN="$(swift build -c release --show-bin-path)/Orden"
exec "$BIN"
