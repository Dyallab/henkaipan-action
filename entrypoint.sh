#!/bin/bash
# entrypoint.sh — HenKaiPan GitHub Action
# Main entrypoint for the Docker-based action

set -euo pipefail

# ── Input mapping from positional args (passed via action.yml runs.args) ──────
API_URL="${1:-}"
API_KEY="${2:-}"
PROJECT_ID="${3:-}"
SCANNERS="${4:-all}"
FAIL_ON="${5:-}"
SCAN_BRANCH="${6:-}"
POST_PR_COMMENT="${7:-true}"
CF_CLIENT_ID="${8:-}"
CF_CLIENT_SECRET="${9:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GITHUB_EVENT_NAME="${GITHUB_EVENT_NAME:-}"
GITHUB_REF="${GITHUB_REF:-}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"
PR_NUMBER="${PR_NUMBER:-}"

# Extract PR number from GitHub event file if not already set
if [[ -z "$PR_NUMBER" && -n "$GITHUB_EVENT_PATH" && -f "$GITHUB_EVENT_PATH" ]]; then
    PR_NUMBER=$(jq -r '.pull_request.number // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)
fi

# Strip trailing slash from API_URL to prevent double-slash in path
while [[ "$API_URL" == */ ]]; do API_URL="${API_URL%/}"; done

# ── Validate required inputs ──────────────────────────────────────────────────
if [[ -z "$API_URL" ]]; then
    echo "ERROR: api-url is required. Set the 'api-url' input."
    exit 1
fi
if [[ -z "$API_KEY" ]]; then
    echo "ERROR: api-key is required. Set the 'api-key' input."
    exit 1
fi
if [[ -z "$PROJECT_ID" ]]; then
    echo "ERROR: project-id is required. Set the 'project-id' input."
    exit 1
fi

# ── Cloudflare Access Service Token headers (optional) ─────────────────────────
CURL_COMMON_ARGS=(-s --compressed -H "Content-Type: application/json" -H "X-API-Key: $API_KEY" -H "User-Agent: HenKaiPan-Action/1.1.0")
if [[ -n "$CF_CLIENT_ID" && -n "$CF_CLIENT_SECRET" ]]; then
    CURL_COMMON_ARGS+=(-H "CF-Access-Client-Id: $CF_CLIENT_ID" -H "CF-Access-Client-Secret: $CF_CLIENT_SECRET")
    echo "Cloudflare Access: using Service Token authentication"
fi

echo "=============================================="
echo " HenKaiPan Security Scan"
echo "=============================================="
echo "API URL     : $API_URL"
echo "Project ID  : $PROJECT_ID"
echo "Scanners    : $SCANNERS"
echo "Fail on     : ${FAIL_ON:-none}"
echo "Branch      : ${SCAN_BRANCH:-<current branch>}"
[[ -n "$CF_CLIENT_ID" ]] && echo "CF Access   : enabled"
echo "=============================================="

# ── Determine target (repo URL + optional branch) ────────────────────────────
# Detect the GitHub repository URL from the runner environment
REPO_URL="https://github.com/${GITHUB_REPOSITORY}.git"
GITHUB_BRANCH="${SCAN_BRANCH:-${GITHUB_REF#refs/heads/}}"

echo ""
echo "[1/3] Triggering scan for $REPO_URL (branch: $GITHUB_BRANCH)..."

PAYLOAD=$(jq -n \
    --arg pid "$PROJECT_ID" \
    --arg url "$REPO_URL" \
    --arg scanners "$SCANNERS" \
    --arg branch "$GITHUB_BRANCH" \
    '{
        project_id: $pid,
        repo_url: $url,
        scanners: ($scanners | split(",") | map(trim)),
        branch: $branch
    }')

# ── Trigger scan ──────────────────────────────────────────────────────────────
HTTP_CODE=$(curl "${CURL_COMMON_ARGS[@]}" -X POST \
    -d "$PAYLOAD" \
    -o /tmp/hkp-response.json \
    -w "%{http_code}" \
    "$API_URL/api/v1/scans/external") || true

RESPONSE=$(cat /tmp/hkp-response.json 2>/dev/null || echo "")

# Detect non-JSON responses (Cloudflare challenge pages, proxies, etc.)
if [[ "$RESPONSE" == \<* ]]; then
    echo "ERROR: Received HTML instead of JSON from $API_URL"
    echo "       This usually means a reverse proxy or firewall (e.g. Cloudflare)"
    echo "       is blocking the request with a challenge page."
    echo ""
    echo "  Fixes:"
    echo "  • Cloudflare: add a WAF Skip rule for URI Path starts with /api/v1/scans/"
    echo "  • Or set cf-access-client-id / cf-access-client-secret if using Cloudflare Access"
    echo "  • Or disable Bot Fight Mode for the API path"
    echo ""
    echo "  HTTP status: $HTTP_CODE"
    echo "  Response (first 200 chars): ${RESPONSE:0:200}"
    exit 1
fi

if [[ -z "$RESPONSE" && "$HTTP_CODE" == "000" ]]; then
    echo "ERROR: Failed to connect to HenKaiPan at $API_URL"
    exit 1
fi

if ! echo "$RESPONSE" | jq -e . >/dev/null 2>&1; then
    echo "ERROR: Received non-JSON response from $API_URL (HTTP $HTTP_CODE)"
    echo "  Response (first 200 chars): ${RESPONSE:0:200}"
    exit 1
fi

# Parse scan response
SCAN_IDS=$(echo "$RESPONSE" | jq -r '.scan_ids // [] | join(",")')
BATCH_ID=$(echo "$RESPONSE" | jq -r '.batch_id // ""')
HTTP_STATUS=$(echo "$RESPONSE" | jq -r '.status // empty')

if [[ "$HTTP_STATUS" != "accepted" ]]; then
    ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error // .message // "Unknown error"')
    echo "ERROR: HenKaiPan rejected the scan request: $ERROR_MSG"
    exit 1
fi

echo "      Scan accepted — batch: $BATCH_ID, IDs: $SCAN_IDS"

# ── Poll for completion ───────────────────────────────────────────────────────
echo ""
echo "[2/3] Waiting for scan to complete..."

SEVERITY_ORDER="critical high medium low"
declare -A SEVERITY_WEIGHT=([critical]=4 [high]=3 [medium]=2 [low]=1)

FAIL_THRESHOLD=0
if [[ -n "$FAIL_ON" && "$FAIL_ON" != "none" ]]; then
    # Convert severity name to numeric threshold
    case "$FAIL_ON" in
        critical) FAIL_THRESHOLD=4 ;;
        high)     FAIL_THRESHOLD=3 ;;
        medium)   FAIL_THRESHOLD=2 ;;
        low)      FAIL_THRESHOLD=1 ;;
        *)        FAIL_THRESHOLD=0 ;;
    esac
