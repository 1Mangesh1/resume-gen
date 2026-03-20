# Fix JSON Response Bug Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix two bugs that cause the frontend to crash with "Unexpected end of JSON input" and fall back to demo mode instead of showing real results.

**Architecture:** Two-layer fix — the n8n main-orchestrator workflow is changed to return a flat JSON object (not an n8n envelope array), and the frontend fetch is made defensive so empty or non-JSON responses produce a meaningful error instead of crashing.

**Tech Stack:** n8n workflow JSON, vanilla JS in a single HTML file, Docker (make import / make restart to deploy workflow changes).

---

### Task 1: Fix the n8n Respond to Webhook node in main-orchestrator.json

**Files:**
- Modify: `workflows/main-orchestrator.json` (the "Respond to Webhook" node, near line 207)

**Step 1: Locate the node to change**

In `workflows/main-orchestrator.json`, find the node with `"name": "Respond to Webhook"` (id `c3d4e5f6-0003-4000-8000-000000000012`). It currently looks like:

```json
{
  "parameters": {
    "respondWith": "allIncomingItems",
    "options": {}
  },
  "name": "Respond to Webhook",
  ...
}
```

**Step 2: Replace the parameters block**

Change `parameters` to:

```json
"parameters": {
  "respondWith": "json",
  "responseBody": "={\n  \"pdf_base64\": {{ JSON.stringify($json.pdf_base64 || null) }},\n  \"tex_source\": {{ JSON.stringify($json.tex_source || '') }},\n  \"ats_score\": {{ $json.ats_score || null }},\n  \"matched_keywords\": {{ JSON.stringify($json.matched_keywords || []) }},\n  \"status\": {{ JSON.stringify($json.status || 'error') }}\n}",
  "options": {
    "responseHeaders": {
      "entries": [
        {
          "name": "Content-Type",
          "value": "application/json"
        },
        {
          "name": "Access-Control-Allow-Origin",
          "value": "*"
        }
      ]
    }
  }
}
```

The CORS header `Access-Control-Allow-Origin: *` is added here because the frontend is served on port 3000 and calls n8n on port 5678 — cross-origin without it.

**Step 3: Verify the JSON file is still valid**

```bash
python3 -c "import json; json.load(open('workflows/main-orchestrator.json')); print('valid')"
```

Expected output: `valid`

**Step 4: Commit**

```bash
git add workflows/main-orchestrator.json
git commit -m "fix: return flat JSON from main-orchestrator webhook with CORS header"
```

---

### Task 2: Fix the frontend fetch to handle empty/non-JSON responses

**Files:**
- Modify: `frontend/index.html` (around line 1358)

**Step 1: Locate the fetch chain**

Find this block (around line 1357–1364):

```javascript
const [result] = await Promise.all([
  fetch(WEBHOOK_URL, { method: 'POST', body: formData })
    .then(r => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
    .catch(err => {
      addLog([['err','✗ '], ['', 'Error: ' + err.message]]);
      addLog([['warn','! '], ['', 'Falling back to demo mode']]);
      return getMockResult();
    }),
  simulateProgress(),
]);
```

**Step 2: Replace the fetch `.then` with a defensive text-first parser**

Replace only the `.then(r => ...)` line:

```javascript
const [result] = await Promise.all([
  fetch(WEBHOOK_URL, { method: 'POST', body: formData })
    .then(async r => {
      const text = await r.text();
      if (!text) throw new Error('Empty response — check n8n is running and workflows are Active');
      let data;
      try { data = JSON.parse(text); }
      catch (_) { throw new Error('Non-JSON response: ' + text.slice(0, 120)); }
      if (!r.ok) throw new Error('HTTP ' + r.status + ': ' + (data.message || text.slice(0, 80)));
      return data;
    })
    .catch(err => {
      addLog([['err','✗ '], ['', 'Error: ' + err.message]]);
      addLog([['warn','! '], ['', 'Falling back to demo mode']]);
      return getMockResult();
    }),
  simulateProgress(),
]);
```

**Step 3: Verify the HTML file is syntactically intact**

Open `http://localhost:3000` in a browser and confirm the page loads without console errors.

**Step 4: Commit**

```bash
git add frontend/index.html
git commit -m "fix: defensive fetch parsing — handle empty and non-JSON responses"
```

---

### Task 3: Deploy the workflow change and smoke test

**Step 1: Import the updated workflow into n8n**

```bash
make import
```

Expected: script runs without errors, prints something like "Workflow imported successfully".

**Step 2: Restart n8n to activate the new webhook**

```bash
make restart
```

**Step 3: Confirm n8n is up**

```bash
make status
```

Both `n8n` and `frontend` containers should show `Up`.

**Step 4: Open the n8n UI and verify main-orchestrator is Active**

```
http://localhost:5678
```

Toggle main-orchestrator workflow to Active if it isn't already.

**Step 5: Smoke test — curl the webhook directly**

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:5678/webhook/resume-gen \
  -F "resume=@/path/to/any.txt" \
  -F "jd_url=https://example.com"
```

Expected: `200` (not empty, not 404). If you get 404, the workflow isn't active.

**Step 6: Smoke test — full response shape**

```bash
curl -s \
  -X POST http://localhost:5678/webhook/resume-gen \
  -F "resume=@/path/to/any.txt" \
  -F "jd_text=We are looking for a software engineer" \
  | python3 -m json.tool
```

Expected: a JSON object with keys `pdf_base64`, `tex_source`, `ats_score`, `matched_keywords`, `status`. No `[{"json": ...}]` envelope.

**Step 7: Test via the frontend**

Open `http://localhost:3000`, upload a file, enter a job description, click Compile. Confirm:
- No "Falling back to demo mode" log line
- ATS score animates to a real value
- PDF and TEX download buttons work

**Step 8: Final commit (if any fixes were needed during smoke test)**

```bash
git add -p
git commit -m "fix: verified JSON response fix end-to-end"
```
