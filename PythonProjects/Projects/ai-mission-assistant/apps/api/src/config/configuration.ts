export default () => ({
  port: parseInt(process.env.PORT ?? '3001', 10),
  nodeEnv: process.env.NODE_ENV ?? 'development',
  appUrl: process.env.APP_URL ?? 'http://localhost:3000',

  database: {
    url: process.env.DATABASE_URL,
  },

  jwt: {
    secret: process.env.JWT_SECRET ?? 'fallback-secret',
    expiresIn: process.env.JWT_EXPIRES_IN ?? '7d',
  },

  llm: {
    provider: process.env.LLM_PROVIDER ?? 'openai',
    apiKey: process.env.LLM_API_KEY ?? '',
    model: process.env.LLM_MODEL ?? 'gpt-4o',
  },

  embedding: {
    provider: process.env.EMBEDDING_PROVIDER ?? 'openai',
    model: process.env.EMBEDDING_MODEL ?? 'text-embedding-3-small',
    dimensions: parseInt(process.env.EMBEDDING_DIMENSIONS ?? '1536', 10),
  },

  n8n: {
    webhookUrl: process.env.N8N_WEBHOOK_URL ?? 'http://localhost:5678/webhook/send-email',
  },

  upload: {
    maxFileSizeMb: parseInt(process.env.MAX_FILE_SIZE_MB ?? '20', 10),
    uploadDir: process.env.UPLOAD_DIR ?? './storage/uploads',
  },
});