fi

POLL_INTERVAL=15
MAX_WAIT=$((20 * 60))  # 20 minutes max
ELAPSED=0

FAILED_SCANS=""
TOTAL_CRITICAL=0
TOTAL_HIGH=0
TOTAL_MEDIUM=0
TOTAL_LOW=0

# Split scan IDs and track per-scan state
IFS=',' read -ra SCAN_ID_ARRAY <<< "$SCAN_IDS"
declare -A SCAN_STATES
for sid in "${SCAN_ID_ARRAY[@]}"; do
    SCAN_STATES[$sid]="pending"
done

while true; do
    if [[ $ELAPSED -ge $MAX_WAIT ]]; then
        echo "ERROR: Timed out after ${MAX_WAIT}s waiting for scans."
        exit 1
    fi

    ALL_DONE=true
    for SCAN_ID in "${SCAN_ID_ARRAY[@]}"; do
        STATE="${SCAN_STATES[$SCAN_ID]}"
        if [[ "$STATE" == "completed" || "$STATE" == "failed" ]]; then
            continue
        fi

        STATUS_RESP=$(curl "${CURL_COMMON_ARGS[@]}" \
            "$API_URL/api/v1/scans/$SCAN_ID/status") || true

        if [[ -z "$STATUS_RESP" ]]; then
            echo "WARN: Empty response querying scan $SCAN_ID, retrying..."
            sleep $POLL_INTERVAL
            ELAPSED=$((ELAPSED + POLL_INTERVAL))
            ALL_DONE=false
            break
        fi

        if [[ "$STATUS_RESP" == \<* ]]; then
            echo "WARN: Received HTML challenge querying scan $SCAN_ID (proxy/firewall blocking), retrying..."
            sleep $POLL_INTERVAL
            ELAPSED=$((ELAPSED + POLL_INTERVAL))
            ALL_DONE=false
            break
        fi

        NEW_STATE=$(echo "$STATUS_RESP" | jq -r '.scan.status // "unknown"')
        SCAN_STATES[$SCAN_ID]="$NEW_STATE"

        if [[ "$NEW_STATE" == "running" || "$NEW_STATE" == "pending" ]]; then
            ALL_DONE=false
        fi

        if [[ "$NEW_STATE" == "failed" ]]; then
            FAILED_SCANS="$FAILED_SCANS $SCAN_ID"
        fi

        # Accumulate finding counts
        if [[ "$NEW_STATE" == "completed" ]]; then
            # Sum findings by severity from the response
            CRIT=$(echo "$STATUS_RESP" | jq '[.findings[] | select(.severity == "critical")] | length')
            HIGH=$(echo "$STATUS_RESP" | jq '[.findings[] | select(.severity == "high")] | length')
            MED=$(echo "$STATUS_RESP" | jq '[.findings[] | select(.severity == "medium")] | length')
            LOW=$(echo "$STATUS_RESP" | jq '[.findings[] | select(.severity == "low")] | length')
            TOTAL_CRITICAL=$((TOTAL_CRITICAL + CRIT))
            TOTAL_HIGH=$((TOTAL_HIGH + HIGH))
            TOTAL_MEDIUM=$((TOTAL_MEDIUM + MED))
            TOTAL_LOW=$((TOTAL_LOW + LOW))
        fi

        echo "      Scan $SCAN_ID: $NEW_STATE"
    done

    if $ALL_DONE; then
        break
    fi

    echo "      Waiting ${POLL_INTERVAL}s..."
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

