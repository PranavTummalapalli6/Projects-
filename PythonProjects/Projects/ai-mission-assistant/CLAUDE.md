# AI Mission Assistant — Claude Context

## Project Purpose

Enterprise AI knowledge assistant built as a portfolio project demonstrating:
Next.js + NestJS + TypeScript + PostgreSQL + pgvector + RAG + embeddings +
agent tool calling + n8n + JWT authentication + logging + Docker.

## Architecture

```
Next.js (port 3000)
    │
    ▼ REST API
NestJS (port 3001)
    │
    ▼
Agent Orchestrator
    │
    ├── Tool: search_documents  ──► pgvector (PostgreSQL)
    ├── Tool: calculator
    ├── Tool: current_time
    └── Tool: send_email  ──► n8n (port 5678) ──► Gmail
    │
    ▼
LLM Provider (OpenAI / Anthropic)
```

## Folder Structure

```
ai-mission-assistant/
├── apps/
│   ├── api/          NestJS backend (port 3001)
│   └── web/          Next.js frontend (port 3000)
├── packages/
│   └── shared/       Shared TypeScript types
├── docs/             Architecture and setup docs
├── storage/
│   └── uploads/      Uploaded PDFs (gitignored)
├── docker/           Docker helper configs
├── .env.example      Environment variable template
├── docker-compose.yml PostgreSQL + n8n
├── README.md
└── CLAUDE.md         (this file)
```

## Technology Decisions

| Concern | Choice | Reason |
|---|---|---|
| Monorepo | npm workspaces | Zero extra tooling, npm native |
| Backend | NestJS | Modular, DI, TypeScript-first, interview-relevant |
| Frontend | Next.js + Tailwind | Industry standard, App Router |
| ORM | Prisma | Great DX, pgvector support, type-safe |
| Vector DB | pgvector in PostgreSQL | No extra service, good enough for demo |
| Auth | JWT + bcrypt | Standard, demonstrable |
| Workflow | n8n | Visual orchestration, Gmail via OAuth |
| LLM | OpenAI (abstracted) | Most common, easy tool calling |

## API Modules

```
AuthModule        /auth/register  /auth/login
UsersModule       /users/me
DocumentsModule   /documents (upload, list, delete)
IngestionModule   background processing after upload
ChatModule        /conversations  /conversations/:id/messages
AgentModule       orchestrates tool selection + LLM calls
ToolsModule       search_documents, calculator, current_time, send_email
N8nModule         webhook client for email
LoggingModule     AI request + tool execution logs
```

## Database Schema (Prisma)

User → Documents → DocumentChunks (with pgvector embedding)
User → Conversations → Messages
Conversations → ToolExecutions
User → AIRequestLogs

## Chunking Strategy

- Chunk size: ~800 tokens (~3200 characters)
- Overlap: ~200 tokens (~800 characters)
- Split on paragraph breaks when possible; fall back to character limit
- Each chunk stores: content, chunkIndex, pageNumber (if extractable), metadata JSON

## RAG Pipeline

1. Embed user query (text-embedding-3-small, 1536 dims)
2. pgvector cosine similarity search, top-5 chunks
3. Build context block with chunk content + source metadata
4. System prompt instructs: answer from context, cite sources, acknowledge uncertainty
5. Citations: documentName + chunkIndex

## Agent Tool Calling

Uses OpenAI tool_choice API (or Anthropic tool_use).
Tools defined with JSON Schema — model decides which (if any) to call.
Server executes tool, result fed back for final response.
Multi-step: model can call multiple tools sequentially.

## Important Commands

```bash
# Start infrastructure (requires Docker Desktop)
docker compose up -d

# Run API in dev
npm run dev:api

# Run frontend in dev
npm run dev:web

# Database migrations
npm run db:migrate

# Prisma Studio (DB GUI)
npm run db:studio
```

## Environment Setup

Copy `.env.example` to `apps/api/.env` and fill in:
- `LLM_API_KEY` — OpenAI API key
- `JWT_SECRET` — any long random string
- `DATABASE_URL` — points to Docker postgres (default works if using docker-compose)
- `N8N_WEBHOOK_URL` — set after configuring n8n workflow

## Implementation Status

- [x] Phase 0 — Environment inspection + project scaffold + docs
- [ ] Phase 1 — Monorepo foundation (NestJS + Next.js + DB)
- [ ] Phase 2 — Authentication
- [ ] Phase 3 — Document upload + ingestion
- [ ] Phase 4 — Embeddings + vector search
- [ ] Phase 5 — RAG chat
- [ ] Phase 6 — Agent tools
- [ ] Phase 7 — n8n email
- [ ] Phase 8 — Logging + polish
- [ ] Phase 9 — Docker + final docs

## Known Issues / Blockers

- Docker Desktop not installed — needed before `docker compose up -d`
  Install from: https://www.docker.com/products/docker-desktop/
- LLM API key not configured — needed for Phase 4+

## Naming Conventions

- Files: kebab-case (e.g. `auth.service.ts`)
- Classes: PascalCase
- Variables/functions: camelCase
- Database tables: snake_case (Prisma default)
- Environment variables: SCREAMING_SNAKE_CASE
