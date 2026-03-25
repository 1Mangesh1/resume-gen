.DEFAULT_GOAL := help
.PHONY: help build up down restart logs logs-latex status import open clean

# ── Config ───────────────────────────────────────────────────────
N8N_URL   := http://localhost:5678
UI_URL    := http://localhost:3000

# ── Help ─────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  RESUME.GEN — AI Resume Generator"
	@echo ""
	@echo "  make setup       Copy .env.example → .env (first time only)"
	@echo "  make build       Build the local LaTeX service image"
	@echo "  make up          Build (if needed) and start all services"
	@echo "  make down        Stop all services"
	@echo "  make restart     Restart all services"
	@echo "  make import      Import all n8n workflows"
	@echo "  make logs        Tail n8n logs"
	@echo "  make logs-latex  Tail latex service logs"
	@echo "  make status      Show running containers"
	@echo "  make open        Open n8n and UI in browser"
	@echo "  make clean       Stop and remove volumes (destructive)"
	@echo ""

# ── Setup ────────────────────────────────────────────────────────
setup:
	@if [ -f .env ]; then \
		echo "⚠  .env already exists — skipping"; \
	else \
		cp .env.example .env; \
		echo "✓  .env created — fill in your API keys before running 'make up'"; \
	fi

# ── Services ─────────────────────────────────────────────────────
build:
	docker compose build latex

up:
	@[ -f .env ] || (echo "✗  .env not found — run 'make setup' first" && exit 1)
	docker compose up -d --build
	@echo ""
	@echo "  n8n  → $(N8N_URL)"
	@echo "  UI   → $(UI_URL)"
	@echo ""
	@echo "  Next: run 'make import' once n8n is ready"

down:
	docker compose down

restart:
	docker compose restart

logs:
	docker compose logs -f n8n

logs-latex:
	docker compose logs -f latex

status:
	docker compose ps

# ── Workflows ────────────────────────────────────────────────────
import:
	@./scripts/import-workflows.sh

# ── Browser ──────────────────────────────────────────────────────
open:
	@open $(N8N_URL) 2>/dev/null || xdg-open $(N8N_URL) 2>/dev/null || echo "Open $(N8N_URL)"
	@open $(UI_URL)  2>/dev/null || xdg-open $(UI_URL)  2>/dev/null || echo "Open $(UI_URL)"

# ── Cleanup ──────────────────────────────────────────────────────
clean:
	@echo "⚠  This will delete all n8n data (workflows, credentials, executions)."
	@printf "   Continue? [y/N] " && read ans && [ "$$ans" = "y" ] || exit 0
	docker compose down -v
	@echo "✓  Cleaned"
