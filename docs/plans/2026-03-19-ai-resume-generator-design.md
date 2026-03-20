# AI-Powered Resume Generator — Design Document

**Date:** 2026-03-19
**Status:** Approved

---

## 1. Problem & Goal

Job seekers waste time manually tailoring resumes for each application, with inconsistent ATS optimization. This workflow automates resume tailoring end-to-end: user provides their resume + a job link or JD text, and receives a tailored PDF resume and `.tex` source in under 2 minutes.

---

## 2. Tech Stack

| Concern | Tool |
|---|---|
| Orchestration | n8n (self-hosted, Docker) |
| LLM | Google Gemini 1.5 Pro |
| Primary scraper | Cloudflare Browser Rendering REST API (free: 10 min/day) |
| Fallback scraper | Jina AI Reader (`r.jina.ai/<url>`) — free, no setup |
| LaTeX compilation | latex.ytotech.com REST API |
| LaTeX template | Jake's Resume (ATS-friendly, single-page) |

---

## 3. Architecture: Modular Sub-Workflows

**Docker Compose:** single `n8n` container — no sidecar services needed for MVP.

**Trigger:** Webhook (POST, multipart form) — accepts resume file (PDF/TXT) + JD text or URL.

**Flow:**
```
Webhook
  ├── [parallel] jd-scraper
  └── [parallel] resume-parser
        ↓ (both complete)
  ai-tailoring-engine
        ↓
  latex-generator
        ↓
  output-handler → JSON response (PDF + .tex + ATS report)
```

---

## 4. Sub-Workflow Specs

### 4.1 `jd-scraper`
```
Input:  { url?: string, text?: string }
Output: { jd_raw: string, source: "cloudflare" | "jina" | "manual" }
```
- If `text` provided → pass through directly
- If `url` → try Cloudflare Browser Rendering API (returns Markdown)
- On failure → fallback to `GET https://r.jina.ai/<url>`
- On failure → error node (ask user to paste JD manually)

**Note:** Cloudflare Browser Rendering cannot bypass Cloudflare Turnstile/bot protection. LinkedIn and similar heavily-protected sites will fall through to Jina or manual paste.

---

### 4.2 `resume-parser`
```
Input:  { resume_text: string }   ← PDF extracted via n8n's "Extract from File" node
Output: { skills[], experience[], projects[], education[], contact{} }
```
- PDF → text via n8n built-in binary data / Extract from File node
- Single Gemini call extracts structured JSON
- Strict prompt: "Do not invent any information not present in the source text"

---

### 4.3 `ai-tailoring-engine`
```
Input:  { resume_json, jd_raw }
Output: { tailored_resume_json, matched_keywords[], ats_score: number }
```
- Single Gemini 1.5 Pro call (full resume + JD fit in context window)
- Re-ranks skills by JD relevance
- Rewrites experience bullets: action verbs + JD keywords + metrics
- Re-ranks projects by relevance
- Returns ATS score (0–100, keyword match %) and matched keywords list
- Anti-hallucination instruction: only use facts from input resume

---

### 4.4 `latex-generator`
```
Input:  { tailored_resume_json }
Output: { tex_source: string, pdf_base64: string }
```
- Fills Jake's Resume LaTeX template with dynamic values
- POSTs `.tex` to `latex.ytotech.com` API → receives compiled PDF
- On compile error: returns raw `.tex` so user can open/fix in Overleaf

---

### 4.5 `output-handler`
```
Input:  { pdf_base64, tex_source, ats_score, matched_keywords[] }
Output: JSON response with PDF (base64), .tex source, ATS score, keyword report
```

---

## 5. Data Schema

### Resume JSON (shared across sub-workflows)
```json
{
  "contact": { "name": "", "email": "", "phone": "", "linkedin": "", "github": "" },
  "summary": "",
  "skills": [{ "category": "", "items": [""] }],
  "experience": [{ "company": "", "title": "", "dates": "", "bullets": [""] }],
  "projects": [{ "name": "", "tech": [""], "bullets": [""] }],
  "education": [{ "institution": "", "degree": "", "dates": "", "gpa": "" }]
}
```

---

## 6. Gemini Prompts

### Call 1 — Resume Parser
> Extract the following structured JSON from this resume text. Return only valid JSON, no markdown fences. Schema: [schema]. Do not invent any information not present in the source text.

### Call 2 — AI Tailoring Engine (single call)
> You are a resume optimization expert. Given the candidate's resume JSON and job description below, return a JSON object with:
> 1. `tailored_resume` — same schema as input, with skills re-ranked by JD relevance, experience bullets rewritten using action verbs and JD keywords, projects re-ranked by relevance
> 2. `matched_keywords` — array of JD keywords found in the resume
> 3. `ats_score` — integer 0–100 representing keyword match percentage
>
> CRITICAL: Only use facts from the input resume. Never add skills, companies, or metrics not already present in the candidate's resume.

**Total: 2 Gemini API calls per resume generation.**

---

## 7. Verification Plan

| Step | Test | Pass Criteria |
|---|---|---|
| Scraper | POST public Greenhouse job URL to `jd-scraper` | Clean Markdown JD returned, `source: "cloudflare"` |
| Scraper fallback | POST LinkedIn URL | Falls back to Jina or returns manual-paste error |
| Parser | POST plain-text resume to `resume-parser` | All JSON fields populated, no hallucinated data |
| Tailoring | Feed known resume JSON + JD to `ai-tailoring-engine` | ATS score > 0, no invented skills/companies |
| LaTeX | Send minimal resume JSON to `latex-generator` | PDF returned, no compile errors |
| Full pipeline | POST real PDF resume + job URL to webhook | PDF downloaded, time < 120s |
| Error handling | Bad URL → Jina fails too | Error response asks user to paste JD |
| LaTeX error | Malformed template variable | Raw `.tex` still returned |

---

## 8. MVP Scope (excluded from v1)

- LinkedIn auto-import
- GitHub project enrichment
- Cover letter generation
- Multi-version A/B testing
- Job auto-apply
