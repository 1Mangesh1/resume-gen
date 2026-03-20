# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**RESUME.GEN** is an AI-powered resume tailoring system built as a collection of n8n workflows orchestrated via webhooks. It accepts a user's resume (PDF/TXT) and a job description (URL or text), then outputs an ATS-optimized PDF resume compiled from a LaTeX template.

This is **not** a traditional Node.js/TypeScript codebase — there are no `package.json`, test runners, or build tools. All logic lives in n8n workflow JSON files and a vanilla HTML frontend.

## Development Commands

All commands are via `make`:

```bash
make setup     # Copy .env.example → .env (first time only)
make up        # Start n8n + nginx via docker compose
make down      # Stop all services
make restart   # Restart all services
make import    # Import all 6 workflows into the running n8n instance
make logs      # Tail n8n container logs
make status    # Show docker compose ps output
make open      # Open n8n UI (port 5678) and frontend (port 3000) in browser
make clean     # Stop and remove volumes (destructive)
```

**First-time setup:**
1. `make setup` → edit `.env` with API keys
2. `make up`
3. `make import`
4. Open n8n UI → toggle all 6 workflows to **Active**

## Environment Variables

Required in `.env` (see `.env.example`):
- `GEMINI_API_KEY` — from aistudio.google.com/app/apikey
- `CF_API_TOKEN` + `CF_ACCOUNT_ID` — Cloudflare Browser Rendering (free: 10 min/day)
- `N8N_HOST`, `N8N_PORT`, `N8N_PROTOCOL`, `WEBHOOK_URL`, `TIMEZONE`

## Architecture

### 6-Workflow Pipeline

All inter-workflow communication is via HTTP webhook calls. The main entry point is a multipart form POST:

```
POST /webhook/resume-gen  (main-orchestrator)
  │
  ├── POST /webhook/resume-parser     ← Gemini extracts structured JSON from resume text
  ├── POST /webhook/jd-scraper        ← Cloudflare Browser Rendering → Jina AI fallback
  │
  └── POST /webhook/ai-tailoring-engine  ← Gemini re-ranks skills, rewrites bullets
        │
        └── POST /webhook/latex-generator   ← Fills Jake's Resume .tex, POSTs to ytotech API
              │
              └── POST /webhook/output-handler  ← Formats final JSON response
```

### Workflow Responsibilities

| Workflow | Webhook | Key External Service |
|---|---|---|
| `main-orchestrator.json` | `/webhook/resume-gen` | — |
| `resume-parser.json` | `/webhook/resume-parser` | Gemini 1.5 Pro |
| `jd-scraper.json` | `/webhook/jd-scraper` | Cloudflare Browser Rendering, Jina AI (`r.jina.ai`) |
| `ai-tailoring-engine.json` | `/webhook/ai-tailoring-engine` | Gemini 1.5 Pro |
| `latex-generator.json` | `/webhook/latex-generator` | latex.ytotech.com |
| `output-handler.json` | `/webhook/output-handler` | — |

### Resume JSON Schema (passes between workflows)

```json
{
  "contact": { "name", "email", "phone", "linkedin", "github" },
  "summary": "",
  "skills": [{ "category", "items": [] }],
  "experience": [{ "company", "title", "dates", "bullets": [] }],
  "projects": [{ "name", "tech": [], "bullets": [] }],
  "education": [{ "institution", "degree", "dates", "gpa" }]
}
```

### Response Schema

```json
{ "pdf_base64": "...", "tex_source": "...", "ats_score": 0-100, "matched_keywords": [] }
```

## Testing Workflows

Test individual workflows via curl:

```bash
# Full pipeline
curl -X POST http://localhost:5678/webhook/resume-gen \
  -F "resume=@/path/to/resume.pdf" \
  -F "jd_url=https://jobs.example.com/position"

# JD Scraper only
curl -X POST http://localhost:5678/webhook/jd-scraper \
  -H "Content-Type: application/json" \
  -d '{"url": "https://jobs.example.com/position"}'
```

Or use the frontend UI at `http://localhost:3000`.

## Workflow Import Script

`scripts/import-workflows.sh` patches workflow JSONs with sequential IDs (1–6), copies them into the n8n container, imports via `n8n import:workflow --separate`, and restarts n8n. Re-run with `make import` after modifying any workflow JSON.

## LaTeX Template

`templates/jake-resume.tex` is the Jake's Resume ATS-friendly template. The `latex-generator` workflow fills this template and compiles via the `latex.ytotech.com` REST API. On compile failure, raw `.tex` is returned so the user can fix it in Overleaf.

## Key Design Decisions

- **Modular sub-workflows** — each workflow is independently testable via its own webhook
- **Jina AI as scraper fallback** — free, no auth required at `r.jina.ai/<url>`
- **Gemini strict prompting** — resume-parser uses anti-hallucination constraints (only facts present in the original text)
- **n8n 2.x compatibility** — workflows must be published (not just imported) to activate webhooks; the import script handles this
