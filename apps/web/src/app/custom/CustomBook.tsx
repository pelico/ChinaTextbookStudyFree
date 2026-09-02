"use client";

import { useState, useEffect, useCallback } from "react";
import {
  apiGet, navigate, getTextStatus, generateOutlineFromTexts,
  type CustomBook, type TextStatus,
} from "@/lib/customApi";
import { requireParentAuth } from "@/lib/parentAuth";
import { ArrowLeft } from "@/components/icons";

const subjectLabels: Record<string, string> = {
  math: "数学", chinese: "语文", english: "英语", science: "科学",
};
const difficultyStars = (d: number) => "★".repeat(d) + "☆".repeat(5 - d);

export function CustomBook({ bookId }: { bookId: string }) {
  const [book, setBook] = useState<CustomBook | null>(null);
  const [textStatus, setTextStatus] = useState<TextStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [generating, setGenerating] = useState(false);
  const [genError, setGenError] = useState("");

  const load = useCallback(async () => {
    try {
      const [data, status] = await Promise.all([
        apiGet<CustomBook>(`books/${bookId}`),
        getTextStatus(bookId),
      ]);
      setBook(data);
      setTextStatus(status);
    } catch (e: any) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, [bookId]);

  useEffect(() => { load(); }, [load]);

  async function handleGenerateOutline() {
    const ok = await requireParentAuth("生成大纲");
    if (!ok) return;
    setGenerating(true);
    setGenError("");
    try {
      await generateOutlineFromTexts(bookId);
      await load();
    } catch (e: any) {
      setGenError(e.message);
    } finally {
      setGenerating(false);
    }
  }

  if (loading) return (
    <div className="min-h-screen bg-bg-soft flex items-center justify-center">
      <div className="animate-spin rounded-full h-8 w-8 border-4 border-primary border-t-transparent" />
    </div>
  );

  if (error || !book) return (
    <div className="min-h-screen bg-bg-soft flex flex-col items-center justify-center gap-4">
      <p className="text-danger font-bold">{error || "书本不存在"}</p>
      <button onClick={() => navigate("/custom/")} className="text-primary-dark font-bold">返回</button>
    </div>
  );

  const hasUnits = book.units && book.units.length > 0;
  const hasText = textStatus?.has_text;
  const textProgress = textStatus ? `${textStatus.text_pages}/${textStatus.total_pages}` : "0/0";
  const allTextExtracted = !!textStatus && textStatus.text_pages === textStatus.total_pages && textStatus.total_pages > 0;

  return (
    <main className="min-h-screen bg-bg-soft pb-20 md:pb-8">
      <header className="sticky top-0 z-30 bg-white border-b border-bg-softer px-4 py-3 md:px-6">
        <div className="flex items-center gap-3 max-w-3xl mx-auto">
          <button onClick={() => navigate("/custom/")} className="text-ink-softer hover:text-ink transition-colors">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-lg font-extrabold text-ink truncate">{book.title}</h1>
        </div>
      </header>

      <div className="max-w-3xl mx-auto px-4 py-6 space-y-6 md:px-6">
        <p className="text-sm text-ink-light">
          {subjectLabels[book.subject] || book.subject} · {book.grade}年级{book.semester === "up" ? "上" : "下"}册
        </p>

        {/* 阅读按钮 */}
        <button
          onClick={() => navigate(`/custom/book/${bookId}/read/`)}
          className="w-full flex items-center justify-center gap-2 rounded-2xl border-2 border-secondary/40 bg-secondary/10 px-4 py-3 text-secondary-dark font-bold hover:bg-secondary/20 transition-colors"
        >
          <span>📖</span>
          <span className="text-sm">阅读原文 + 语音朗读 + 文字修正</span>
        </button>

        {/* 文字提取进度 */}
        {textStatus && (
          <div className="rounded-xl border-2 border-bg-softer bg-white px-4 py-3">
            <div className="flex items-center justify-between text-sm">
              <span className="text-ink-light">文字提取进度</span>
              <span className={allTextExtracted ? "text-secondary-dark font-extrabold" : "text-warning font-bold"}>
                {textProgress} 页
              </span>
            </div>
            {hasText && !allTextExtracted && (
              <p className="text-xs text-ink-softer mt-1">部分页面尚未提取，可在阅读页继续提取</p>
            )}
          </div>
        )}

        {/* 无大纲时的引导 */}
        {!hasUnits && (
          <div className="space-y-3">
            {hasText ? (
              <div className="rounded-2xl border-2 border-primary/30 bg-primary/10 p-4">
                <p className="text-sm font-extrabold text-primary-dark mb-1">文字已提取，可以生成大纲</p>
                <p className="text-xs text-ink-light mb-3">
                  AI 将基于 {textStatus?.text_pages} 页文字内容分析单元和知识点结构
                </p>
                <button
                  onClick={handleGenerateOutline}
                  disabled={generating}
                  className="w-full flex items-center justify-center gap-2 rounded-xl bg-primary px-4 py-2.5 text-white font-extrabold hover:bg-primary-dark disabled:opacity-50 transition-colors"
                >
                  {generating ? (
                    <>
                      <div className="animate-spin w-4 h-4 border-2 border-white border-t-transparent rounded-full" />
                      AI 分析中...
                    </>
                  ) : (
                    <>🧠 从文字生成大纲</>
                  )}
                </button>
                {genError && (
                  <p className="mt-2 text-xs text-danger">{genError}</p>
                )}
              </div>
            ) : (
              <div className="rounded-2xl border-2 border-warning/30 bg-warning/10 p-4 text-center">
                <p className="text-sm font-extrabold text-ink mb-1">需要先提取文字</p>
                <p className="text-xs text-ink-light">
                  点击上方"阅读原文"，在阅读页逐页提取文字内容
                </p>
                <p className="text-xs text-ink-light mt-1">
                  提取后可人工修正，再回到此页生成大纲和题目
                </p>
              </div>
            )}
          </div>
        )}

        {/* 单元和知识点列表 */}
        {hasUnits && (
          <div className="space-y-6">
            {book.units!.map(unit => (
              <div key={unit.id}>
                <div className="flex items-center gap-2 mb-3">
                  <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-primary/10 text-primary-dark text-sm font-extrabold">
                    {unit.unit_number}
                  </span>
                  <h2 className="font-extrabold text-ink">{unit.title || `第${unit.unit_number}单元`}</h2>
                </div>

                <div className="ml-9 space-y-2">
                  {unit.knowledge_points.map((kp, idx) => (
                    <div
                      key={kp.id}
                      className="flex items-center gap-3 rounded-xl border-2 border-bg-softer bg-white p-3.5 hover:border-primary/20 cursor-pointer transition-colors"
                      onClick={() => navigate(`/custom/book/${bookId}/${kp.id}/`)}
                    >
                      <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary/10 text-primary-dark text-sm font-bold">
                        {idx + 1}
                      </div>
                      <div className="flex-1 min-w-0">
                        <h3 className="font-bold text-ink text-sm truncate">{kp.name}</h3>
                        {kp.description && (
                          <p className="text-xs text-ink-light truncate">{kp.description}</p>
                        )}
                      </div>
                      <div className="text-xs text-warning/70 whitespace-nowrap">
                        {difficultyStars(kp.difficulty)}
                      </div>
                      <span className="text-ink-softer">→</span>
                    </div>
                  ))}
                </div>
              </div>
            ))}

            {/* 已有大纲时也允许重新生成 */}
            <button
              onClick={handleGenerateOutline}
              disabled={generating}
              className="w-full flex items-center justify-center gap-2 rounded-xl border-2 border-bg-softer bg-white px-4 py-2.5 text-sm text-ink-light hover:text-ink hover:border-ink/15 disabled:opacity-50 transition-colors"
            >
              {generating ? "AI 分析中..." : "🔄 从文字重新生成大纲"}
            </button>
          </div>
        )}
      </div>
    </main>
  );
}
