"use client";

import { useState, useMemo, useCallback, useEffect, type ReactNode } from "react";
import Link from "next/link";
import {
  type BookInfo,
  type WorksheetConfig,
  type WorksheetQuestion,
  type AIConfig,
  QUESTION_TYPE_LABELS,
  SUBJECT_LABELS,
  loadAIConfig,
  saveAIConfig,
  generateWorksheet,
} from "@/lib/worksheet";
import type { SubjectId } from "@cstf/core";
import { ArrowLeft } from "@/components/icons";

const SUBJECT_LIST: SubjectId[] = ["chinese", "math", "english", "science"];

const SUBJECT_COLORS: Record<SubjectId, string> = {
  chinese: "border-danger/40 bg-danger/10 text-danger-dark",
  math: "border-primary/40 bg-primary/10 text-primary-dark",
  english: "border-secondary/40 bg-secondary/10 text-secondary-dark",
  science: "border-warning/40 bg-warning/10 text-ink",
};

interface Props {
  books: BookInfo[];
}

export function WorksheetClient({ books }: Props) {
  const [selectedSubject, setSelectedSubject] = useState<SubjectId>("science");
  const [selectedGrade, setSelectedGrade] = useState<number>(2);
  const [selectedBookId, setSelectedBookId] = useState<string>("");
  const [selectedUnits, setSelectedUnits] = useState<Set<number>>(new Set());
  const [questionTypes, setQuestionTypes] = useState({
    true_false: 5,
    choice: 5,
    fill_blank_text: 5,
    short_answer: 0,
  });
  const [difficultyMax, setDifficultyMax] = useState(3);
  const [includeAnswerKey, setIncludeAnswerKey] = useState(true);
  const [aiConfig, setAiConfig] = useState<AIConfig>(loadAIConfig);
  const [showAISettings, setShowAISettings] = useState(false);
  const [generating, setGenerating] = useState(false);
  const [error, setError] = useState("");
  const [questions, setQuestions] = useState<WorksheetQuestion[]>([]);
  const [showPreview, setShowPreview] = useState(false);

  const grades = useMemo(() => {
    const set = new Set(books.filter(b => b.subject === selectedSubject).map(b => b.grade));
    return Array.from(set).sort((a, b) => a - b);
  }, [books, selectedSubject]);

  const availableBooks = useMemo(
    () => books.filter(b => b.subject === selectedSubject && b.grade === selectedGrade),
    [books, selectedSubject, selectedGrade],
  );

  const selectedBook = useMemo(
    () => availableBooks.find(b => b.id === selectedBookId) ?? availableBooks[0],
    [availableBooks, selectedBookId],
  );

  const selectedBookUnits = selectedBook?.outline.units ?? [];

  const toggleUnit = useCallback((unitNum: number) => {
    setSelectedUnits(prev => {
      const next = new Set(prev);
      if (next.has(unitNum)) next.delete(unitNum);
      else next.add(unitNum);
      return next;
    });
  }, []);

  const handleGenerate = useCallback(async () => {
    if (!selectedBook) {
      setError("请先选择教材");
      return;
    }
    if (!aiConfig.apiKey) {
      setError("请先设置 AI 接口的 API Key");
      setShowAISettings(true);
      return;
    }

    const unitNumbers = Array.from(selectedUnits).sort((a, b) => a - b);
    const units = unitNumbers.length === 0
      ? selectedBookUnits
      : selectedBookUnits.filter(u => selectedUnits.has(u.unit_number));

    if (units.length === 0) {
      setError("该教材没有单元数据");
      return;
    }

    const totalQ = Object.values(questionTypes).reduce((a, b) => a + b, 0);
    if (totalQ === 0) {
      setError("请至少选择一种题型");
      return;
    }

    setGenerating(true);
    setError("");

    const config: WorksheetConfig = {
      subject: selectedSubject,
      bookId: selectedBook.id,
      textbookName: selectedBook.textbookName,
      unitNumbers,
      questionTypes,
      difficultyMax,
      includeAnswerKey,
    };

    try {
      const result = await generateWorksheet(config, aiConfig, units);
      setQuestions(result);
      setShowPreview(true);
    } catch (e) {
      setError(e instanceof Error ? e.message : "生成失败，请检查 AI 接口配置");
    } finally {
      setGenerating(false);
    }
  }, [selectedBook, aiConfig, selectedUnits, selectedBookUnits, questionTypes, difficultyMax, includeAnswerKey, selectedSubject]);

  if (showPreview && questions.length > 0) {
    return (
      <PrintPreview
        questions={questions}
        config={{
          subject: selectedSubject,
          bookId: selectedBook?.id ?? "",
          textbookName: selectedBook?.textbookName ?? "",
          unitNumbers: Array.from(selectedUnits).sort((a, b) => a - b),
          questionTypes,
          difficultyMax,
          includeAnswerKey,
        }}
        onBack={() => setShowPreview(false)}
      />
    );
  }

  return (
    <main className="min-h-screen bg-bg-soft pb-20 md:pb-8">
      {/* 顶栏 */}
      <header className="sticky top-0 z-30 bg-white border-b border-bg-softer px-4 py-3 md:px-6">
        <div className="flex items-center gap-3 max-w-3xl mx-auto">
          <Link href="/" className="text-ink-softer hover:text-ink transition-colors">
            <ArrowLeft className="w-5 h-5" />
          </Link>
          <h1 className="text-lg font-extrabold text-ink">打印试卷</h1>
          <span className="text-xs text-ink-light ml-auto hidden sm:inline">AI 生成 · 可打印 A4</span>
        </div>
      </header>

      <div className="max-w-3xl mx-auto px-4 py-6 space-y-6 md:px-6">
        {/* Step 1: 学科 */}
        <Section step={1} title="选择学科">
          <div className="grid grid-cols-4 gap-3">
            {SUBJECT_LIST.map(s => (
              <button
                key={s}
                onClick={() => {
                  setSelectedSubject(s);
                  setSelectedBookId("");
                  setSelectedUnits(new Set());
                }}
                className={`px-3 py-3 rounded-2xl border-2 text-sm font-bold transition-all ${
                  selectedSubject === s
                    ? SUBJECT_COLORS[s]
                    : "border-bg-softer bg-white text-ink-softer hover:border-ink/20"
                }`}
              >
                {SUBJECT_LABELS[s]}
              </button>
            ))}
          </div>
        </Section>

        {/* Step 2: 年级 */}
        <Section step={2} title="选择年级">
          <div className="flex flex-wrap gap-3">
            {grades.map(g => (
              <button
                key={g}
                onClick={() => {
                  setSelectedGrade(g);
                  setSelectedBookId("");
                  setSelectedUnits(new Set());
                }}
                className={`px-4 py-2.5 rounded-xl border-2 text-sm font-bold transition-all ${
                  selectedGrade === g
                    ? "border-primary bg-primary/10 text-primary-dark"
                    : "border-bg-softer bg-white text-ink-softer hover:border-ink/20"
                }`}
              >
                {g}年级
              </button>
            ))}
          </div>
        </Section>

        {/* Step 3: 教材 */}
        <Section step={3} title="选择教材">
          {availableBooks.length === 0 ? (
            <p className="text-sm text-ink-light">该学科暂无此年级教材</p>
          ) : (
            <div className="flex flex-wrap gap-3">
              {availableBooks.map(b => (
                <button
                  key={b.id}
                  onClick={() => {
                    setSelectedBookId(b.id);
                    setSelectedUnits(new Set());
                  }}
                  className={`px-4 py-2.5 rounded-xl border-2 text-sm font-bold transition-all ${
                    (selectedBookId || availableBooks[0]?.id) === b.id
                      ? "border-primary bg-primary/10 text-primary-dark"
                      : "border-bg-softer bg-white text-ink-softer hover:border-ink/20"
                  }`}
                >
                  {b.textbookName}
                </button>
              ))}
            </div>
          )}
        </Section>

        {/* Step 4: 单元 */}
        {selectedBook && selectedBookUnits.length > 0 && (
          <Section step={4} title="选择单元（不选则全部）">
            <div className="space-y-2.5">
              {selectedBookUnits.map(u => (
                <label
                  key={u.unit_number}
                  className="flex items-center gap-3 p-3 rounded-xl border-2 border-bg-softer bg-white cursor-pointer hover:border-ink/15 transition-colors"
                >
                  <input
                    type="checkbox"
                    checked={selectedUnits.has(u.unit_number)}
                    onChange={() => toggleUnit(u.unit_number)}
                    className="w-4 h-4 accent-primary"
                  />
                  <span className="text-sm font-bold text-ink">
                    第{u.unit_number}单元 · {u.title}
                  </span>
                  <span className="text-xs text-ink-light ml-auto">
                    {u.knowledge_points.length} 个知识点
                  </span>
                </label>
              ))}
            </div>
          </Section>
        )}

        {/* Step 5: 题型与数量 */}
        <Section step={5} title="题型与数量">
          <div className="space-y-3">
            {(Object.keys(questionTypes) as (keyof typeof questionTypes)[]).map(type => (
              <div key={type} className="flex items-center gap-3 p-3 rounded-xl border-2 border-bg-softer bg-white">
                <div className="flex-1">
                  <div className="text-sm font-bold text-ink">{QUESTION_TYPE_LABELS[type]}</div>
                  <div className="text-xs text-ink-light">
                    {type === "true_false" && "每题2分 · 判断对错"}
                    {type === "choice" && "每题5分 · 四选一"}
                    {type === "fill_blank_text" && "每空2分 · 文字填空"}
                    {type === "short_answer" && "每题8分 · 简要作答"}
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => setQuestionTypes(prev => ({ ...prev, [type]: Math.max(0, prev[type] - 1) }))}
                    className="w-8 h-8 rounded-lg bg-bg-soft text-ink font-bold hover:bg-bg-softer transition-colors"
                  >
                    −
                  </button>
                  <span className="w-8 text-center text-sm font-extrabold text-ink tabular-nums">
                    {questionTypes[type]}
                  </span>
                  <button
                    onClick={() => setQuestionTypes(prev => ({ ...prev, [type]: Math.min(20, prev[type] + 1) }))}
                    className="w-8 h-8 rounded-lg bg-bg-soft text-ink font-bold hover:bg-bg-softer transition-colors"
                  >
                    +
                  </button>
                </div>
              </div>
            ))}
            <div className="flex items-center justify-between px-1">
              <span className="text-xs text-ink-light">共 {Object.values(questionTypes).reduce((a, b) => a + b, 0)} 题</span>
              <span className="text-xs text-ink-light">
                预计 {
                  questionTypes.true_false * 2 +
                  questionTypes.choice * 5 +
                  questionTypes.fill_blank_text * 2 +
                  questionTypes.short_answer * 8
                } 分
              </span>
            </div>
          </div>
        </Section>

        {/* Step 6: 难度 */}
        <Section step={6} title="难度上限">
          <div className="flex items-center gap-3">
            <input
              type="range"
              min={1}
              max={5}
              value={difficultyMax}
              onChange={e => setDifficultyMax(Number(e.target.value))}
              className="flex-1 accent-primary"
            />
            <span className="text-sm font-extrabold text-ink tabular-nums w-16 text-right">
              {["", "基础", "简单", "中等", "较难", "拓展"][difficultyMax]}
            </span>
          </div>
        </Section>

        {/* AI 设置 */}
        <div className="bg-white rounded-2xl border-2 border-bg-softer p-4 space-y-3">
          <button
            onClick={() => setShowAISettings(!showAISettings)}
            className="flex items-center justify-between w-full"
          >
            <span className="text-sm font-bold text-ink">AI 接口设置</span>
            <span className="text-xs text-ink-light">
              {aiConfig.model || "未设置"} {showAISettings ? "▾" : "▸"}
            </span>
          </button>
          {showAISettings && (
            <div className="space-y-3 pt-2 border-t border-bg-softer">
              <div>
                <label className="text-xs font-bold text-ink-softer block mb-1">API Base URL</label>
                <input
                  type="text"
                  value={aiConfig.baseURL}
                  onChange={e => {
                    const cfg = { ...aiConfig, baseURL: e.target.value };
                    setAiConfig(cfg);
                    saveAIConfig(cfg);
                  }}
                  placeholder="https://api.openai.com/v1"
                  className="w-full px-3 py-2 rounded-lg border-2 border-bg-softer text-sm text-ink focus:border-primary focus:outline-none"
                />
              </div>
              <div>
                <label className="text-xs font-bold text-ink-softer block mb-1">API Key</label>
                <input
                  type="password"
                  value={aiConfig.apiKey}
                  onChange={e => {
                    const cfg = { ...aiConfig, apiKey: e.target.value };
                    setAiConfig(cfg);
                    saveAIConfig(cfg);
                  }}
                  placeholder="sk-..."
                  className="w-full px-3 py-2 rounded-lg border-2 border-bg-softer text-sm text-ink focus:border-primary focus:outline-none"
                />
              </div>
              <div>
                <label className="text-xs font-bold text-ink-softer block mb-1">模型</label>
                <input
                  type="text"
                  value={aiConfig.model}
                  onChange={e => {
                    const cfg = { ...aiConfig, model: e.target.value };
                    setAiConfig(cfg);
                    saveAIConfig(cfg);
                  }}
                  placeholder="gpt-4o-mini"
                  className="w-full px-3 py-2 rounded-lg border-2 border-bg-softer text-sm text-ink focus:border-primary focus:outline-none"
                />
              </div>
              <p className="text-xs text-ink-light">
                支持 OpenAI 兼容接口（如 OpenAI、DeepSeek、通义千问等）。
                Base URL 通常以 <code className="bg-bg-soft px-1 rounded">/v1</code> 结尾。
                配置保存在浏览器本地，不会上传。
              </p>
            </div>
          )}
        </div>

        {/* 选项 */}
        <label className="flex items-center gap-3 cursor-pointer">
          <input
            type="checkbox"
            checked={includeAnswerKey}
            onChange={e => setIncludeAnswerKey(e.target.checked)}
            className="w-4 h-4 accent-primary"
          />
          <span className="text-sm font-bold text-ink">包含参考答案与解析</span>
        </label>

        {/* 错误提示 */}
        {error && (
          <div className="px-4 py-3 rounded-xl bg-danger/10 border-2 border-danger/30 text-sm text-danger-dark font-bold">
            {error}
          </div>
        )}

        {/* 生成按钮 */}
        <button
          onClick={handleGenerate}
          disabled={generating}
          className="w-full py-4 rounded-2xl bg-primary text-white font-extrabold text-base shadow-lg shadow-primary/30 transition-all hover:bg-primary-dark disabled:opacity-60 disabled:shadow-none"
        >
          {generating ? "AI 正在生成试卷..." : "生成试卷"}
        </button>
      </div>
    </main>
  );
}

