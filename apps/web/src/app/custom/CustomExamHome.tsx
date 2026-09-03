"use client";

import { useState, useEffect } from "react";
import { navigate } from "@/lib/customApi";
import {
  listExams, deleteExam,
  type Exam, DIFFICULTY_LABELS,
} from "@/lib/customApi";
import { requireParentAuth } from "@/lib/parentAuth";
import { ArrowLeft } from "@/components/icons";

const subjectLabels: Record<string, string> = {
  math: "数学", chinese: "语文", english: "英语", science: "科学",
};

export function CustomExamHome() {
  const [exams, setExams] = useState<Exam[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => { load(); }, []);

  async function load() {
    try {
      const data = await listExams();
      setExams(data);
    } catch (e: any) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }

  async function handleDelete(id: string, title: string) {
    const ok = await requireParentAuth("删除真题");
    if (!ok) return;
    if (!confirm(`确定删除「${title}」？`)) return;
    try {
      await deleteExam(id);
      setExams(exams.filter(e => e.id !== id));
    } catch (e: any) {
      alert("删除失败: " + e.message);
    }
  }

  return (
    <main className="min-h-screen bg-bg-soft pb-20 md:pb-8">
      <header className="sticky top-0 z-30 bg-white border-b border-bg-softer px-4 py-3 md:px-6">
        <div className="flex items-center gap-3 max-w-3xl mx-auto">
          <button onClick={() => window.location.assign("/worksheet/")} className="text-ink-softer hover:text-ink transition-colors">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-lg font-extrabold text-ink">真题库</h1>
          <span className="text-xs text-ink-light ml-auto hidden sm:inline">上传真题 · AI 仿生成</span>
        </div>
      </header>

      <div className="max-w-3xl mx-auto px-4 py-6 space-y-6 md:px-6">
        <button
          onClick={async () => {
            const ok = await requireParentAuth("上传真题");
            if (ok) navigate("/custom/exam/create");
          }}
          className="w-full flex items-center justify-center gap-2 rounded-2xl border-2 border-dashed border-primary/40 bg-primary/10 px-4 py-6 text-primary-dark hover:bg-primary/20 transition-colors"
        >
          <span className="text-2xl">📝</span>
          <span className="font-bold text-sm">上传真题试卷</span>
        </button>

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

        {!loading && !error && exams.length === 0 && (
          <div className="text-center py-12 text-ink-light">
            <p className="text-4xl mb-3">📋</p>
            <p className="font-bold">还没有真题试卷</p>
            <p className="text-sm mt-1">上传一份真题，AI 将学习其风格生成新题</p>
          </div>
        )}

        <div className="space-y-3">
          {exams.map(exam => (
            <div
              key={exam.id}
              className="group flex items-center gap-3 rounded-2xl border-2 border-bg-softer bg-white p-4 hover:border-primary/20 transition-colors cursor-pointer"
              onClick={() => navigate(`/custom/exam/${exam.id}`)}
            >
              <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-warning/10 text-warning text-xl">
                📝
              </div>
              <div className="flex-1 min-w-0">
                <h3 className="font-extrabold text-ink truncate">{exam.title}</h3>
                <p className="text-sm text-ink-light">
                  {subjectLabels[exam.subject] || exam.subject} · {exam.grade}年级{exam.semester === "up" ? "上" : "下"}册 · {DIFFICULTY_LABELS[exam.difficulty as keyof typeof DIFFICULTY_LABELS] || exam.difficulty}
                </p>
                <div className="flex items-center gap-2 mt-0.5">
                  {exam.has_text ? (
                    <span className="text-xs text-secondary-dark font-bold">✓ 已识别</span>
                  ) : (
                    <span className="text-xs text-warning font-bold">待识别</span>
                  )}
                  <span className="text-xs text-ink-softer">· {exam.total_pages}页</span>
                </div>
              </div>
              <button
                onClick={(e) => { e.stopPropagation(); handleDelete(exam.id, exam.title); }}
                className="no-print opacity-0 group-hover:opacity-100 text-ink-softer hover:text-danger text-sm px-2 py-1 transition-opacity"
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
