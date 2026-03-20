# Fix: JSON Response Bug Design

**Date:** 2026-03-19
**Status:** Approved

## Problem

Two bugs cause the frontend to fall back to demo mode with the error:
`Failed to execute 'json' on 'Response': Unexpected end of JSON input`

**Bug 1 — Empty response body crash**
When n8n can't reach its "Respond to Webhook" node (workflow inactive, execution error, or CORS), it returns a 200 with an empty body. The frontend's `r.json()` call throws "Unexpected end of JSON input", which is caught and triggers demo mode.

**Bug 2 — Wrong response envelope (silent failure)**
Both `main-orchestrator` and `output-handler` use `respondWith: allIncomingItems`, which wraps the payload as `[{"json": {...}, "pairedItem": {...}}]`. The frontend accesses `data.ats_score`, `data.pdf_base64` etc. directly — these are `undefined` on an array, so downloads and score silently break even on a successful run.

## Solution: Option C — Fix Both Layers

### Change 1: `workflows/main-orchestrator.json`

In the "Respond to Webhook" node, change:
- `respondWith`: `allIncomingItems` → `json`
- Add explicit `responseBody` with the fields the frontend expects:

```json
{
  "pdf_base64":       "={{ $json.pdf_base64 || null }}",
  "tex_source":       "={{ $json.tex_source || '' }}",
  "ats_score":        "={{ $json.ats_score || null }}",
  "matched_keywords": "={{ $json.matched_keywords || [] }}",
  "status":           "={{ $json.status || 'error' }}"
}
```

This returns a flat, predictable JSON object with no n8n envelope.

### Change 2: `frontend/index.html`

Replace:
```javascript
.then(r => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
```

With:
```javascript
.then(async r => {
  const text = await r.text();
  if (!text) throw new Error('Empty response from server');
  const data = JSON.parse(text);
  if (!r.ok) throw new Error('HTTP ' + r.status + ': ' + (data.message || ''));
  return data;
})
```

## Scope

- Only `main-orchestrator.json` needs the Respond to Webhook fix (it's the entry point the frontend calls).
- `output-handler.json` can stay as-is — its response goes back to the HTTP Request node inside main-orchestrator, not directly to the frontend.
- No changes to any other workflow.

## After Implementation

Run `make import` and `make restart` to reload the updated workflow into n8n.