echo ""
echo "[3/3] Scan complete."

# ── Report results ────────────────────────────────────────────────────────────
TOTAL=$((TOTAL_CRITICAL + TOTAL_HIGH + TOTAL_MEDIUM + TOTAL_LOW))

echo ""
echo "=============================================="
echo " HenKaiPan Scan Results"
echo "=============================================="
echo "Critical : $TOTAL_CRITICAL"
echo "High     : $TOTAL_HIGH"
echo "Medium   : $TOTAL_MEDIUM"
echo "Low      : $TOTAL_LOW"
echo "Total    : $TOTAL"
echo "=============================================="

# Check for failed scans
if [[ -n "$FAILED_SCANS" ]]; then
    echo "WARNING: Some scans failed:$FAILED_SCANS"
fi

# ── Set GitHub Action outputs ─────────────────────────────────────────────────
echo "scan-id=$SCAN_IDS" >> "$GITHUB_OUTPUT"
echo "finding-count=$TOTAL" >> "$GITHUB_OUTPUT"
echo "finding-critical=$TOTAL_CRITICAL" >> "$GITHUB_OUTPUT"
echo "finding-high=$TOTAL_HIGH" >> "$GITHUB_OUTPUT"
echo "finding-medium=$TOTAL_MEDIUM" >> "$GITHUB_OUTPUT"
echo "finding-low=$TOTAL_LOW" >> "$GITHUB_OUTPUT"

