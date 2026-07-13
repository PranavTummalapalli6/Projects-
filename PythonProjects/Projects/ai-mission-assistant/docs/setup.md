# Setup Guide

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Node.js | 18+ | https://nodejs.org |
| Docker Desktop | Latest | https://docker.com/products/docker-desktop |
| Git | Any | https://git-scm.com |
| OpenAI API key | — | https://platform.openai.com |

## Step-by-Step Setup

### 1. Install dependencies

```bash
cd ai-mission-assistant
npm install
```

### 2. Configure environment variables

```bash
cp .env.example apps/api/.env
```

Edit `apps/api/.env`:

```env
DATABASE_URL="postgresql://postgres:postgres@localhost:5432/ai_mission_assistant?schema=public"
JWT_SECRET="replace-with-a-long-random-string"
LLM_API_KEY="sk-your-openai-key"
LLM_MODEL="gpt-4o"
EMBEDDING_MODEL="text-embedding-3-small"
N8N_WEBHOOK_URL="http://localhost:5678/webhook/send-email"
```

### 3. Start infrastructure

Docker Desktop must be running.

```bash
docker compose up -d
```

Verify:
```bash
docker compose ps
# Both postgres and n8n should show "healthy" or "running"
```

### 4. Run database migrations

```bash
npm run db:migrate
```

This creates all tables including the pgvector extension.

### 5. Start the API

```bash
npm run dev:api
# Starts NestJS on http://localhost:3001
```

Test: http://localhost:3001/health → should return `{"status":"ok"}`

### 6. Start the frontend

```bash
npm run dev:web
# Starts Next.js on http://localhost:3000
```

Open http://localhost:3000

## n8n Setup (Email Tool)

See [docs/n8n.md](n8n.md) for full Gmail configuration instructions.

Quick summary:
1. Open http://localhost:5678
2. Create a new workflow
3. Add Webhook trigger node (POST, path: `send-email`)
4. Add Gmail node (connect your Google account)
5. Map `to`, `subject`, `body` fields from webhook body
6. Activate the workflow
7. Copy the webhook URL to `N8N_WEBHOOK_URL` in your `.env`

## Troubleshooting

**Database connection refused:**
- Ensure Docker Desktop is running
- Run `docker compose up -d`
- Wait ~15 seconds for PostgreSQL to initialize

**pgvector extension error:**
- The `pgvector/pgvector:pg16` image includes pgvector pre-installed
- The Prisma migration enables it via `CREATE EXTENSION IF NOT EXISTS vector`

**LLM API errors:**
- Verify `LLM_API_KEY` is set correctly in `apps/api/.env`
- Check OpenAI account has available credits

**Email not sending:**
- Verify n8n is running: http://localhost:5678
- Ensure Gmail OAuth is configured in n8n
- Check n8n workflow is activated
