# RESUME.GEN — AI-Powered Resume Generator

Automated n8n workflow that takes your resume + a job description and outputs a tailored, ATS-optimized PDF compiled from a LaTeX template.

**Stack:** n8n · Google Gemini 1.5 Pro · Cloudflare Browser Rendering · Jina AI · LaTeX (ytotech)

---

## Quick Start

### 1. Prerequisites
- Docker + Docker Compose
- Google Gemini API key → [aistudio.google.com](https://aistudio.google.com/app/apikey)
- Cloudflare account (free tier) → API token with **Browser Rendering - Edit** permission

### 2. Configure environment
```bash
cp .env.example .env
# Edit .env and fill in your API keys
```

### 3. Start services
```bash
docker compose up -d
```

n8n → `http://localhost:5678`
Frontend → `http://localhost:3000`

### 4. Import workflows
```bash
./scripts/import-workflows.sh
```

Or manually: open `http://localhost:5678` → **Workflows** → **Import from File** → import each file in `workflows/` in this order:
1. `jd-scraper.json`
2. `resume-parser.json`
3. `ai-tailoring-engine.json`
4. `latex-generator.json`
5. `output-handler.json`
6. `main-orchestrator.json`

### 5. Activate workflows
In n8n UI, toggle all 6 workflows to **Active**.

### 6. Use it
Open `http://localhost:3000`, upload your resume PDF, paste a job URL or JD text, click **Compile Resume**.

---

## Architecture

```
Webhook (POST /webhook/resume-gen)
  ↓
Extract PDF → text
  ↓
HTTP → /webhook/jd-scraper          (Cloudflare BR → Jina fallback → manual)
  ↓
HTTP → /webhook/resume-parser       (Gemini extracts structured JSON)
  ↓
HTTP → /webhook/ai-tailoring-engine (Gemini tailors resume to JD)
  ↓
HTTP → /webhook/latex-generator     (builds .tex, compiles via ytotech)
  ↓
HTTP → /webhook/output-handler      (formats final response)
  ↓
Response: { pdf_base64, tex_source, ats_score, matched_keywords }
```

### Sub-workflows

| Workflow | Webhook Path | Input | Output |
|---|---|---|---|
| JD Scraper | `/webhook/jd-scraper` | `{url?, text?}` | `{jd_raw, source}` |
| Resume Parser | `/webhook/resume-parser` | `{resume_text}` | structured JSON |
| AI Tailoring Engine | `/webhook/ai-tailoring-engine` | `{resume_json, jd_raw}` | `{tailored_resume, matched_keywords, ats_score}` |
| LaTeX Generator | `/webhook/latex-generator` | `{tailored_resume}` | `{tex_source, pdf_base64}` |
| Output Handler | `/webhook/output-handler` | all fields | formatted final JSON |
| Main Orchestrator | `/webhook/resume-gen` | multipart form | final response |

---

## Project Structure

```
n8n/
├── frontend/
│   └── index.html              # UI (served via nginx on :3000)
├── workflows/
│   ├── jd-scraper.json
│   ├── resume-parser.json
│   ├── ai-tailoring-engine.json
│   ├── latex-generator.json
│   ├── output-handler.json
│   └── main-orchestrator.json
├── templates/
│   └── jake-resume.tex         # Reference LaTeX template
├── scripts/
│   └── import-workflows.sh     # Auto-import script
├── docs/
│   └── plans/
│       └── 2026-03-19-ai-resume-generator-design.md
├── docker-compose.yml
├── .env.example
└── README.md
```

---

## API Keys Setup

### Google Gemini
1. Go to [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey)
2. Create a new API key
3. Add to `.env` as `GEMINI_API_KEY`

### Cloudflare Browser Rendering
1. Go to [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Create token → **Custom token** → permission: **Browser Rendering - Edit**
3. Your Account ID is shown in the right sidebar of [dash.cloudflare.com](https://dash.cloudflare.com)
4. Add both to `.env`

**Free tier:** 10 minutes of browser time/day — enough for ~30 job scrapes.

**Note:** Cloudflare Browser Rendering cannot bypass Cloudflare's own Turnstile/bot protection. LinkedIn, Indeed, and similar sites will automatically fall back to Jina AI Reader (free, no setup).

---

## Scraping Behaviour

| Site type | Method used |
|---|---|
| Greenhouse, Lever, Workday, company pages | Cloudflare Browser Rendering |
| Sites with Cloudflare Turnstile / heavy bot protection | Jina AI (`r.jina.ai`) |
| LinkedIn, Indeed (very aggressive blocking) | Manual paste fallback |

---

## LaTeX Compilation

Uses [latex.ytotech.com](https://latex.ytotech.com) — free, supports full TeXLive.

If compilation fails, the raw `.tex` source is still returned. Open it in [Overleaf](https://overleaf.com) to debug.

---

## Testing

```bash
# Test JD scraper directly
curl -X POST http://localhost:5678/webhook/jd-scraper \
  -H "Content-Type: application/json" \
  -d '{"url": "https://jobs.lever.co/example/position"}'

# Test resume parser
curl -X POST http://localhost:5678/webhook/resume-parser \
  -H "Content-Type: application/json" \
  -d '{"resume_text": "John Doe\njohn@example.com\n\nExperience:\nSoftware Engineer at Acme Corp..."}'

# Full pipeline
curl -X POST http://localhost:5678/webhook/resume-gen \
  -F "resume=@/path/to/your/resume.pdf" \
  -F "jd_url=https://jobs.greenhouse.io/company/position"
```

---

## Troubleshooting

**n8n not starting:** check `docker compose logs n8n`

**Workflow import fails:** ensure n8n is fully started (`curl http://localhost:5678/healthz`), then retry the import script.

**Gemini returns invalid JSON:** the Code node in each workflow has a fallback parser. Check n8n execution logs for the raw Gemini response.

**LaTeX compile error:** the `.tex` source is always returned even on compile failure. Download it and open in Overleaf to see the error.

**PDF is null:** LaTeX compilation failed. Common causes: special characters in resume text not escaped (the Code node handles most cases), or ytotech API down (check [status](https://latex.ytotech.com)).
