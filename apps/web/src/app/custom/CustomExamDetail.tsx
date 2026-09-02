"use client";

import { useState, useEffect, useCallback } from "react";
import {
  navigate, getExam, extractExamText, getExamExtractStatus, updateExamText,
  type Exam, DIFFICULTY_LABELS,
} from "@/lib/customApi";
import { requireParentAuth } from "@/lib/parentAuth";
import { ArrowLeft } from "@/components/icons";

const subjectLabels: Record<string, string> = {
  math: "数学", chinese: "语文", english: "英语", science: "科学",
};

export function CustomExamDetail({ examId }: { examId: string }) {
  const [exam, setExam] = useState<Exam | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [extracting, setExtracting] = useState(false);
  const [extractStatus, setExtractStatus] = useState("");
  const [editing, setEditing] = useState(false);
  const [editText, setEditText] = useState("");
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    try {
      const data = await getExam(examId);
      setExam(data);
      setEditText(data.text_content || "");
    } catch (e: any) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, [examId]);

  useEffect(() => { load(); }, [load]);

  // Poll extract status
  useEffect(() => {
    if (!extracting) return;
    const timer = setInterval(async () => {
      try {
        const status = await getExamExtractStatus(examId);
        if (status.status === "done") {
          setExtracting(false);
          setExtractStatus("");
          await load();
        } else if (status.status === "error") {
          setExtracting(false);
          setExtractStatus("识别失败: " + (status.message || "未知错误"));
        } else {
          setExtractStatus(status.message || "正在识别...");
        }
      } catch {
        // ignore poll errors
      }
    }, 2000);
    return () => clearInterval(timer);
  }, [extracting, examId, load]);

  async function handleExtract() {
    const ok = await requireParentAuth("识别文字");
    if (!ok) return;
    setExtracting(true);
    setExtractStatus("正在识别...");
    try {
      await extractExamText(examId);
    } catch (e: any) {
      setExtracting(false);
      setExtractStatus("启动失败: " + e.message);
    }
  }

  async function handleEditStart() {
    const ok = await requireParentAuth("编辑文字");
    if (!ok) return;
    setEditing(true);
  }

  async function handleSave() {
    setSaving(true);
    try {
      await updateExamText(examId, editText);
      await load();
      setEditing(false);
    } catch (e: any) {
      alert("保存失败: " + e.message);
    } finally {
      setSaving(false);
    }
  }

  if (loading) return (
    <div className="min-h-screen bg-bg-soft flex items-center justify-center">
      <div className="animate-spin rounded-full h-8 w-8 border-4 border-primary border-t-transparent" />
    </div>
  );

  if (error || !exam) return (
    <div className="min-h-screen bg-bg-soft flex flex-col items-center justify-center gap-4">
      <p className="text-danger font-bold">{error || "试卷不存在"}</p>
      <button onClick={() => navigate("/custom/exams")} className="text-primary-dark font-bold">返回</button>
    </div>
  );

  const hasText = exam.has_text || !!exam.text_content;

  return (
    <main className="min-h-screen bg-bg-soft pb-20 md:pb-8">
      <header className="sticky top-0 z-30 bg-white border-b border-bg-softer px-4 py-3 md:px-6">
        <div className="flex items-center gap-3 max-w-3xl mx-auto">
          <button onClick={() => navigate("/custom/exams")} className="text-ink-softer hover:text-ink transition-colors">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-lg font-extrabold text-ink truncate">{exam.title}</h1>
        </div>
      </header>

      <div className="max-w-3xl mx-auto px-4 py-6 space-y-6 md:px-6">
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="px-2.5 py-1 rounded-lg bg-primary/10 text-primary-dark font-bold">
            {subjectLabels[exam.subject] || exam.subject}
          </span>
          <span className="px-2.5 py-1 rounded-lg bg-secondary/10 text-secondary-dark font-bold">
            {exam.grade}年级{exam.semester === "up" ? "上" : "下"}册
          </span>
          <span className="px-2.5 py-1 rounded-lg bg-warning/10 text-warning font-bold">
            {DIFFICULTY_LABELS[exam.difficulty as keyof typeof DIFFICULTY_LABELS] || exam.difficulty}
          </span>
          <span className="px-2.5 py-1 rounded-lg bg-bg-softer text-ink-light">
            {exam.total_pages}页
          </span>
        </div>

        {/* 文字识别 */}
        <div className="rounded-2xl border-2 border-bg-softer bg-white p-4 space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-sm font-extrabold text-ink">试卷文字</span>
            {hasText ? (
              <span className="text-xs text-secondary-dark font-bold">✓ 已识别 ({exam.text_len || 0} 字)</span>
            ) : (
              <span className="text-xs text-warning font-bold">未识别</span>
            )}
          </div>

          {extracting && (
            <div className="flex items-center gap-2 text-sm text-primary-dark">
              <div className="animate-spin w-4 h-4 border-2 border-primary border-t-transparent rounded-full" />
              {extractStatus}
            </div>
          )}

          {!hasText && !extracting && (
            <button
              onClick={handleExtract}
              className="w-full flex items-center justify-center gap-2 rounded-xl bg-primary px-4 py-2.5 text-white font-extrabold hover:bg-primary-dark transition-colors"
            >
              🤖 AI 识别文字
            </button>
          )}

          {hasText && !editing && !extracting && (
            <>
              <div className="rounded-xl bg-bg-soft p-3 max-h-96 overflow-y-auto">
                <pre className="text-xs text-ink whitespace-pre-wrap font-mono">
                  {exam.text_content || "(空)"}
                </pre>
              </div>
              <div className="flex gap-2">
                <button
                  onClick={handleExtract}
                  className="flex-1 rounded-xl border-2 border-bg-softer px-3 py-2 text-sm text-ink-light hover:text-ink hover:border-ink/15 transition-colors"
                >
                  🔄 重新识别
                </button>
                <button
                  onClick={handleEditStart}
                  className="flex-1 rounded-xl border-2 border-bg-softer px-3 py-2 text-sm text-ink-light hover:text-ink hover:border-ink/15 transition-colors"
                >
                  ✏️ 编辑文字
                </button>
              </div>
            </>
          )}

          {editing && (
            <>
              <textarea
                value={editText}
                onChange={e => setEditText(e.target.value)}
                className="w-full h-64 rounded-xl bg-bg-soft p-3 text-xs text-ink font-mono border-2 border-bg-softer focus:border-primary focus:outline-none resize-none"
                placeholder="试卷文字内容..."
              />
              <div className="flex gap-2">
                <button
                  onClick={() => { setEditing(false); setEditText(exam.text_content || ""); }}
                  className="flex-1 rounded-xl border-2 border-bg-softer px-3 py-2 text-sm text-ink-light hover:text-ink transition-colors"
                >
                  取消
                </button>
                <button
                  onClick={handleSave}
                  disabled={saving}
                  className="flex-1 rounded-xl bg-primary px-3 py-2 text-sm text-white font-bold hover:bg-primary-dark disabled:opacity-50 transition-colors"
                >
                  {saving ? "保存中..." : "保存"}
                </button>
              </div>
            </>
          )}
        </div>

        {hasText && !extracting && (
          <div className="rounded-2xl border-2 border-primary/20 bg-primary/5 p-4">
            <p className="text-sm font-extrabold text-primary-dark mb-1">可用于出题</p>
            <p className="text-xs text-ink-light">
              前往「打印试卷」页面，选择本真题作为参考，AI 将模仿其风格和难度生成新题。
            </p>
            <button
              onClick={() => navigate("/worksheet/")}
              className="mt-3 w-full flex items-center justify-center gap-2 rounded-xl bg-primary px-4 py-2.5 text-white font-extrabold hover:bg-primary-dark transition-colors"
            >
              🖨️ 去打印试卷
            </button>
          </div>
        )}
      </div>
    </main>
  );
}
