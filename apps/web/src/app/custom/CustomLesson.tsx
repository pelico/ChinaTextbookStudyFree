"use client";

import { useState, useEffect, useCallback } from "react";
import dynamic from "next/dynamic";
import { apiGet, apiPost, navigate, type CustomBook, type QuestionSet } from "@/lib/customApi";
import type { Lesson, Question } from "@/types";

const LessonRunner = dynamic(
  () => import("@/components/LessonRunner").then(m => ({ default: m.LessonRunner })),
  { ssr: false, loading: () => (
    <div className="flex items-center justify-center py-20">
      <div className="animate-spin rounded-full h-8 w-8 border-4 border-violet-500 border-t-transparent" />
    </div>
  )},
);

export function CustomLesson({ bookId, lessonId }: { bookId: string; lessonId: string }) {
  const [lesson, setLesson] = useState<Lesson | null>(null);
  const [version, setVersion] = useState(0);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState("");
  const [kpName, setKpName] = useState("");
  const [bookSubject, setBookSubject] = useState<string>("");

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const [book, qSet] = await Promise.all([
        apiGet<CustomBook>(`books/${bookId}`),
        apiPost<QuestionSet>(`lessons/${lessonId}/questions`),
      ]);

      for (const u of book.units || []) {
        const idx = u.knowledge_points.findIndex(kp => kp.id === lessonId);
        if (idx >= 0) {
          setBookSubject(book.subject);
          const kp = u.knowledge_points[idx];
          setLesson({
            id: lessonId,
            title: kp.name,
            bookId,
            unitNumber: u.unit_number,
            unitTitle: u.title,
            kpIndex: idx,
            kpTotal: u.knowledge_points.length,
            questions: qSet.questions as Question[],
            knowledge: null,
          });
          setKpName(kp.name);
          setVersion(v => v + 1);
          break;
        }
      }
    } catch (e: any) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, [bookId, lessonId]);

  useEffect(() => { load(); }, [load]);

  async function handleRefresh() {
    setRefreshing(true);
    setError("");
    try {
      const qSet = await apiPost<QuestionSet>(`lessons/${lessonId}/refresh`);
      if (lesson) {
        setLesson({ ...lesson, questions: qSet.questions as Question[] });
        setVersion(v => v + 1);
      }
    } catch (e: any) {
      setError(e.message);
    } finally {
      setRefreshing(false);
    }
  }

  if (loading) return (
    <div className="min-h-screen bg-bg flex items-center justify-center">
      <div className="flex flex-col items-center gap-3">
        <div className="animate-spin rounded-full h-10 w-10 border-4 border-violet-500 border-t-transparent" />
        <p className="text-sm text-text-muted">AI 正在生成题目...</p>
      </div>
    </div>
  );

  if (error) return (
    <div className="min-h-screen bg-bg flex flex-col items-center justify-center gap-4 p-4">
      <div className="rounded-xl bg-red-500/10 border border-red-500/30 p-4 text-red-400 text-center max-w-md">
        <p className="font-bold mb-1">出错了</p>
        <p className="text-sm">{error}</p>
      </div>
      <div className="flex gap-3">
        <button onClick={() => navigate(`/custom/book/${bookId}/`)} className="rounded-xl bg-bg-soft px-4 py-2 text-text-muted">返回</button>
        <button onClick={load} className="rounded-xl bg-violet-500 px-4 py-2 text-white font-bold">重试</button>
      </div>
    </div>
  );

  if (!lesson) return null;

  return (
    <div className="h-dvh flex flex-col overflow-hidden bg-bg">
      <div className="shrink-0 z-20 flex items-center justify-between gap-3 border-b border-bg-soft bg-bg/95 backdrop-blur px-4 py-2.5">
        <button onClick={() => navigate(`/custom/book/${bookId}/`)} className="text-sm text-text-muted hover:text-text">
          ← {kpName}
        </button>
        <button
          onClick={handleRefresh}
          disabled={refreshing}
          className="flex items-center gap-1.5 rounded-lg bg-violet-500/15 px-3 py-1.5 text-sm text-violet-300 hover:bg-violet-500/25 disabled:opacity-50 transition-colors"
        >
          {refreshing ? (
            <>
              <div className="animate-spin rounded-full h-3.5 w-3.5 border-2 border-violet-400 border-t-transparent" />
              生成中
            </>
          ) : (
            <>🔄 换一套题</>
          )}
        </button>
      </div>
      <LessonRunner key={version} lesson={lesson} chestSlot={null} backHref={`/custom/book/${bookId}/`} navigateFn={navigate} speakLang={bookSubject === "english" ? "en-US" : "zh-CN"} />
    </div>
  );
}
