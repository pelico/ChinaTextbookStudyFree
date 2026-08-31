"use client";

import { useState, useEffect } from "react";
import { apiGet, navigate, type CustomBook } from "@/lib/customApi";

const subjectLabels: Record<string, string> = {
  math: "数学", chinese: "语文", english: "英语", science: "科学",
};
const difficultyStars = (d: number) => "★".repeat(d) + "☆".repeat(5 - d);

export function CustomBook({ bookId }: { bookId: string }) {
  const [book, setBook] = useState<CustomBook | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    (async () => {
      try {
        const data = await apiGet<CustomBook>(`books/${bookId}`);
        setBook(data);
      } catch (e: any) {
        setError(e.message);
      } finally {
        setLoading(false);
      }
    })();
  }, [bookId]);

  if (loading) return (
    <div className="min-h-screen bg-bg flex items-center justify-center">
      <div className="animate-spin rounded-full h-8 w-8 border-4 border-violet-500 border-t-transparent" />
    </div>
  );

  if (error || !book) return (
    <div className="min-h-screen bg-bg flex flex-col items-center justify-center gap-4">
      <p className="text-red-400">{error || "书本不存在"}</p>
      <button onClick={() => navigate("/custom/")} className="text-violet-400">返回</button>
    </div>
  );

  return (
    <div className="min-h-screen bg-bg p-4 md:p-6">
      <div className="mx-auto max-w-2xl">
        <div className="flex items-center gap-3 mb-2">
          <button onClick={() => navigate("/custom/")} className="text-text-muted hover:text-text">←</button>
          <h1 className="text-xl font-bold text-text truncate">{book.title}</h1>
        </div>
        <p className="text-sm text-text-muted mb-4 ml-7">
          {subjectLabels[book.subject] || book.subject} · {book.grade}年级{book.semester === "up" ? "上" : "下"}册
        </p>

        <button
          onClick={() => navigate(`/custom/book/${bookId}/read/`)}
          className="mb-6 w-full flex items-center justify-center gap-2 rounded-xl bg-emerald-500/15 border border-emerald-500/30 px-4 py-3 text-emerald-300 hover:bg-emerald-500/25 transition-colors"
        >
          <span>📖</span>
          <span className="font-bold text-sm">阅读原文 + 语音朗读</span>
        </button>

        {(!book.units || book.units.length === 0) && (
          <div className="rounded-xl bg-bg-soft p-6 text-center text-text-muted">
            <p>AI 未能从照片中识别出单元结构</p>
            <p className="text-sm mt-1">请尝试重新创建，上传更清晰的教材图片</p>
          </div>
        )}

        <div className="space-y-6">
          {book.units?.map(unit => (
            <div key={unit.id}>
              <div className="flex items-center gap-2 mb-3">
                <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-violet-500/20 text-violet-300 text-sm font-bold">
                  {unit.unit_number}
                </span>
                <h2 className="font-bold text-text">{unit.title || `第${unit.unit_number}单元`}</h2>
              </div>

              <div className="ml-9 space-y-2">
                {unit.knowledge_points.map((kp, idx) => (
                  <div
                    key={kp.id}
                    className="flex items-center gap-3 rounded-xl bg-bg-soft p-3.5 hover:bg-bg-soft/60 cursor-pointer transition-colors"
                    onClick={() => navigate(`/custom/book/${bookId}/${kp.id}/`)}
                  >
                    <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-violet-500/10 text-violet-300 text-sm">
                      {idx + 1}
                    </div>
                    <div className="flex-1 min-w-0">
                      <h3 className="font-bold text-text text-sm truncate">{kp.name}</h3>
                      {kp.description && (
                        <p className="text-xs text-text-muted truncate">{kp.description}</p>
                      )}
                    </div>
                    <div className="text-xs text-amber-400/70 whitespace-nowrap">
                      {difficultyStars(kp.difficulty)}
                    </div>
                    <span className="text-text-muted">→</span>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