// ============================================================
// 子组件
// ============================================================

function Section({ step, title, children }: { step: number; title: string; children: ReactNode }) {
  return (
    <section className="space-y-3">
      <div className="flex items-center gap-2">
        <span className="w-6 h-6 rounded-full bg-primary text-white text-xs font-extrabold inline-flex items-center justify-center">
          {step}
        </span>
        <h2 className="text-sm font-extrabold text-ink">{title}</h2>
      </div>
      {children}
    </section>
  );
}

// ============================================================
// 打印预览
// ============================================================

function PrintPreview({
  questions,
  config,
  onBack,
}: {
  questions: WorksheetQuestion[];
  config: WorksheetConfig;
  onBack: () => void;
}) {
  // 打印模式：给 html 加类，便于全局 CSS 隐藏导航等元素
  useEffect(() => {
    document.documentElement.classList.add("worksheet-print-mode");
    return () => {
      document.documentElement.classList.remove("worksheet-print-mode");
    };
  }, []);

  const subjectLabel = SUBJECT_LABELS[config.subject] || config.subject;
  const unitText = config.unitNumbers.length === 0
    ? "全册"
    : config.unitNumbers.map(n => `第${n}单元`).join("、");

  const totalScore = questions.reduce((acc, q) => acc + q.score, 0);

  const grouped = useMemo(() => {
    const groups: Record<string, WorksheetQuestion[]> = {};
    for (const q of questions) {
      if (!groups[q.type]) groups[q.type] = [];
      groups[q.type].push(q);
    }
    return groups;
  }, [questions]);

  const typeOrder = ["true_false", "choice", "fill_blank_text", "short_answer"];
  const sectionLabels: Record<string, string> = {
    true_false: "判断题",
    choice: "选择题",
    fill_blank_text: "填空题",
    short_answer: "简答题",
  };

  return (
    <>
      {/* 屏幕上的操作栏（打印时隐藏） */}
      <div className="no-print sticky top-0 z-30 bg-white border-b border-bg-softer px-4 py-3 md:px-6">
        <div className="flex items-center gap-3 max-w-3xl mx-auto">
          <button onClick={onBack} className="text-ink-softer hover:text-ink transition-colors flex items-center gap-1.5">
            <ArrowLeft className="w-5 h-5" />
            <span className="text-sm font-bold">返回</span>
          </button>
          <h1 className="text-lg font-extrabold text-ink">试卷预览</h1>
          <button
            onClick={() => window.print()}
            className="ml-auto px-4 py-2 rounded-xl bg-primary text-white text-sm font-extrabold shadow-lg shadow-primary/30 hover:bg-primary-dark transition-colors"
          >
            打印 / 保存 PDF
          </button>
        </div>
      </div>

      {/* 试卷内容 */}
      <div className="worksheet-page max-w-[210mm] mx-auto bg-white px-8 py-6 md:px-12 md:py-8 min-h-screen">
        {/* 试卷头 */}
        <div className="text-center mb-6">
          <h1 className="text-2xl font-bold text-black tracking-wide">
            {subjectLabel}练习试卷
          </h1>
          <p className="text-sm text-gray-600 mt-1">
            {config.textbookName} · {unitText}
          </p>
        </div>

        {/* 考生信息 */}
        <div className="flex justify-between text-sm text-black mb-6 border-b-2 border-black pb-3">
          <span>姓名：<span className="inline-block border-b border-black min-w-[80px]">&nbsp;</span></span>
          <span>班级：<span className="inline-block border-b border-black min-w-[80px]">&nbsp;</span></span>
          <span>得分：<span className="inline-block border-b border-black min-w-[40px]">&nbsp;</span></span>
          <span>时间：______ 分钟</span>
        </div>

        {/* 试卷说明 */}
        <div className="text-sm text-gray-700 mb-6">
          <span>满分 {totalScore} 分 · 考试时间 ______ 分钟</span>
        </div>

        {/* 题目 */}
        {typeOrder.map(type => {
          const qs = grouped[type];
          if (!qs || qs.length === 0) return null;
          let num = 0;
          const sectionScore = qs.reduce((acc, q) => acc + q.score, 0);
          return (
            <section key={type} className="mb-8 break-inside-avoid">
              <h2 className="text-base font-bold text-black border-b border-gray-400 pb-1 mb-4">
                {QUESTION_TYPE_LABELS[type] || sectionLabels[type]}（共 {qs.length} 题，{sectionScore} 分）
              </h2>
              <ol className="space-y-4 text-sm text-black leading-7">
                {qs.map((q, i) => {
                  num++;
                  return (
                    <li key={i} className="break-inside-avoid">
                      <div className="flex gap-2">
                        <span className="font-bold flex-shrink-0">{num}.</span>
                        <div className="flex-1">
                          <div>{renderQuestionText(q)}</div>
                          {q.type === "choice" && q.options.length > 0 && (
                            <div className="grid grid-cols-2 gap-x-6 gap-y-1 mt-1.5 ml-4">
                              {q.options.map((opt, oi) => (
                                <div key={oi}>
                                  {"ABCD"[oi]}. {opt}
                                </div>
                              ))}
                            </div>
                          )}
                          {q.type === "true_false" && (
                            <div className="mt-1.5 ml-4 text-gray-500">
                              <span className="border-b border-gray-400 px-4">&nbsp;</span>
                              （对 / 错）
                            </div>
                          )}
                          {q.type === "fill_blank_text" && (
                            <div className="mt-2 text-xs text-gray-400">答：</div>
                          )}
                          {q.type === "short_answer" && (
                            <div className="mt-2 border-b border-gray-300 h-16">&nbsp;</div>
                          )}
                        </div>
                        <span className="text-xs text-gray-500 flex-shrink-0">({q.score}分)</span>
                      </div>
                    </li>
                  );
                })}
              </ol>
            </section>
          );
        })}

        {/* 参考答案 */}
        {config.includeAnswerKey && (
          <section className="answer-key break-before-page mt-8">
            <h2 className="text-lg font-bold text-black border-b-2 border-black pb-2 mb-4">
              参考答案与解析
            </h2>
            <ol className="space-y-3 text-sm text-black leading-6">
              {questions.map((q, i) => (
                <li key={i} className="break-inside-avoid">
                  <span className="font-bold">{i + 1}.</span>{" "}
                  <span className="font-bold text-primary">{q.answer}</span>
                  <span className="text-gray-600 ml-2">（{q.knowledge_point}）</span>
                  {q.explanation && (
                    <span className="block text-gray-700 ml-4 mt-0.5">{q.explanation}</span>
                  )}
                </li>
              ))}
            </ol>
          </section>
        )}
      </div>

      <style dangerouslySetInnerHTML={{ __html: PRINT_CSS }} />
    </>
  );
}

