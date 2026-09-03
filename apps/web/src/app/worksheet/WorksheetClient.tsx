"use client";

import { useState, useMemo, useCallback, useEffect, type ReactNode } from "react";
import Link from "next/link";
import {
  type BookInfo,
  type WorksheetConfig,
  type WorksheetQuestion,
  type AIConfig,
  type ExamStructure,
  type ExamStructureSection,
  QUESTION_TYPE_LABELS,
  SUBJECT_LABELS,
  loadAIConfig,
  saveAIConfig,
  generateWorksheet,
} from "@/lib/worksheet";
import type { SubjectId, Outline } from "@cstf/core";
import { ArrowLeft } from "@/components/icons";
import { apiGet, type CustomBook, listExams, getExam, type Exam, DIFFICULTY_LABELS, getExamWithStructure } from "@/lib/customApi";

const SUBJECT_LIST: SubjectId[] = ["chinese", "math", "english", "science"];

const SUBJECT_COLORS: Record<SubjectId, string> = {
  chinese: "border-danger/40 bg-danger/10 text-danger-dark",
  math: "border-primary/40 bg-primary/10 text-primary-dark",
  english: "border-secondary/40 bg-secondary/10 text-secondary-dark",
  science: "border-warning/40 bg-warning/10 text-ink",
};

function getTypeLabel(type: string): string {
  return QUESTION_TYPE_LABELS[type] || type;
}

interface Props {
  books: BookInfo[];
}

