"use client";

import { useState, useEffect } from "react";
import { apiGet, navigate, apiDelete, type CustomBook } from "@/lib/customApi";

const subjectLabels: Record<string, string> = {
  math: "数学", chinese: "语文", english: "英语", science: "科学",
};

export function CustomHome() {
  const [books, setBooks] = useState<CustomBook[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => { load(); }, []);

  async function load() {
    try {
      const data = await apiGet<{ books: CustomBook[] }>("books");
      setBooks(data.books || []);
    } catch (e: any) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }

  async function handleDelete(id: string, title: string) {
    if (!confirm(`确定删除「${title}」？所有题目将一并删除。`)) return;
    try {
      await apiDelete(`books/${id}`);
      setBooks(books.filter(b => b.id !== id));
    } catch (e: any) {
      alert("删除失败: " + e.message);
    }
  }

  return (
    <div className="min-h-screen bg-bg p-4 md:p-6">
      <div className="mx-auto max-w-2xl">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-2xl font-bold text-text">自定义学习</h1>
            <p className="text-sm text-text-muted mt-1">拍照或文件夹上传教材，AI 自动生成题目</p>
          </div>
          <a href="/" className="text-sm text-text-muted hover:text-text">← 返回首页</a>
        </div>

        <div className="grid grid-cols-2 gap-3 mb-6">
          <button
            onClick={() => navigate("/custom/create/")}
            className="flex flex-col items-center gap-2 rounded-2xl border-2 border-dashed border-violet-400/40 bg-violet-500/10 px-4 py-6 text-violet-300 hover:bg-violet-500/20 transition-colors"
          >
            <span className="text-2xl">📷</span>
            <span className="font-bold text-sm">拍照上传</span>
          </button>
          <button
            onClick={() => navigate("/custom/folder-create/")}
            className="flex flex-col items-center gap-2 rounded-2xl border-2 border-dashed border-emerald-400/40 bg-emerald-500/10 px-4 py-6 text-emerald-300 hover:bg-emerald-500/20 transition-colors"
          >
            <span className="text-2xl">📁</span>
            <span className="font-bold text-sm">从文件夹创建</span>
          </button>
        </div>

        {loading && (
          <div className="flex items-center justify-center py-12">
            <div className="animate-spin rounded-full h-8 w-8 border-4 border-violet-500 border-t-transparent" />
          </div>
        )}

        {error && (
          <div className="rounded-xl bg-red-500/10 border border-red-500/30 p-4 text-red-400 text-sm">
            {error}
          </div>
        )}

        {!loading && !error && books.length === 0 && (
          <div className="text-center py-12 text-text-muted">
            <p className="text-4xl mb-3">📚</p>
            <p>还没有自定义教材</p>
            <p className="text-sm mt-1">点击上方按钮创建第一本</p>
          </div>
        )}

        <div className="space-y-3">
          {books.map(book => (
            <div
              key={book.id}
              className="group flex items-center gap-3 rounded-2xl bg-bg-soft p-4 hover:bg-bg-soft/80 transition-colors cursor-pointer"
              onClick={() => navigate(`/custom/book/${book.id}/`)}
            >
              <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-violet-500/20 text-violet-300 text-xl">
                📖
              </div>
              <div className="flex-1 min-w-0">
                <h3 className="font-bold text-text truncate">{book.title}</h3>
                <p className="text-sm text-text-muted">
                  {subjectLabels[book.subject] || book.subject} · {book.grade}年级{book.semester === "up" ? "上" : "下"}册
                </p>
              </div>
              <button
                onClick={(e) => { e.stopPropagation(); handleDelete(book.id, book.title); }}
                className="opacity-0 group-hover:opacity-100 text-text-muted hover:text-red-400 text-sm px-2 py-1 transition-opacity"
              >
                删除
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
