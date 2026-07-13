# n8n Email Workflow Setup

## Overview

The email tool routes through n8n rather than sending directly from NestJS.
This demonstrates workflow orchestration and keeps email credentials out of the API.

Flow:
```
NestJS send_email tool
  → POST http://localhost:5678/webhook/send-email
  → n8n Webhook node
  → Gmail node
  → Email delivered
```

## Step 1: Access n8n

After running `docker compose up -d`:

Open http://localhost:5678

Create an account on first visit (local account, not cloud).

## Step 2: Create the Workflow

1. Click **New Workflow**
2. Name it: `AI Mission Assistant — Send Email`

## Step 3: Add Webhook Trigger

1. Click **+** to add a node
2. Search for **Webhook**
3. Configure:
   - **HTTP Method:** POST
   - **Path:** `send-email`
   - **Response Mode:** Immediately
   - **Response Data:** First Entry JSON

The webhook URL will be:
```
http://localhost:5678/webhook/send-email
```

## Step 4: Add Gmail Node

1. Click **+** after the Webhook node
2. Search for **Gmail**
3. Select **Send Email**
4. Click **Create New Credential** → follow Google OAuth flow
5. Authorize with your Gmail account (`pranavst2@gmail.com`)

## Step 5: Map the Fields

In the Gmail node, map from the webhook body:

| Gmail Field | Expression |
|---|---|
| To | `{{ $json.to }}` |
| Subject | `{{ $json.subject }}` |
| Message | `{{ $json.body }}` |
| Message Type | HTML or Text |

## Step 6: Activate the Workflow

Toggle the workflow to **Active** (top right).

## Step 7: Update Environment Variable

In `apps/api/.env`:

```env
N8N_WEBHOOK_URL="http://localhost:5678/webhook/send-email"
```

Restart the API after updating.

## Step 8: Test

The AI agent will automatically use this when a user asks to send an email.

You can also test manually:

```bash
curl -X POST http://localhost:5678/webhook/send-email \
  -H "Content-Type: application/json" \
  -d '{"to":"pranavst2@gmail.com","subject":"Test","body":"Hello from n8n!"}'
```

## Workflow JSON Export

Export your n8n workflow to `docs/n8n-workflow.json` for version control:

1. Open the workflow
2. Click **...** (three dots) → **Export**
3. Save to `docs/n8n-workflow.json`

## Important Notes

- Gmail OAuth tokens are stored inside the n8n Docker volume (`n8n_data`)
- They are **not** in the repository
- The n8n volume persists between `docker compose down` and `docker compose up`
- To reset: `docker compose down -v` (destroys all volumes including tokens)