export function WorksheetClient({ books }: Props) {
  const [customBooks, setCustomBooks] = useState<BookInfo[]>([]);
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
  const [exams, setExams] = useState<Exam[]>([]);
  const [selectedExamId, setSelectedExamId] = useState<string>("");
  const [mode, setMode] = useState<"unit_practice" | "exam_simulation">("unit_practice");
  const [examStructure, setExamStructure] = useState<ExamStructure | null>(null);

  // Fetch custom books and convert to BookInfo format
  useEffect(() => {
    (async () => {
      try {
        const data = await apiGet<{ books: CustomBook[] }>("books");
        const booksWithOutlines = await Promise.all(
          (data.books || []).map(async (b) => {
            try {
              const detail = await apiGet<CustomBook>(`books/${b.id}`);
              return detail;
            } catch {
              return null;
            }
          })
        );
        const converted: BookInfo[] = booksWithOutlines
          .filter((b): b is CustomBook => b !== null && !!b.units && b.units.length > 0)
          .map(b => ({
            id: `custom-${b.id}`,
            subject: b.subject as SubjectId,
            grade: b.grade,
            semester: b.semester as "up" | "down",
            textbookName: b.title,
            subjectName: SUBJECT_LABELS[b.subject as SubjectId] || b.subject,
            outline: { textbook: b.title, units: b.units! } as Outline,
            isCustom: true,
          }));
        setCustomBooks(converted);
      } catch {
        // Custom books API not available, skip silently
      }
    })();
    (async () => {
      try {
        const data = await listExams();
        setExams(data.filter(e => e.has_text));
      } catch {
        // Exams API not available, skip silently
      }
    })();
  }, []);

  // 当选中真题变化时，加载结构（真题仿真模式）
  useEffect(() => {
    if (mode !== "exam_simulation" || !selectedExamId) {
      setExamStructure(null);
      return;
    }
    (async () => {
      try {
        const { structure } = await getExamWithStructure(selectedExamId);
        setExamStructure(structure);
      } catch {
        setExamStructure(null);
      }
    })();
  }, [mode, selectedExamId]);

  const allBooks = useMemo(() => [...books, ...customBooks], [books, customBooks]);

  // 真题仿真模式下，过滤有结构的真题（全部年级时不按年级过滤）
  const examsForSimulation = useMemo(
    () => exams.filter(e => e.has_structure && e.subject === selectedSubject && (selectedGrade === 0 || e.grade === selectedGrade)),
    [exams, selectedSubject, selectedGrade],
  );

  const grades = useMemo(() => {
    const set = new Set(allBooks.filter(b => b.subject === selectedSubject).map(b => b.grade));
    return Array.from(set).sort((a, b) => a - b);
  }, [allBooks, selectedSubject]);

  const availableBooks = useMemo(
    () => allBooks.filter(b => b.subject === selectedSubject && b.grade === selectedGrade),
    [allBooks, selectedSubject, selectedGrade],
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
    const isAllGrade = selectedGrade === 0;

    if (!isAllGrade && !selectedBook) {
      setError("请先选择教材");
      return;
    }
    if (!aiConfig.apiKey) {
      setError("请先设置 AI 接口的 API Key");
      setShowAISettings(true);
      return;
    }

    let units: typeof selectedBookUnits;
    let textbookName: string;
    let bookId: string;

    if (isAllGrade) {
      // 全部年级模式：汇总该学科所有年级的 units
      const subjectBooks = allBooks.filter(b => b.subject === selectedSubject);
      units = subjectBooks.flatMap(b => b.outline.units);
      textbookName = `${SUBJECT_LABELS[selectedSubject]}全年级综合`;
      bookId = "all-grades";
    } else {
      const unitNumbers = Array.from(selectedUnits).sort((a, b) => a - b);
      units = unitNumbers.length === 0
        ? selectedBookUnits
        : selectedBookUnits.filter(u => selectedUnits.has(u.unit_number));
      textbookName = selectedBook!.textbookName;
      bookId = selectedBook!.id;
    }

    if (units.length === 0) {
      setError("该教材没有单元数据");
      return;
    }

    if (mode === "unit_practice") {
      const totalQ = Object.values(questionTypes).reduce((a, b) => a + b, 0);
      if (totalQ === 0) {
        setError("请至少选择一种题型");
        return;
      }
    }

    if (mode === "exam_simulation") {
      if (!selectedExamId) {
        setError("请选择一份真题试卷用于仿真");
        return;
      }
      if (!examStructure) {
        setError("该真题尚未分析结构，请先在真题详情页分析试卷结构");
        return;
      }
    }

    setGenerating(true);
    setError("");

    let examReference: string | undefined;
    if (selectedExamId) {
      try {
        const exam = await getExam(selectedExamId);
        if (exam.text_content) {
          examReference = exam.text_content;
        }
      } catch {
        // If we can't load the exam, continue without reference
      }
    }

    const config: WorksheetConfig = {
      mode,
      subject: selectedSubject,
      bookId,
      textbookName,
      unitNumbers: isAllGrade ? [] : Array.from(selectedUnits).sort((a, b) => a - b),
      questionTypes,
      difficultyMax,
      includeAnswerKey,
      examReference,
      examStructure: examStructure ?? undefined,
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
  }, [selectedBook, aiConfig, selectedUnits, selectedBookUnits, questionTypes, difficultyMax, includeAnswerKey, selectedSubject, selectedExamId, mode, examStructure, selectedGrade, allBooks]);

  if (showPreview && questions.length > 0) {
    return (
      <PrintPreview
        questions={questions}
        config={{
          mode,
          subject: selectedSubject,
          bookId: selectedGrade === 0 ? "all-grades" : (selectedBook?.id ?? ""),
          textbookName: selectedGrade === 0
            ? `${SUBJECT_LABELS[selectedSubject]}全年级综合`
            : (selectedBook?.textbookName ?? ""),
          unitNumbers: Array.from(selectedUnits).sort((a, b) => a - b),
          questionTypes,
          difficultyMax,
          includeAnswerKey,
          examStructure: examStructure ?? undefined,
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
        {/* 真题库入口 */}
        <Link
          href="/custom/exams"
          className="flex items-center gap-3 rounded-2xl border-2 border-warning/30 bg-warning/10 px-4 py-3.5 hover:bg-warning/20 transition-colors"
        >
          <span className="text-2xl">📝</span>
          <div className="flex-1 min-w-0">
            <p className="font-extrabold text-sm text-ink">真题库</p>
            <p className="text-xs text-ink-light">上传真题试卷，AI 仿照结构出题</p>
          </div>
          <span className="text-ink-softer">→</span>
        </Link>

        {/* 出题模式 */}
        <div className="bg-white rounded-2xl border-2 border-bg-softer p-4">
          <div className="grid grid-cols-2 gap-3">
            <button
              onClick={() => { setMode("unit_practice"); setSelectedExamId(""); }}
              className={`p-4 rounded-xl border-2 text-left transition-all ${
                mode === "unit_practice"
                  ? "border-primary bg-primary/10"
                  : "border-bg-softer hover:border-ink/20"
              }`}
            >
              <div className="text-lg mb-1">📚</div>
              <div className={`text-sm font-extrabold ${mode === "unit_practice" ? "text-primary-dark" : "text-ink"}`}>
                单元练习
              </div>
              <div className="text-xs text-ink-light mt-1">
                自选题型和数量，按知识点出题
              </div>
            </button>
            <button
              onClick={() => setMode("exam_simulation")}
              disabled={exams.filter(e => e.has_structure).length === 0}
              className={`p-4 rounded-xl border-2 text-left transition-all ${
                mode === "exam_simulation"
                  ? "border-secondary bg-secondary/10"
                  : "border-bg-softer hover:border-ink/20"
              } ${exams.filter(e => e.has_structure).length === 0 ? "opacity-50 cursor-not-allowed" : ""}`}
            >
              <div className="text-lg mb-1">📝</div>
              <div className={`text-sm font-extrabold ${mode === "exam_simulation" ? "text-secondary-dark" : "text-ink"}`}>
                真题仿真
              </div>
              <div className="text-xs text-ink-light mt-1">
                仿照真题结构，题型题数完全一致
              </div>
            </button>
          </div>
        </div>

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
                  setSelectedExamId("");
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
                  setSelectedExamId("");
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
            {mode === "exam_simulation" && (
              <button
                onClick={() => {
                  setSelectedGrade(0);
                  setSelectedBookId("");
                  setSelectedUnits(new Set());
                  setSelectedExamId("");
                }}
                className={`px-4 py-2.5 rounded-xl border-2 text-sm font-extrabold transition-all ${
                  selectedGrade === 0
                    ? "border-secondary bg-secondary/10 text-secondary-dark"
                    : "border-bg-softer bg-white text-ink-softer hover:border-ink/20"
                }`}
              >
                全部年级
              </button>
            )}
          </div>
          {mode === "exam_simulation" && selectedGrade === 0 && (
            <p className="text-xs text-ink-light mt-2">
              💡 升学/综合模式：AI 将融合该学科所有年级的知识点出题，适合毕业模拟、升学考试等场景。
            </p>
          )}
        </Section>

        {/* Step 3: 教材（全部年级模式下隐藏） */}
        {selectedGrade !== 0 && (
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
                  className={`px-4 py-2.5 rounded-xl border-2 text-sm font-bold transition-all flex items-center gap-1.5 ${
                    (selectedBookId || availableBooks[0]?.id) === b.id
                      ? "border-primary bg-primary/10 text-primary-dark"
                      : "border-bg-softer bg-white text-ink-softer hover:border-ink/20"
                  }`}
                >
                  {b.textbookName}
                  {b.isCustom && (
                    <span className="text-[10px] px-1.5 py-0.5 rounded bg-secondary/20 text-secondary-dark font-extrabold">自定义</span>
                  )}
                </button>
              ))}
            </div>
          )}
        </Section>
        )}

        {/* Step 4: 单元（全部年级模式下隐藏） */}
        {selectedGrade !== 0 && selectedBook && selectedBookUnits.length > 0 && (
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
            {mode === "exam_simulation" && (
              <p className="text-xs text-ink-light mt-2">
                💡 真题仿真模式下，知识点以上面选中的范围为主，允许出综合题。
              </p>
            )}
          </Section>
        )}

        {/* Step 5: 题型与数量（仅单元练习模式） */}
        {mode === "unit_practice" && (
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
        )}

        {/* Step 5: 选择真题（真题仿真模式） */}
        {mode === "exam_simulation" && (
          <Section step={5} title="选择真题试卷">
            {examsForSimulation.length === 0 ? (
              <p className="text-sm text-ink-light">
                该学科年级暂无已分析结构的真题。请先前往「自定义学习 → 真题库」上传并分析试卷结构。
              </p>
            ) : (
              <div className="space-y-2">
                {examsForSimulation.map(exam => (
                  <button
                    key={exam.id}
                    onClick={() => setSelectedExamId(exam.id)}
                    className={`w-full p-3 rounded-xl border-2 text-left transition-all ${
                      selectedExamId === exam.id
                        ? "border-secondary bg-secondary/10"
                        : "border-bg-softer bg-white hover:border-ink/20"
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <div className="flex-1 min-w-0">
                        <div className={`text-sm font-bold truncate ${selectedExamId === exam.id ? "text-secondary-dark" : "text-ink"}`}>
                          {exam.title}
                        </div>
                        <div className="text-xs text-ink-light mt-0.5">
                          {DIFFICULTY_LABELS[exam.difficulty as keyof typeof DIFFICULTY_LABELS] || exam.difficulty}
                        </div>
                      </div>
                      <div className="text-xs text-ink-light">
                        {exam.total_pages}页
                      </div>
                    </div>
                  </button>
                ))}
              </div>
            )}

            {examStructure && (
              <div className="mt-4 p-3 rounded-xl bg-bg-soft border border-bg-softer">
                <div className="text-xs font-bold text-ink mb-2">试卷结构</div>
                <div className="flex gap-3 mb-3 text-xs">
                  <span className="text-ink-light">总分：<span className="font-extrabold text-primary-dark">{examStructure.total_score}</span></span>
                  <span className="text-ink-light">时长：<span className="font-extrabold text-secondary-dark">{examStructure.duration_minutes}</span>分钟</span>
                  <span className="text-ink-light">大题：<span className="font-extrabold text-warning">{examStructure.sections.length}</span></span>
                </div>
                <div className="space-y-1.5">
                  {examStructure.sections.map((s, i) => (
                    <div key={i} className="flex items-center gap-2 text-xs">
                      <span className="w-5 h-5 rounded-full bg-primary text-white flex items-center justify-center font-extrabold flex-shrink-0 text-[10px]">
                        {i + 1}
                      </span>
                      <span className="text-ink font-bold flex-shrink-0">{s.name}</span>
                      <span className="text-ink-light">
                        {s.count}小题 · 共{s.total_score}分
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </Section>
        )}

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

        {/* Step 7: 参考真题（仅单元练习模式，且有真题时） */}
        {mode === "unit_practice" && exams.length > 0 && (
          <Section step={7} title="参考真题（可选）">
            <p className="text-xs text-ink-light mb-2">
              选择一份真题试卷，AI 将模仿其题型风格和难度出题
            </p>
            <select
              value={selectedExamId}
              onChange={e => setSelectedExamId(e.target.value)}
              className="w-full px-3 py-2 rounded-lg border-2 border-bg-softer text-sm text-ink bg-white focus:border-primary focus:outline-none"
            >
              <option value="">不使用参考真题</option>
              {exams.map(exam => (
                <option key={exam.id} value={exam.id}>
                  {exam.title}（{SUBJECT_LABELS[exam.subject as SubjectId] || exam.subject} · {exam.grade}年级 · {DIFFICULTY_LABELS[exam.difficulty as keyof typeof DIFFICULTY_LABELS] || exam.difficulty}）
                </option>
              ))}
            </select>
          </Section>
        )}

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
                  placeholder="https://aiapi.fonken.net/v1"
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
                  placeholder="gemini-3.1-flash-lite"
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
    const html = document.documentElement;
    html.classList.add("worksheet-print-mode");
    return () => {
      html.classList.remove("worksheet-print-mode");
    };
  }, []);

  const subjectLabel = SUBJECT_LABELS[config.subject] || config.subject;
  const unitText = config.unitNumbers.length === 0
    ? "全册"
    : config.unitNumbers.map(n => `第${n}单元`).join("、");

  const totalScore = questions.reduce((acc, q) => acc + q.score, 0);
  const duration = config.examStructure?.duration_minutes || 0;

  // 按大题分组（真题仿真模式用 section_index，单元练习模式用 type）
  const sections = useMemo(() => {
    if (config.mode === "exam_simulation" && config.examStructure) {
      return config.examStructure.sections.map((section, idx) => {
        const sectionQuestions = questions.filter(q => q.section_index === idx);
        return {
          name: section.name,
          type: section.type,
          questions: sectionQuestions.length > 0 ? sectionQuestions : questions.filter(q => q.type === section.type),
          totalScore: section.total_score,
          description: section.description,
        };
      });
    }

    // 单元练习模式：按 type 分组
    const groups: Record<string, WorksheetQuestion[]> = {};
    for (const q of questions) {
      if (!groups[q.type]) groups[q.type] = [];
      groups[q.type].push(q);
    }
    const typeOrder = ["true_false", "choice", "fill_blank_text", "short_answer"];
    return typeOrder
      .filter(t => groups[t]?.length > 0)
      .map(t => ({
        name: QUESTION_TYPE_LABELS[t] || t,
        type: t,
        questions: groups[t],
        totalScore: groups[t].reduce((a, q) => a + q.score, 0),
        description: "",
      }));
  }, [questions, config.mode, config.examStructure]);

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
      <div className="worksheet-page max-w-[210mm] mx-auto bg-white px-6 py-6 md:px-12 md:py-8">
        {/* 试卷头 */}
        <div className="text-center mb-6">
          <h1 className="text-2xl font-bold text-black tracking-wide">
            {subjectLabel}{config.mode === "exam_simulation" ? "仿真试卷" : "练习试卷"}
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
          <span>时间：{duration > 0 ? `${duration} 分钟` : "______ 分钟"}</span>
        </div>

        {/* 试卷说明 */}
        <div className="text-sm text-gray-700 mb-6">
          <span>满分 {totalScore} 分 · 考试时间 {duration > 0 ? `${duration} 分钟` : "______ 分钟"}</span>
        </div>

        {/* 题目 - 按大题渲染 */}
        {sections.map((section, si) => {
          const qs = section.questions;
          if (!qs || qs.length === 0) return null;
          return (
            <section key={si} className="mb-8 break-inside-avoid">
              <h2 className="text-base font-bold text-black border-b border-gray-400 pb-1 mb-4">
                {section.name}（共 {qs.length} 题，{section.totalScore} 分）
              </h2>
              {section.description && (
                <p className="text-xs text-gray-600 mb-3">{section.description}</p>
              )}
              <ol className="space-y-4 text-sm text-black leading-7">
                {qs.map((q, i) => (
                  <QuestionItem key={i} q={q} index={i + 1} />
                ))}
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

      <style dangerouslySetInnerHTML={{ __html: PRINT_CSS }} className="no-print" />
    </>
  );
}

function QuestionItem({ q, index }: { q: WorksheetQuestion; index: number }) {
  // 不同题型的答题区渲染
  const renderAnswerArea = () => {
    // 选择题
    if (q.type === "choice" && q.options.length > 0) {
      return (
        <div className="grid grid-cols-2 gap-x-6 gap-y-1 mt-1.5 ml-4">
          {q.options.map((opt, oi) => (
            <div key={oi}>
              {"ABCD"[oi]}. {opt.replace(/^[A-Da-d][.、．]\s*/, "")}
            </div>
          ))}
        </div>
      );
    }

    // 判断题
    if (q.type === "true_false") {
      return (
        <div className="mt-1.5 ml-4 text-gray-500">
          <span className="border-b border-gray-400 px-4">&nbsp;</span>
          （对 / 错）
        </div>
      );
    }

    // 填空题
    if (q.type === "fill_blank" || q.type === "fill_blank_text" || q.type === "fill_in_the_blanks") {
      return (
        <div className="mt-2 text-xs text-gray-400">答：</div>
      );
    }

    // 计算题
    if (q.type === "calculation") {
      return (
        <div className="mt-3 ml-4 border-b border-gray-300 h-20">&nbsp;</div>
      );
    }

    // 应用题 / 解决问题 / 简答题
    if (q.type === "application" || q.type === "word_problem" || q.type === "short_answer" || q.type === "reading_comprehension") {
      return (
        <div className="mt-3 ml-4 border-b border-gray-300 h-24">&nbsp;</div>
      );
    }

    // 作文
    if (q.type === "composition") {
      return (
        <div className="mt-3 ml-4 space-y-1">
          <div className="border-b border-gray-300 h-16">&nbsp;</div>
          <div className="border-b border-gray-300 h-16">&nbsp;</div>
          <div className="border-b border-gray-300 h-16">&nbsp;</div>
        </div>
      );
    }

    // 默认：留一行答题空间
    return (
      <div className="mt-2 ml-4 border-b border-gray-300 h-12">&nbsp;</div>
    );
  };

  return (
    <li className="break-inside-avoid">
      <div className="flex gap-2">
        <span className="font-bold flex-shrink-0">{index}.</span>
        <div className="flex-1">
          <div>{q.question}</div>
          {renderAnswerArea()}
        </div>
        <span className="text-xs text-gray-500 flex-shrink-0">({q.score}分)</span>
      </div>
    </li>
  );
}

const PRINT_CSS = `
@media print {
  /* 强制覆盖暗色模式：白底黑字 */
  html.worksheet-print-mode,
  html.worksheet-print-mode.theme-dark {
    color-scheme: light !important;
    --app-bg: #FFFFFF !important;
    --app-bg-soft: #F7F7F7 !important;
    --app-bg-softer: #E5E5E5 !important;
    --app-ink: #4B4B4B !important;
    --app-ink-light: #777777 !important;
    --app-ink-softer: #AFAFAF !important;
    background: white !important;
    height: auto !important;
    min-height: 0 !important;
    max-height: none !important;
  }
  html.worksheet-print-mode body {
    background: white !important;
    color: #4B4B4B !important;
    margin: 0 !important;
    padding: 0 !important;
    min-height: 0 !important;
    height: auto !important;
    max-height: none !important;
    overflow: visible !important;
  }
  /* 隐藏所有非试卷元素 */
  html.worksheet-print-mode nav[aria-label="主导航"],
  html.worksheet-print-mode .no-print {
    display: none !important;
  }
  /* 试卷容器 */
  html.worksheet-print-mode .worksheet-page {
    max-width: none !important;
    width: 100% !important;
    padding: 0 !important;
    margin: 0 !important;
    min-height: 0 !important;
    height: auto !important;
    max-height: none !important;
    box-shadow: none !important;
    border: none !important;
    background: white !important;
    color: black !important;
  }
  /* 移除所有外层容器的边距和最小高度 */
  html.worksheet-print-mode main,
  html.worksheet-print-mode .min-h-screen,
  html.worksheet-print-mode .bg-bg-soft,
  html.worksheet-print-mode .pb-20 {
    min-height: 0 !important;
    height: auto !important;
    max-height: none !important;
    padding: 0 !important;
    margin: 0 !important;
    background: white !important;
  }
  /* 确保所有文字在白底上可见 */
  html.worksheet-print-mode * {
    color: black !important;
  }
  html.worksheet-print-mode .text-primary,
  html.worksheet-print-mode .text-danger {
    color: #4B4B4B !important;
  }
  /* 避免 section 底部 margin 造成空白页 */
  html.worksheet-print-mode section:last-child {
    margin-bottom: 0 !important;
    padding-bottom: 0 !important;
  }
  html.worksheet-print-mode .answer-key:last-child {
    margin-bottom: 0 !important;
  }
  /* 消除试卷容器末尾可能的空白页 */
  html.worksheet-print-mode .worksheet-page > *:last-child {
    margin-bottom: 0 !important;
  }
  @page {
    size: A4;
    margin: 15mm 18mm;
  }
  .break-inside-avoid {
    break-inside: avoid;
  }
  .answer-key {
    break-before: page;
  }
}
`;
