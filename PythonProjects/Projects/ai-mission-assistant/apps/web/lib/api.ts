import axios from 'axios';

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:3001';

export const api = axios.create({
  baseURL: API_URL,
  headers: { 'Content-Type': 'application/json' },
});

// Attach JWT to every request
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

// Redirect to login on 401
api.interceptors.response.use(
  (res) => res,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('token');
      localStorage.removeItem('user');
      window.location.href = '/login';
    }
    return Promise.reject(error);
  },
);

// ─── Auth ────────────────────────────────────────────────────────────────────
export const authApi = {
  register: (email: string, password: string) =>
    api.post('/auth/register', { email, password }),
  login: (email: string, password: string) =>
    api.post('/auth/login', { email, password }),
  me: () => api.get('/auth/me'),
};

// ─── Documents ───────────────────────────────────────────────────────────────
export const documentsApi = {
  upload: (file: File) => {
    const form = new FormData();
    form.append('file', file);
    return api.post('/documents/upload', form, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  },
  list: () => api.get('/documents'),
  remove: (id: string) => api.delete(`/documents/${id}`),
};

// ─── Chat ────────────────────────────────────────────────────────────────────
export const chatApi = {
  listConversations: () => api.get('/conversations'),
  getConversation: (id: string) => api.get(`/conversations/${id}`),
  createConversation: (title?: string) => api.post('/conversations', { title }),
  deleteConversation: (id: string) => api.delete(`/conversations/${id}`),
  sendMessage: (content: string, conversationId?: string) =>
    api.post('/chat', { content, conversationId }),
};