# ── Determine exit code ──────────────────────────────────────────────────────
if [[ $FAIL_THRESHOLD -gt 0 ]]; then
    CURRENT_WEIGHT=0
    if   [[ $TOTAL_CRITICAL -gt 0 && $FAIL_THRESHOLD -le 4 ]]; then CURRENT_WEIGHT=4
    elif [[ $TOTAL_HIGH     -gt 0 && $FAIL_THRESHOLD -le 3 ]]; then CURRENT_WEIGHT=3
    elif [[ $TOTAL_MEDIUM   -gt 0 && $FAIL_THRESHOLD -le 2 ]]; then CURRENT_WEIGHT=2
    elif [[ $TOTAL_LOW      -gt 0 && $FAIL_THRESHOLD -le 1 ]]; then CURRENT_WEIGHT=1
    fi

    if [[ $CURRENT_WEIGHT -ge $FAIL_THRESHOLD ]]; then
        echo ""
        echo "ERROR: Findings exceed fail-on-severity threshold ($FAIL_ON)."
        echo "Blocking pipeline."
        exit 1
    fi
fi

echo ""
echo "HenKaiPan scan completed successfully."

# ── Post PR comment ────────────────────────────────────────────────────────────
postPRComment() {
    if [[ "$POST_PR_COMMENT" != "true" ]]; then
        return 0
    fi
    if [[ "$GITHUB_EVENT_NAME" != "pull_request" ]]; then
        return 0
    fi
    if [[ -z "$PR_NUMBER" || "$PR_NUMBER" == "null" || -z "$GITHUB_TOKEN" ]]; then
        return 0
    fi

    echo ""
    echo "[PR] Posting results to GitHub PR #$PR_NUMBER..."

    # Build markdown body
    local BLOCKED=""
    if [[ $FAIL_THRESHOLD -gt 0 && $CURRENT_WEIGHT -ge $FAIL_THRESHOLD ]]; then
        BLOCKED=" 🚫 **Pipeline blocked** — findings meet or exceed `$FAIL_ON` threshold."
    fi

    local BODY=$(cat <<COMMENT_EOF
## 🔍 HenKaiPan Security Scan Results

| Severity | Count |
|----------|-------:|
| 🔴 Critical | **$TOTAL_CRITICAL** |
| 🟠 High | **$TOTAL_HIGH** |
| 🟡 Medium | **$TOTAL_MEDIUM** |
| 🟢 Low | **$TOTAL_LOW** |

**Total: $TOTAL finding(s)** | Scan IDs: \`$SCAN_IDS\`$BLOCKED

_This comment was posted automatically by the HenKaiPan GitHub Action._
COMMENT_EOF
)

    # Post or edit existing comment
    local COMMENT_ID=""
    local PAYLOAD
    PAYLOAD=$(jq -n --arg body "$BODY" '{"body": $body}')
    local POST_STATUS=0

    if COMMENT_ID=$(curl -s -f \
        -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
        | jq -r '.[] | select(.body | contains("HenKaiPan Security Scan Results")) | .id' 2>/dev/null \
        | head -1) && [[ -n "$COMMENT_ID" ]]; then
        echo "[PR] Updating existing comment $COMMENT_ID..."
        curl -s -f -X PATCH \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" \
            "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/comments/$COMMENT_ID" \
            > /dev/null 2>&1 || POST_STATUS=$?
    else
        echo "[PR] Posting new comment..."
        curl -s -f -X POST \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" \
            "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
            > /dev/null 2>&1 || POST_STATUS=$?
    fi

    if [[ $POST_STATUS -eq 0 ]]; then
        echo "[PR] Comment posted successfully."
    else
        echo "[PR] Failed to post comment (non-fatal, continuing)."
    fi
}

postPRComment

exit 0
