# AI Mission Assistant

An enterprise-grade AI knowledge assistant built to demonstrate production-style
full-stack AI engineering: RAG, embeddings, agent tool calling, workflow orchestration,
and modern web architecture.

## What It Does

Upload internal PDF documents and ask questions in natural language:

> "What is the vacation policy?"
> "Summarize the onboarding SOP."
> "Email me a summary of the travel reimbursement policy."
> "What is 18% of 4,750?"

The AI agent decides which tools to use, retrieves relevant document context,
generates grounded answers with citations, and can trigger real workflows (email via n8n).

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Next.js 14, React, Tailwind CSS, TypeScript |
| Backend | NestJS, TypeScript, REST API |
| Database | PostgreSQL 16 + pgvector |
| ORM | Prisma |
| AI / LLM | OpenAI GPT-4o (abstracted — swappable) |
| Embeddings | OpenAI text-embedding-3-small |
| Vector Search | pgvector cosine similarity |
| Auth | JWT + bcrypt |
| Workflow | n8n (email via Gmail OAuth) |
| Infrastructure | Docker Compose |

## Architecture

```
┌─────────────────────────────┐
│     Next.js Frontend        │  :3000
└────────────┬────────────────┘
             │ REST
┌────────────▼────────────────┐
│     NestJS API              │  :3001
│  ┌──────────────────────┐   │
│  │  Agent Orchestrator  │   │
│  └──────┬───────────────┘   │
│         │ tool calls        │
│  ┌──────▼───────────────┐   │
│  │    Tool Registry     │   │
│  │  search_documents    │   │
│  │  calculator          │   │
│  │  current_time        │   │
│  │  send_email ─────────┼───┼──► n8n :5678 ──► Gmail
│  └──────────────────────┘   │
└────────────────────────────┬┘
                             │
              ┌──────────────▼──────────────┐
              │  PostgreSQL + pgvector       │  :5432
              │  users, documents, chunks,   │
              │  embeddings, conversations   │
              └─────────────────────────────┘
```

## Quick Start

### Prerequisites

- Node.js 18+
- Docker Desktop
- OpenAI API key

### 1. Clone and install

```bash
git clone <repo-url>
cd ai-mission-assistant
npm install
```

### 2. Configure environment

```bash
cp .env.example apps/api/.env
# Edit apps/api/.env:
#   LLM_API_KEY=sk-...
#   JWT_SECRET=your-random-secret
```

### 3. Start infrastructure

```bash
docker compose up -d
```

### 4. Run database migrations

```bash
npm run db:migrate
```

### 5. Start the apps

```bash
# Terminal 1
npm run dev:api

# Terminal 2
npm run dev:web
```

Open http://localhost:3000

## Example Prompts

- "What does the employee handbook say about remote work?"
- "Summarize the Q3 safety procedures document."
- "What is the process for submitting a travel reimbursement?"
- "Email me a summary of the onboarding guide."
- "Calculate 18% of 4,750."
- "What time is it in New York?"

## Project Structure

```
ai-mission-assistant/
├── apps/
│   ├── api/          NestJS backend
│   └── web/          Next.js frontend
├── packages/
│   └── shared/       Shared TypeScript types
├── docs/             Documentation
├── storage/uploads/  PDF storage (local, gitignored)
├── docker-compose.yml
├── .env.example
└── CLAUDE.md         Project context for AI assistance
```

## Documentation

- [Architecture](docs/architecture.md)
- [Setup Guide](docs/setup.md)
- [API Reference](docs/api.md)
- [n8n Configuration](docs/n8n.md)

## Future Improvements

- Streaming chat responses
- Hybrid keyword + vector search (BM25 + cosine)
- Reranking layer (Cohere Rerank)
- Page-level PDF citations
- Cloud deployment (Railway / Render / Fly.io)
- Terraform infrastructure
- OpenTelemetry observability
- RAG evaluation metrics
