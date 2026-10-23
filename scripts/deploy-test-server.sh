#!/usr/bin/env bash
# Retained entry point: the foundation release requires coordinated rules + APK.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
exec bash scripts/deploy-test-foundation.sh