function renderQuestionText(q: WorksheetQuestion): string {
  return q.question;
}

const PRINT_CSS = `
@media print {
  /* 基于 html.worksheet-print-mode 隐藏所有非试卷内容 */
  html.worksheet-print-mode body,
  html.worksheet-print-mode {
    background: white !important;
    margin: 0 !important;
    padding: 0 !important;
    min-height: auto !important;
    height: auto !important;
  }
  /* 隐藏底部导航 */
  html.worksheet-print-mode nav[aria-label="主导航"],
  html.worksheet-print-mode .fixed.bottom-0 {
    display: none !important;
  }
  /* 隐藏试卷预览页的顶栏操作条（返回/打印按钮） */
  html.worksheet-print-mode .no-print {
    display: none !important;
  }
  /* 隐藏所有 sticky 元素 */
  html.worksheet-print-mode header.sticky {
    display: none !important;
  }
  /* 试卷页面占满打印区域 */
  html.worksheet-print-mode .worksheet-page {
    max-width: none !important;
    width: 100% !important;
    padding: 0 !important;
    margin: 0 !important;
    min-height: auto !important;
    box-shadow: none !important;
    border: none !important;
    background: white !important;
  }
  /* 试卷外层容器去边距和背景 */
  html.worksheet-print-mode main,
  html.worksheet-print-mode .min-h-screen,
  html.worksheet-print-mode .bg-bg-soft,
  html.worksheet-print-mode .pb-20 {
    min-height: auto !important;
    padding: 0 !important;
    margin: 0 !important;
    background: white !important;
  }
  @page {
    size: A4;
    margin: 15mm 18mm;
  }
  .break-inside-avoid {
    break-inside: avoid;
  }
  .break-before-page,
  .answer-key {
    break-before: page;
  }
}
`;
