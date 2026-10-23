#!/usr/bin/env bash
set -u
set -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$DIR/stop.sh" || true
"$DIR/start.sh" -b
