'use client';

import { useState, useCallback } from 'react';
import { Upload, FileText, Trash2, CheckCircle, Clock, AlertCircle, Loader2 } from 'lucide-react';
import { Document } from '@/types';
import { documentsApi } from '@/lib/api';

interface Props {
  documents: Document[];
  onRefresh: () => void;
}

const statusIcon = {
  UPLOADED: <Clock size={14} className="text-yellow-400" />,
  PROCESSING: <Loader2 size={14} className="text-blue-400 animate-spin" />,
  INDEXED: <CheckCircle size={14} className="text-green-400" />,
  FAILED: <AlertCircle size={14} className="text-red-400" />,
};

const statusLabel = {
  UPLOADED: 'Queued',
  PROCESSING: 'Processing…',
  INDEXED: 'Ready',
  FAILED: 'Failed',
};

function formatBytes(bytes: number) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function DocumentList({ documents, onRefresh }: Props) {
  const [uploading, setUploading] = useState(false);
  const [dragOver, setDragOver] = useState(false);

  const handleUpload = useCallback(
    async (file: File) => {
      if (!file.type.includes('pdf')) {
        alert('Only PDF files are supported.');
        return;
      }
      setUploading(true);
      try {
        await documentsApi.upload(file);
        onRefresh();
      } catch {
        alert('Upload failed. Please try again.');
      } finally {
        setUploading(false);
      }
    },
    [onRefresh],
  );

  const handleFileInput = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) handleUpload(file);
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setDragOver(false);
    const file = e.dataTransfer.files?.[0];
    if (file) handleUpload(file);
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Delete this document and all its data?')) return;
    await documentsApi.remove(id);
    onRefresh();
  };

  return (
    <div className="flex flex-col h-full">
      {/* Upload area */}
      <div
        onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
        onDragLeave={() => setDragOver(false)}
        onDrop={handleDrop}
        className={`relative border-2 border-dashed rounded-xl p-5 text-center transition-colors ${
          dragOver ? 'border-blue-500 bg-blue-900/20' : 'border-gray-700 hover:border-gray-600'
        }`}
      >
        <Upload size={20} className="mx-auto mb-2 text-gray-400" />
        <p className="text-xs text-gray-400">
          Drag a PDF here or{' '}
          <label className="cursor-pointer text-blue-400 hover:text-blue-300">
            browse
            <input type="file" accept=".pdf" className="hidden" onChange={handleFileInput} />
          </label>
        </p>
        {uploading && (
          <div className="absolute inset-0 bg-gray-900/70 flex items-center justify-center rounded-xl">
            <Loader2 size={20} className="animate-spin text-blue-400" />
          </div>
        )}
      </div>

      {/* Document list */}
      <div className="mt-3 flex-1 overflow-y-auto space-y-2">
        {documents.length === 0 && (
          <p className="text-xs text-gray-500 text-center py-4">No documents uploaded yet</p>
        )}
        {documents.map((doc) => (
          <div
            key={doc.id}
            className="flex items-start gap-2 p-2 rounded-lg bg-gray-800/50 hover:bg-gray-800 group"
          >
            <FileText size={16} className="mt-0.5 flex-shrink-0 text-gray-400" />
            <div className="flex-1 min-w-0">
              <p className="text-xs font-medium text-gray-200 truncate">{doc.originalName}</p>
              <div className="flex items-center gap-1 mt-0.5">
                {statusIcon[doc.status]}
                <span className="text-xs text-gray-500">
                  {statusLabel[doc.status]} · {formatBytes(doc.fileSize)}
                </span>
              </div>
              {doc.status === 'FAILED' && doc.errorMessage && (
                <p className="text-xs text-red-400 mt-0.5 truncate">{doc.errorMessage}</p>
              )}
            </div>
            <button
              onClick={() => handleDelete(doc.id)}
              className="opacity-0 group-hover:opacity-100 p-1 text-gray-500 hover:text-red-400 transition"
            >
              <Trash2 size={13} />
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}
