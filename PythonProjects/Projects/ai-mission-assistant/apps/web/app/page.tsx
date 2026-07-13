'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { Send, Plus, LogOut, MessageSquare, ChevronRight } from 'lucide-react';
import { useAuth } from '@/lib/auth';
import { chatApi, documentsApi } from '@/lib/api';
import { Conversation, Message, Document, ChatResponse } from '@/types';
import { MessageBubble } from '@/components/chat/MessageBubble';
import { DocumentList } from '@/components/documents/DocumentList';

interface MessageWithTools extends Message {
  toolsUsed?: string[];
}

export default function HomePage() {
  const { user, logout, isLoading } = useAuth();
  const router = useRouter();

  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [activeConvId, setActiveConvId] = useState<string | null>(null);
  const [messages, setMessages] = useState<MessageWithTools[]>([]);
  const [documents, setDocuments] = useState<Document[]>([]);
  const [input, setInput] = useState('');
  const [sending, setSending] = useState(false);
  const [sidebarTab, setSidebarTab] = useState<'chats' | 'docs'>('chats');

  const messagesEndRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = () => messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });

  const loadConversations = useCallback(async () => {
    try {
      const res = await chatApi.listConversations();
      setConversations(res.data);
    } catch {}
  }, []);

  const loadDocuments = useCallback(async () => {
    try {
      const res = await documentsApi.list();
      setDocuments(res.data);
    } catch {}
  }, []);

  useEffect(() => {
    if (!isLoading && !user) router.replace('/login');
  }, [isLoading, user, router]);

  useEffect(() => {
    if (user) {
      loadConversations();
      loadDocuments();
    }
  }, [user, loadConversations, loadDocuments]);

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  const openConversation = async (id: string) => {
    setActiveConvId(id);
    try {
      const res = await chatApi.getConversation(id);
      setMessages(res.data.messages ?? []);
    } catch {}
  };

  const newConversation = () => {
    setActiveConvId(null);
    setMessages([]);
  };

  const sendMessage = async () => {
    if (!input.trim() || sending) return;

    const content = input.trim();
    setInput('');
    setSending(true);

    const tempUserMsg: MessageWithTools = {
      id: `temp-${Date.now()}`,
      conversationId: activeConvId ?? '',
      role: 'user',
      content,
      createdAt: new Date().toISOString(),
    };
    setMessages((prev) => [...prev, tempUserMsg]);

    try {
      const res = await chatApi.sendMessage(content, activeConvId ?? undefined);
      const data: ChatResponse = res.data;

      if (!activeConvId) {
        setActiveConvId(data.conversationId);
        loadConversations();
      }

      setMessages((prev) => [
        ...prev.filter((m) => m.id !== tempUserMsg.id),
        { ...tempUserMsg, id: `user-${Date.now()}`, conversationId: data.conversationId },
        { ...data.message, toolsUsed: data.toolsUsed },
      ]);
    } catch {
      setMessages((prev) =>
        prev.filter((m) => m.id !== tempUserMsg.id).concat({
          id: `err-${Date.now()}`,
          conversationId: activeConvId ?? '',
          role: 'assistant',
          content: 'Something went wrong. Please try again.',
          createdAt: new Date().toISOString(),
        }),
      );
    } finally {
      setSending(false);
    }
  };

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="w-6 h-6 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="flex h-screen bg-gray-950">
      {/* Sidebar */}
      <div className="w-64 flex-shrink-0 border-r border-gray-800 flex flex-col bg-gray-900">
        <div className="p-4 border-b border-gray-800">
          <h1 className="text-sm font-semibold text-white truncate">AI Mission Assistant</h1>
          <p className="text-xs text-gray-500 truncate mt-0.5">{user?.email}</p>
        </div>

        <div className="flex border-b border-gray-800">
          {(['chats', 'docs'] as const).map((tab) => (
            <button
              key={tab}
              onClick={() => setSidebarTab(tab)}
              className={`flex-1 py-2 text-xs font-medium capitalize transition-colors ${
                sidebarTab === tab
                  ? 'text-blue-400 border-b-2 border-blue-400'
                  : 'text-gray-500 hover:text-gray-300'
              }`}
            >
              {tab}
            </button>
          ))}
        </div>

        <div className="flex-1 overflow-hidden p-3">
          {sidebarTab === 'chats' ? (
            <div className="flex flex-col h-full gap-2">
              <button
                onClick={newConversation}
                className="flex items-center gap-2 w-full px-3 py-2 rounded-lg bg-blue-600/20 hover:bg-blue-600/30 text-blue-400 text-xs font-medium transition-colors"
              >
                <Plus size={14} />
                New conversation
              </button>
              <div className="flex-1 overflow-y-auto space-y-1">
                {conversations.map((c) => (
                  <button
                    key={c.id}
                    onClick={() => openConversation(c.id)}
                    className={`w-full flex items-center gap-2 px-3 py-2 rounded-lg text-left text-xs transition-colors ${
                      activeConvId === c.id
                        ? 'bg-gray-800 text-white'
                        : 'text-gray-400 hover:bg-gray-800/50 hover:text-gray-200'
                    }`}
                  >
                    <MessageSquare size={13} className="flex-shrink-0" />
                    <span className="truncate">{c.title}</span>
                    <ChevronRight size={12} className="ml-auto flex-shrink-0 opacity-50" />
                  </button>
                ))}
              </div>
            </div>
          ) : (
            <DocumentList documents={documents} onRefresh={loadDocuments} />
          )}
        </div>

        <button
          onClick={() => { logout(); router.push('/login'); }}
          className="flex items-center gap-2 p-4 text-xs text-gray-500 hover:text-gray-300 transition-colors border-t border-gray-800"
        >
          <LogOut size={14} />
          Sign out
        </button>
      </div>

      {/* Chat area */}
      <div className="flex-1 flex flex-col min-w-0">
        <div className="flex-1 overflow-y-auto px-6 py-6 space-y-6">
          {messages.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-full text-center">
              <div className="w-12 h-12 rounded-full bg-blue-600/20 flex items-center justify-center mb-4">
                <MessageSquare size={24} className="text-blue-400" />
              </div>
              <h2 className="text-lg font-semibold text-gray-200">Ask anything</h2>
              <p className="mt-1 text-sm text-gray-500 max-w-sm">
                Upload documents in the sidebar, then ask questions about their content.
              </p>
              <div className="mt-6 grid grid-cols-1 gap-2 w-full max-w-sm">
                {[
                  'What is the vacation policy?',
                  'Summarize the onboarding guide.',
                  'What is 18% of 4,750?',
                  'What time is it in New York?',
                ].map((prompt) => (
                  <button
                    key={prompt}
                    onClick={() => setInput(prompt)}
                    className="px-3 py-2 rounded-lg border border-gray-700 text-xs text-gray-400 hover:border-gray-600 hover:text-gray-200 text-left transition-colors"
                  >
                    {prompt}
                  </button>
                ))}
              </div>
            </div>
          ) : (
            messages.map((msg) => (
              <MessageBubble key={msg.id} message={msg} toolsUsed={msg.toolsUsed} />
            ))
          )}

          {sending && (
            <div className="flex gap-3 items-start">
              <div className="w-8 h-8 rounded-full bg-blue-600 flex items-center justify-center flex-shrink-0">
                <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
              </div>
              <div className="bg-gray-800 rounded-2xl rounded-tl-sm px-4 py-3">
                <div className="flex gap-1">
                  <span className="w-1.5 h-1.5 bg-gray-500 rounded-full animate-bounce [animation-delay:0ms]" />
                  <span className="w-1.5 h-1.5 bg-gray-500 rounded-full animate-bounce [animation-delay:150ms]" />
                  <span className="w-1.5 h-1.5 bg-gray-500 rounded-full animate-bounce [animation-delay:300ms]" />
                </div>
              </div>
            </div>
          )}
          <div ref={messagesEndRef} />
        </div>

        <div className="border-t border-gray-800 p-4">
          <div className="flex gap-3 items-end max-w-4xl mx-auto">
            <textarea
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                  e.preventDefault();
                  sendMessage();
                }
              }}
              placeholder="Ask a question, request a summary, send an email…"
              rows={1}
              className="flex-1 resize-none rounded-xl bg-gray-800 border border-gray-700 px-4 py-3 text-sm text-white placeholder-gray-500 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500 max-h-32 overflow-y-auto"
              style={{ minHeight: '44px' }}
            />
            <button
              onClick={sendMessage}
              disabled={!input.trim() || sending}
              className="flex-shrink-0 w-10 h-10 rounded-xl bg-blue-600 flex items-center justify-center text-white hover:bg-blue-500 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
            >
              <Send size={16} />
            </button>
          </div>
          <p className="mt-2 text-center text-xs text-gray-600">
            AI responses may be inaccurate. Verify important information independently.
          </p>
        </div>
      </div>
    </div>
  );
}
