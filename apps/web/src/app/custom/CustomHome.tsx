"use client";

import { useState, useEffect } from "react";
import Link from "next/link";
import { apiGet, navigate, apiDelete, type CustomBook } from "@/lib/customApi";
import { ArrowLeft } from "@/components/icons";

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
    <main className="min-h-screen bg-bg-soft pb-20 md:pb-8">
      <header className="sticky top-0 z-30 bg-white border-b border-bg-softer px-4 py-3 md:px-6">
        <div className="flex items-center gap-3 max-w-3xl mx-auto">
          <Link href="/" className="text-ink-softer hover:text-ink transition-colors">
            <ArrowLeft className="w-5 h-5" />
          </Link>
          <h1 className="text-lg font-extrabold text-ink">自定义学习</h1>
          <span className="text-xs text-ink-light ml-auto hidden sm:inline">拍照上传 · AI 出题</span>
        </div>
      </header>

      <div className="max-w-3xl mx-auto px-4 py-6 space-y-6 md:px-6">
        <div className="grid grid-cols-2 gap-3">
          <button
            onClick={() => navigate("/custom/create/")}
            className="flex flex-col items-center gap-2 rounded-2xl border-2 border-dashed border-primary/40 bg-primary/10 px-4 py-6 text-primary-dark hover:bg-primary/20 transition-colors"
          >
            <span className="text-2xl">📷</span>
            <span className="font-bold text-sm">拍照上传</span>
          </button>
          <button
            onClick={() => navigate("/custom/folder-create/")}
            className="flex flex-col items-center gap-2 rounded-2xl border-2 border-dashed border-secondary/40 bg-secondary/10 px-4 py-6 text-secondary-dark hover:bg-secondary/20 transition-colors"
          >
            <span className="text-2xl">📁</span>
            <span className="font-bold text-sm">从文件夹创建</span>
          </button>
        </div>

        {loading && (
          <div className="flex items-center justify-center py-12">
            <div className="animate-spin rounded-full h-8 w-8 border-4 border-primary border-t-transparent" />
          </div>
        )}

        {error && (
          <div className="px-4 py-3 rounded-xl bg-danger/10 border-2 border-danger/30 text-sm text-danger-dark font-bold">
            {error}
          </div>
        )}

        {!loading && !error && books.length === 0 && (
          <div className="text-center py-12 text-ink-light">
            <p className="text-4xl mb-3">📚</p>
            <p className="font-bold">还没有自定义教材</p>
            <p className="text-sm mt-1">点击上方按钮创建第一本</p>
          </div>
        )}

        <div className="space-y-3">
          {books.map(book => (
            <div
              key={book.id}
              className="group flex items-center gap-3 rounded-2xl border-2 border-bg-softer bg-white p-4 hover:border-primary/20 transition-colors cursor-pointer"
              onClick={() => navigate(`/custom/book/${book.id}/`)}
            >
              <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-primary/10 text-primary-dark text-xl">
                📖
              </div>
              <div className="flex-1 min-w-0">
                <h3 className="font-extrabold text-ink truncate">{book.title}</h3>
                <p className="text-sm text-ink-light">
                  {subjectLabels[book.subject] || book.subject} · {book.grade}年级{book.semester === "up" ? "上" : "下"}册
                </p>
              </div>
              <button
                onClick={(e) => { e.stopPropagation(); handleDelete(book.id, book.title); }}
                className="opacity-0 group-hover:opacity-100 text-ink-softer hover:text-danger text-sm px-2 py-1 transition-opacity"
              >
                删除
              </button>
            </div>
          ))}
        </div>
      </div>
    </main>
  );
}
