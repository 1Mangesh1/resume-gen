#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# import-workflows.sh
# Imports all n8n workflow JSONs using the n8n CLI inside Docker.
# Run AFTER `docker compose up -d`.
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

WORKFLOWS_DIR="$(cd "$(dirname "$0")/../workflows" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}!${NC} $*"; }
log_err()  { echo -e "${RED}✗${NC} $*"; }

# ── Detect container name ────────────────────────────────────────
CONTAINER=$(docker compose ps -q n8n 2>/dev/null | head -1)
if [ -z "$CONTAINER" ]; then
  log_err "n8n container not running. Run 'make up' first."
  exit 1
fi

# ── Wait for n8n to be ready ─────────────────────────────────────
echo "Waiting for n8n..."
MAX_WAIT=60; ELAPSED=0
until curl -sf http://localhost:5678/healthz > /dev/null 2>&1; do
  sleep 2; ELAPSED=$((ELAPSED + 2))
  [ $ELAPSED -ge $MAX_WAIT ] && log_err "n8n not ready after ${MAX_WAIT}s" && exit 1
done
log_ok "n8n is up"

# ── Patch workflow JSONs with required numeric ids ───────────────
python3 -c "
import json, os, sys
files = [
  ('jd-scraper.json',            1),
  ('resume-parser.json',         2),
  ('ai-tailoring-engine.json',   3),
  ('latex-generator.json',       4),
  ('output-handler.json',        5),
  ('main-orchestrator.json',     6),
]
wdir = sys.argv[1]
for fname, fid in files:
    path = os.path.join(wdir, fname)
    if not os.path.exists(path):
        continue
    with open(path) as f:
        d = json.load(f)
    d['id'] = fid
    with open(path, 'w') as f:
        json.dump(d, f, indent=2)
" "$WORKFLOWS_DIR"

# ── Import order: sub-workflows before orchestrator ──────────────
IMPORT_ORDER=(
  "jd-scraper.json"
  "resume-parser.json"
  "ai-tailoring-engine.json"
  "latex-generator.json"
  "output-handler.json"
  "main-orchestrator.json"
)

echo ""
echo "Importing workflows..."
echo "─────────────────────────────────"

IMPORTED=0; FAILED=0

for filename in "${IMPORT_ORDER[@]}"; do
  filepath="${WORKFLOWS_DIR}/${filename}"
  [ -f "$filepath" ] || { log_warn "Skipping (not found): ${filename}"; continue; }

  docker compose cp "$filepath" "n8n:/tmp/${filename}" > /dev/null 2>&1
  RESULT=$(docker compose exec n8n n8n import:workflow --input="/tmp/${filename}" 2>&1)

  if echo "$RESULT" | grep -q "Successfully imported"; then
    log_ok "${filename}"
    IMPORTED=$((IMPORTED + 1))
  else
    log_err "${filename} → ${RESULT}"
    FAILED=$((FAILED + 1))
  fi
done

echo "─────────────────────────────────"
log_ok "Imported: ${IMPORTED} / $((IMPORTED + FAILED)) workflows"
[ $FAILED -gt 0 ] && log_warn "${FAILED} failed — check output above"

# ── Publish all workflows (n8n 2.x requires published version) ───
echo ""
echo "Publishing workflows..."
for id in 1 2 3 4 5 6; do
  docker compose exec n8n n8n publish:workflow --id=$id > /dev/null 2>&1 && log_ok "Published workflow $id"
done

# ── Restart so published versions take effect ────────────────────
echo ""
echo "Restarting n8n to activate webhooks..."
docker compose restart n8n > /dev/null 2>&1
sleep 8
until curl -sf http://localhost:5678/healthz > /dev/null 2>&1; do sleep 2; done
log_ok "n8n restarted"

echo ""
echo "  UI ready at: http://localhost:3000"
echo ""
