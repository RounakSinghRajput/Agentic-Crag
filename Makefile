.PHONY: install run build up down logs pull-models
install:
	pip install -e ".[dev]"
run:
	uvicorn agentic_crag.api:app --reload --port 8000
build:
	docker compose build
up:
	docker compose up -d
down:
	docker compose down
logs:
	docker compose logs -f api
pull-models:
	ollama pull llama3.2 && ollama pull nomic-embed-text
