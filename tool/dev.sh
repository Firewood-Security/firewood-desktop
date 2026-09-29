#!/usr/bin/env bash
# Run Firewood Desktop with Hot Reload & Hot Restart
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Starting Firewood Desktop in Development Mode (Hot Reload enabled) =="
flutter run -d linux "$@"
