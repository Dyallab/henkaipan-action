#!/bin/bash
# cleanup.sh — HenKaiPan GitHub Action
# Runs when the action is cancelled or interrupted.
# Currently a no-op since scans are fire-and-forget, but can be
# extended to call DELETE /api/v1/scans/{id}/cancel if such an endpoint
# is added to the API.

set -euo pipefail

SCAN_IDS="${1:-}"

if [[ -z "$SCAN_IDS" ]]; then
    exit 0
fi

echo "HenKaiPan action cancelled. Scan(s) will continue on the server but no output will be captured."
exit 0
