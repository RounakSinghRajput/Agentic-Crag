# Agentic Self-Corrective RAG (Adaptive CRAG)

A stateful LangGraph pipeline that retrieves from a persistent ChromaDB store,
grades each chunk for relevance, falls back to Tavily web search when context is
insufficient, and audits every answer for hallucinations before returning it.

> **Status:** project scaffold. Module files contain docstring stubs; they are
> implemented sequentially (see "Implementation roadmap").

## Graph topology

```
START -> retrieve -> grade_documents --(all relevant)--------> generate
                          |                                       |
                          +--(insufficient)--> transform_query    v
                                                    |      hallucination_grader
                                                    v        |            |
                                               web_search    | grounded   | not grounded
                                                    |        v            | (retry < 2)
                                                    +----> generate <-----+
                                                             (grounded -> END)
```

Note: the hallucination retry loop makes this a cyclic graph, not a strict DAG.
Termination is guaranteed by `retry_count` (max 2).

## Requirements

- macOS (Apple Silicon supported), Python 3.11+
- [Ollama](https://ollama.com) if using local models
- A Tavily API key (https://tavily.com) for web fallback
- Optional: Anthropic API key

## Setup

```bash
# 1. Create environment
python3.11 -m venv .venv
source .venv/bin/activate

# 2. Install
pip install --upgrade pip
pip install -e ".[dev]"        # or: pip install -r requirements.txt

# 3. Configure
cp .env.example .env
# edit .env: add TAVILY_API_KEY (and ANTHROPIC_API_KEY if LLM_PROVIDER=anthropic)

# 4. Local models (if using Ollama)
ollama pull llama3.2
ollama pull nomic-embed-text   # only if EMBEDDING_PROVIDER=ollama
ollama serve                   # skip if the Ollama app is already running
```

On Apple Silicon, `sentence-transformers` uses the MPS backend automatically
through PyTorch. The first run downloads `BAAI/bge-small-en-v1.5` (~130 MB).

## Usage (available once implemented)

```bash
crag ingest ./data/raw            # chunk + embed documents into ChromaDB
crag ask "What does the report say about Q3 churn?"
```

## Project layout

```
src/agentic_crag/
  config.py        Settings (pydantic-settings, reads .env)
  state.py         GraphState TypedDict
  schemas.py       Pydantic v2 grader outputs (binary yes/no)
  prompts.py       Prompt templates
  llm.py           LLM factory (Ollama / Anthropic)
  embeddings.py    Embedding factory (HF / Ollama)
  vectorstore.py   Persistent Chroma access
  ingestion.py     Load, split, embed, persist
  nodes/           One module per graph node + routing
  graph.py         StateGraph assembly and compile()
  cli.py           Command-line entry point
  api.py           FastAPI service (/health, /ingest, /ask)
tests/             Unit tests with mocked LLM / Tavily
```

## Implementation roadmap

1. config.py, state.py, schemas.py
2. llm.py, embeddings.py, vectorstore.py, ingestion.py
3. prompts.py
4. nodes/* (retrieve, grade_documents, transform_query, web_search, generate, hallucination_grader, routing)
5. graph.py, cli.py
6. tests

## Notes

- Model IDs are configurable in `.env`; `claude-3-5-sonnet-latest` has been
  retired by Anthropic, so the default is a current Sonnet model.
- Structured grader output uses `llm.with_structured_output(PydanticModel)`.
  Small local models can be flaky at this; `mistral` or `llama3.2` at
  temperature 0 works best.

## Deployment

### Option A: Docker Compose (recommended)

```bash
cp .env.example .env            # set TAVILY_API_KEY, provider settings
ollama serve                    # on the macOS host, if LLM_PROVIDER=ollama
docker compose up -d --build
curl http://localhost:8000/health
```

- The API runs on port 8000 as a non-root user; a healthcheck hits `/health`.
- ChromaDB persists in the `chroma_data` named volume, so it survives restarts.
- The embedding model is baked into the image at build time.
- On macOS, Docker cannot use the Apple GPU. Keep Ollama on the host and let
  the container reach it via `host.docker.internal` (the default in compose).
- On a Linux/GPU server, run Ollama in a container instead:
  `docker compose --profile ollama up -d`, and set
  `OLLAMA_BASE_URL=http://ollama:11434` in `.env`.

### Option B: Anthropic backend (no local GPU needed)

Set `LLM_PROVIDER=anthropic` and `ANTHROPIC_API_KEY` in `.env`. The
container then needs no Ollama at all (use `EMBEDDING_PROVIDER=huggingface`).

### Production checklist

- Inject secrets via your platform's secret manager, not a baked `.env`.
- Put the API behind a reverse proxy / API gateway with auth and rate limits.
- Mount `chroma_data` on durable storage and back it up.
- Build multi-arch images if deploying to ARM and x86:
  `docker buildx build --platform linux/amd64,linux/arm64 -t agentic-crag .`
- Ingest documents via `POST /ingest` or `crag ingest` inside the container.
